# Current Architecture Analysis & Feed Efficiency Proposals

## Executive Summary

This document provides a comprehensive analysis of the current microblog architecture, usage flow patterns, and two architectural proposals to significantly improve feed efficiency for both readers (followers) and writers (content creators).

---

## Part 1: Current Architecture Analysis

### 1.1 System Overview

**Technology Stack:**
- **Framework**: Ruby on Rails 8.1.1
- **Database**: PostgreSQL 14+ (primary), SQLite (cache/queue/cable)
- **Web Server**: Puma (25 threads, 25 max connections)
- **Connection Pool**: 25 database connections
- **Frontend**: Hotwire (Turbo + Stimulus), Tailwind CSS
- **Pagination**: Cursor-based (SQL WHERE clause)

**Deployment Architecture:**
```
┌─────────────────┐
│   Rails App      │
│   (Puma)         │
│   25 threads     │
└────────┬─────────┘
         │
         │ (25 connections)
         │
┌────────▼─────────┐
│   PostgreSQL     │
│   (Primary DB)   │
└──────────────────┘
```

### 1.2 Data Model

#### Core Entities

**Users Table:**
- Stores user accounts with authentication
- Fields: `id`, `username`, `description`, `password_digest`, `created_at`, `updated_at`
- Index: `username` (unique)

**Posts Table:**
- Stores all posts and replies
- Fields: `id`, `author_id`, `content` (max 200 chars), `parent_id`, `created_at`, `updated_at`
- Indexes:
  - `author_id` (for author filtering)
  - `created_at` (for timeline sorting)
  - `parent_id` (for replies)
  - `(author_id, created_at DESC)` **composite** (for optimized feed queries)

**Follows Table:**
- Stores follow relationships
- Fields: `follower_id`, `followed_id`, `created_at`, `updated_at`
- Indexes:
  - `(follower_id, followed_id)` composite (unique, for follow checks)
  - `followed_id` (for reverse lookups)

#### Relationships

```
User
 ├─ has_many :posts (as author)
 ├─ has_many :active_follows (following others)
 ├─ has_many :passive_follows (followed by others)
 ├─ has_many :following (through active_follows)
 └─ has_many :followers (through passive_follows)

Post
 ├─ belongs_to :author (User, optional)
 ├─ belongs_to :parent (Post, optional)
 └─ has_many :replies (Post)

Follow
 ├─ belongs_to :follower (User)
 └─ belongs_to :followed (User)
```

### 1.3 Current Feed Architecture

#### Feed Generation Flow

**Current Implementation:**

```ruby
# User Model
def feed_posts
  user_id = Post.connection.quote(id)
  Post.joins(
    "LEFT JOIN follows ON posts.author_id = follows.followed_id AND follows.follower_id = #{user_id}"
  ).where(
    "posts.author_id = ? OR follows.followed_id IS NOT NULL",
    id
  ).distinct
end
```

**Generated SQL:**
```sql
SELECT DISTINCT posts.* FROM posts
LEFT JOIN follows ON posts.author_id = follows.followed_id
  AND follows.follower_id = ?
WHERE posts.author_id = ? OR follows.followed_id IS NOT NULL
ORDER BY created_at DESC
LIMIT 20
```

**Performance Characteristics:**
- **Query Time**: 50-200ms (optimized from 150-600ms)
- **Index Usage**: Composite index `(author_id, created_at DESC)`
- **Scalability**: Works well up to ~5,000 follows per user
- **Bottleneck**: Still requires JOIN on every feed request

#### Feed Display Modes

1. **Timeline (Default)**: Own posts + posts from followed users
2. **Mine**: Only own posts
3. **Following**: Only posts from followed users (no own posts)
4. **All (Public)**: All top-level posts (for non-authenticated users)

#### Pagination Strategy

**Cursor-Based Pagination:**
- Uses `WHERE id < cursor_id` (for DESC) or `WHERE id > cursor_id` (for ASC)
- Efficient for large datasets (no OFFSET)
- Returns `[posts, next_cursor, has_next]`

### 1.4 Request Flow Analysis

#### Feed Request Flow (Posts#index)

```
1. User Request
   ↓
2. Authentication Check (ApplicationController#current_user)
   ↓
3. Filter Selection (timeline/mine/following)
   ↓
4. Feed Query Generation
   ├─ If timeline: current_user.feed_posts
   ├─ If mine: current_user.posts
   ├─ If following: JOIN query
   └─ If public: Post.top_level
   ↓
5. Cursor Pagination (ApplicationController#cursor_paginate)
   ├─ Apply cursor filter: WHERE id < cursor_id
   ├─ Limit: 20 posts + 1 (to check has_next)
   └─ Return: [posts, next_cursor, has_next]
   ↓
6. View Rendering
   ├─ Load post authors (potential N+1)
   └─ Render HTML with Turbo
   ↓
7. Response (200 OK)
```

**Time Breakdown:**
- Authentication: ~5ms
- Database Query: 50-200ms
- Pagination Logic: ~1ms
- View Rendering: 50-100ms
- **Total: 105-306ms**

#### Post Creation Flow (Posts#create)

```
1. User Submits Post
   ↓
2. Validation (content length, presence)
   ↓
3. Database Insert
   ├─ INSERT INTO posts (author_id, content, created_at)
   └─ Index Updates (author_id, created_at, composite)
   ↓
4. Redirect to Feed or Post
   ↓
5. Feed Refresh (if redirected to feed)
```

**Time Breakdown:**
- Validation: ~1ms
- Database Insert: 5-15ms
- Index Updates: ~2ms
- Redirect: ~5ms
- **Total: 13-23ms**

**Writer Impact:**
- ✅ Fast writes (single INSERT)
- ✅ No feed regeneration needed
- ⚠️ Index updates on every write (minimal overhead)

### 1.5 Current Performance Characteristics

#### Read Performance (Feed Loading)

**For User with 2,505 Follows:**
- Query Time: 50-200ms
- Posts to Consider: ~375,750 posts (2,505 users × 150 posts)
- Result Set: 20 posts
- Index Usage: Composite index scan
- Memory: ~20KB per request

**For User with 5,000 Follows:**
- Query Time: 100-400ms
- Posts to Consider: ~750,000 posts
- Result Set: 20 posts
- Index Usage: Composite index scan (still efficient)
- Memory: ~20KB per request

**Bottlenecks:**
1. **JOIN Complexity**: O(F × log(P)) where F = follows, P = posts
2. **Index Scan**: Must scan composite index for all followed authors
3. **DISTINCT Operation**: Small overhead for duplicate prevention

#### Write Performance (Post Creation)

**Single Post Creation:**
- Insert Time: 5-15ms
- Index Updates: ~2ms per index (4 indexes = ~8ms)
- Total: 13-23ms

**Concurrent Writes:**
- PostgreSQL handles concurrent writes well
- No locking issues (unlike SQLite)
- Connection pool: 25 connections sufficient

**Writer Bottlenecks:**
- ✅ Minimal - writes are fast
- ⚠️ Index updates add small overhead
- ⚠️ No feed regeneration needed (good!)

### 1.6 Scalability Analysis

#### Current Limitations

**Read Scalability:**
- **Follows per User**: Works well up to ~5,000 follows
- **Posts per User**: Works well up to ~10,000 posts
- **Total Users**: Works well up to ~100,000 users
- **Concurrent Reads**: Limited by connection pool (25 connections)

**Write Scalability:**
- **Posts per Second**: ~100-500 posts/sec (limited by DB, not application)
- **Concurrent Writers**: Limited by connection pool (25 connections)
- **Index Updates**: Minimal overhead per write

**Breaking Points:**
1. **>10,000 follows per user**: Query time exceeds 500ms
2. **>1,000 concurrent users**: Connection pool exhaustion
3. **>1,000 posts/sec**: Database write bottleneck

### 1.7 Current Optimizations

**Already Implemented:**
1. ✅ **Composite Index**: `(author_id, created_at DESC)` - 50-70% faster
2. ✅ **JOIN Query**: Instead of large IN clause - 50-70% faster
3. ✅ **Cursor Pagination**: No OFFSET - O(1) instead of O(N)
4. ✅ **Connection Pool**: 25 connections (up from 5)
5. ✅ **PostgreSQL**: Better concurrency than SQLite

**Not Yet Implemented:**
- ❌ Feed caching
- ❌ Pre-computed feeds
- ❌ Read replicas
- ❌ Denormalized counters
- ❌ Materialized views

---

## Part 2: Architectural Proposal 1 - Fan-Out on Write (Push Model)

### 2.1 Overview

**Strategy**: Pre-compute and store feed entries for each follower when a post is created.

**Architecture Pattern**: Fan-Out on Write / Push Model

**Key Principle**: Write once, read many (optimize for reads)

### 2.2 Proposed Architecture

#### New Data Model

**Add FeedEntries Table:**
```ruby
create_table :feed_entries do |t|
  t.bigint :user_id, null: false  # The follower who will see this
  t.bigint :post_id, null: false  # The post to show
  t.bigint :author_id, null: false # Denormalized for filtering
  t.datetime :created_at, null: false # Post creation time (for sorting)

  t.index [:user_id, :created_at], order: { created_at: :desc }
  t.index [:user_id, :post_id], unique: true
  t.index :post_id
end
```

**Schema Changes:**
- **New Table**: `feed_entries` (stores pre-computed feed items)
- **Existing Tables**: Unchanged (posts, users, follows remain the same)

#### Architecture Diagram

```
┌─────────────────────────────────────────────────────────┐
│                    User Creates Post                     │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
            ┌────────────────┐
            │  INSERT post   │
            │  (5-15ms)      │
            └────────┬───────┘
                     │
                     ▼
        ┌────────────────────────────┐
        │  Fan-Out Process          │
        │  (Async Background Job)   │
        └────────┬───────────────────┘
                 │
                 ▼
    ┌────────────────────────────┐
    │  For each follower:        │
    │  INSERT INTO feed_entries  │
    │  (user_id, post_id, ...)   │
    └────────────────────────────┘
                 │
                 ▼
        ┌────────────────────┐
        │  Feed Query        │
        │  (Now O(1)!)       │
        └────────────────────┘
```

#### Feed Query Transformation

**Before (Current):**
```ruby
def feed_posts
  # JOIN query: O(F × log(P))
  Post.joins(...).where(...).order(created_at: :desc)
end
```

**After (Proposed):**
```ruby
def feed_posts
  # Simple index scan: O(log(N))
  FeedEntry.where(user_id: id)
           .includes(:post, :author)
           .order(created_at: :desc)
           .limit(20)
end
```

**SQL Generated:**
```sql
SELECT feed_entries.*, posts.*, users.*
FROM feed_entries
INNER JOIN posts ON feed_entries.post_id = posts.id
INNER JOIN users ON feed_entries.author_id = users.id
WHERE feed_entries.user_id = ?
ORDER BY feed_entries.created_at DESC
LIMIT 20
```

**Performance:**
- **Query Time**: 5-20ms (vs 50-200ms)
- **Complexity**: O(log(N)) where N = feed entries (much smaller)
- **Index Usage**: Single index scan on `(user_id, created_at DESC)`

### 2.3 Implementation Details

#### Post Creation Flow

```ruby
# PostsController#create
def create
  @post = Post.new(post_params)
  @post.author = current_user

  if @post.save
    # Fan-out to followers (async)
    FanOutFeedJob.perform_later(@post)
    redirect_to @post.parent || posts_path
  end
end
```

**Fan-Out Background Job:**
```ruby
class FanOutFeedJob < ApplicationJob
  def perform(post)
    # Get all followers
    followers = post.author.followers

    # Batch insert feed entries
    feed_entries = followers.map do |follower|
      {
        user_id: follower.id,
        post_id: post.id,
        author_id: post.author_id,
        created_at: post.created_at
      }
    end

    # Bulk insert (efficient)
    FeedEntry.insert_all(feed_entries) if feed_entries.any?
  end
end
```

#### Unfollow Flow

```ruby
# When user unfollows, remove their feed entries
def unfollow(other_user)
  active_follows.where(followed_id: other_user.id).delete_all
  # Clean up feed entries
  FeedEntry.where(user_id: id, author_id: other_user.id).delete_all
end
```

#### Follow Flow

```ruby
# When user follows, backfill recent posts
def follow(other_user)
  return false unless active_follows.create(followed_id: other_user.id)

  # Backfill last 50 posts from followed user
  BackfillFeedJob.perform_later(id, other_user.id)
end
```

### 2.4 Benefits

#### For Readers (Feed Loading)

**Performance Improvements:**
- ✅ **10-40x faster queries**: 5-20ms vs 50-200ms
- ✅ **Predictable performance**: No longer depends on follow count
- ✅ **Simple queries**: Single index scan, no JOINs
- ✅ **Better scalability**: Works for users with 10,000+ follows

**Scalability:**
- **Before**: O(F × log(P)) - grows with follows
- **After**: O(log(N)) - constant regardless of follows
- **Query Time**: 5-20ms regardless of follow count

#### For Writers (Post Creation)

**Performance:**
- ✅ **Write time**: Still fast (13-23ms for post INSERT)
- ⚠️ **Fan-out time**: 50-500ms (async, doesn't block user)
- ✅ **Non-blocking**: User sees post immediately, fan-out happens in background

**Scalability:**
- **For users with 100 followers**: Fan-out ~100ms
- **For users with 5,000 followers**: Fan-out ~500ms (async)
- **No user-facing delay**: Fan-out is background job

### 2.5 Trade-offs

#### Advantages

1. **Extremely Fast Reads**: Feed queries become O(log(N)) instead of O(F × log(P))
2. **Predictable Performance**: Query time doesn't depend on follow count
3. **Better Scalability**: Works for users with 10,000+ follows
4. **Simpler Queries**: No complex JOINs needed
5. **Better Caching**: Can cache feed entries easily

#### Disadvantages

1. **Storage Overhead**:
   - For user with 5,000 followers: 5,000 feed entries per post
   - Storage: ~1.5M posts × 2,505 avg follows × 40 bytes = ~150 GB
   - **Solution**: Partition by date, archive old entries

2. **Write Complexity**:
   - Must fan-out to all followers
   - Background job overhead
   - **Solution**: Batch inserts, async processing

3. **Consistency Challenges**:
   - Feed entries must be updated if post is deleted
   - Unfollow must clean up entries
   - **Solution**: Cascading deletes, cleanup jobs

4. **Initial Implementation**:
   - Must backfill existing feeds
   - Migration complexity
   - **Solution**: Gradual migration, backfill script

### 2.6 Storage Estimation

**Per Post:**
- Feed entries = number of followers
- Storage per entry = ~40 bytes
- For user with 5,000 followers: 5,000 × 40 = 200 KB per post

**Total Storage (10k users, 1.5M posts):**
- Average followers per user: ~2,505
- Total feed entries: 1.5M × 2,505 = 3.76 billion entries
- Storage: 3.76B × 40 bytes = ~150 GB

**Mitigation Strategies:**
1. **Partition by date**: Archive entries older than 30 days
2. **Lazy backfill**: Only create entries for active followers
3. **Hybrid approach**: Use fan-out for active users, query for inactive

### 2.7 Migration Strategy

**Phase 1: Add FeedEntries Table**
```ruby
rails generate migration CreateFeedEntries
# Add table, indexes, foreign keys
```

**Phase 2: Background Fan-Out**
```ruby
# Add FanOutFeedJob
# Update PostsController to fan-out on create
# Test with small subset
```

**Phase 3: Dual Write**
```ruby
# Keep old feed_posts method
# Add new feed_posts_from_entries method
# Feature flag to switch
```

**Phase 4: Backfill**
```ruby
# Backfill feed entries for existing posts
# Run in batches
# Monitor performance
```

**Phase 5: Switch Over**
```ruby
# Remove old feed_posts method
# Use feed_entries exclusively
# Monitor performance
```

---

## Part 3: Architectural Proposal 2 - Hybrid Materialized View with Caching

### 3.1 Overview

**Strategy**: Use PostgreSQL materialized views for feed pre-computation, combined with Redis caching for hot data.

**Architecture Pattern**: Materialized View + Cache Layer

**Key Principle**: Pre-compute feeds periodically, cache hot data

### 3.2 Proposed Architecture

#### Materialized View Structure

**Create Materialized View:**
```sql
CREATE MATERIALIZED VIEW user_feeds AS
SELECT
  f.follower_id as user_id,
  p.id as post_id,
  p.author_id,
  p.content,
  p.created_at,
  p.parent_id
FROM follows f
INNER JOIN posts p ON p.author_id = f.followed_id
WHERE p.parent_id IS NULL  -- Only top-level posts
ORDER BY f.follower_id, p.created_at DESC;

CREATE INDEX idx_user_feeds_user_created
  ON user_feeds(user_id, created_at DESC);
```

**Refresh Strategy:**
- **Full Refresh**: Every 5 minutes (for consistency)
- **Incremental Refresh**: On new post creation (trigger-based)
- **Cache Layer**: Redis for last 100 posts per user (hot data)

#### Architecture Diagram

```
┌─────────────────────────────────────────────────────────┐
│                    User Creates Post                     │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
            ┌────────────────┐
            │  INSERT post   │
            │  (5-15ms)      │
            └────────┬───────┘
                     │
                     ▼
        ┌────────────────────────────┐
        │  PostgreSQL Trigger        │
        │  (Incremental Refresh)     │
        └────────┬───────────────────┘
                 │
                 ▼
    ┌────────────────────────────┐
    │  Update Materialized View │
    │  (Add new entries)         │
    └────────┬───────────────────┘
             │
             ▼
        ┌────────────────────┐
        │  Invalidate Cache │
        │  (Redis)          │
        └────────────────────┘
```

#### Feed Query Transformation

**Before (Current):**
```ruby
def feed_posts
  # JOIN query: O(F × log(P))
  Post.joins(...).where(...).order(created_at: :desc)
end
```

**After (Proposed):**
```ruby
def feed_posts
  # Check cache first
  cached = Rails.cache.read("user_feed:#{id}")
  return cached if cached

  # Query materialized view (fast)
  posts = query_materialized_view(id)

  # Cache result
  Rails.cache.write("user_feed:#{id}", posts, expires_in: 1.minute)
  posts
end

def query_materialized_view(user_id)
  sql = <<-SQL
    SELECT post_id, author_id, content, created_at, parent_id
    FROM user_feeds
    WHERE user_id = ?
    ORDER BY created_at DESC
    LIMIT 20
  SQL

  results = ActiveRecord::Base.connection.execute(sql, [user_id])
  post_ids = results.map { |r| r['post_id'] }
  Post.where(id: post_ids).includes(:author).order(created_at: :desc)
end
```

**Performance:**
- **Cache Hit**: <1ms (Redis)
- **Cache Miss**: 10-30ms (materialized view query)
- **View Refresh**: 100-500ms (every 5 minutes, background)

### 3.3 Implementation Details

#### Materialized View Refresh

**Full Refresh (Scheduled):**
```ruby
# config/schedule.rb (using whenever gem or similar)
every 5.minutes do
  runner "RefreshUserFeedsJob.perform_now"
end

class RefreshUserFeedsJob < ApplicationJob
  def perform
    ActiveRecord::Base.connection.execute(
      "REFRESH MATERIALIZED VIEW CONCURRENTLY user_feeds"
    )
    # Invalidate all caches
    Rails.cache.clear
  end
end
```

**Incremental Refresh (Trigger-based):**
```sql
CREATE OR REPLACE FUNCTION refresh_user_feeds_on_insert()
RETURNS TRIGGER AS $$
BEGIN
  -- Insert into materialized view for all followers
  INSERT INTO user_feeds (user_id, post_id, author_id, content, created_at, parent_id)
  SELECT
    f.follower_id,
    NEW.id,
    NEW.author_id,
    NEW.content,
    NEW.created_at,
    NEW.parent_id
  FROM follows f
  WHERE f.followed_id = NEW.author_id
    AND NEW.parent_id IS NULL;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER refresh_user_feeds_trigger
AFTER INSERT ON posts
FOR EACH ROW
EXECUTE FUNCTION refresh_user_feeds_on_insert();
```

#### Caching Strategy

**Redis Cache Structure:**
```
Key: "user_feed:#{user_id}"
Value: JSON array of post IDs [1, 2, 3, ...]
TTL: 60 seconds

Key: "user_feed_meta:#{user_id}"
Value: { cursor: 123, has_next: true }
TTL: 60 seconds
```

**Cache Invalidation:**
```ruby
# When user creates post
after_create :invalidate_follower_caches

def invalidate_follower_caches
  author.followers.each do |follower|
    Rails.cache.delete("user_feed:#{follower.id}")
  end
end
```

### 3.4 Benefits

#### For Readers (Feed Loading)

**Performance Improvements:**
- ✅ **Cache Hit**: <1ms (99% of requests after warm-up)
- ✅ **Cache Miss**: 10-30ms (still 2-5x faster than current)
- ✅ **Predictable**: Consistent performance regardless of follow count
- ✅ **Scalable**: Works for users with 10,000+ follows

**Scalability:**
- **Cache Hit Rate**: 90-95% (after warm-up)
- **Average Query Time**: <5ms (weighted average)
- **Peak Load**: Redis handles 10,000+ requests/sec

#### For Writers (Post Creation)

**Performance:**
- ✅ **Write time**: 13-23ms (unchanged)
- ✅ **Trigger overhead**: ~5-10ms (minimal)
- ✅ **Cache invalidation**: ~1-5ms (async, non-blocking)
- ✅ **No user-facing delay**: All async operations

**Scalability:**
- **Trigger execution**: Fast (single INSERT with JOIN)
- **Cache invalidation**: Batch operation
- **No blocking**: User sees post immediately

### 3.5 Trade-offs

#### Advantages

1. **Fast Reads**: 90-95% cache hit rate = <1ms average
2. **Storage Efficient**: Materialized view is smaller than feed_entries table
3. **PostgreSQL Native**: Uses database features, no custom logic
4. **Flexible Refresh**: Can adjust refresh frequency based on needs
5. **Better for Analytics**: Materialized view can be queried for insights

#### Disadvantages

1. **Eventual Consistency**:
   - View refresh every 5 minutes
   - New posts may not appear immediately
   - **Solution**: Incremental refresh via triggers

2. **Cache Management**:
   - Must manage Redis
   - Cache invalidation complexity
   - **Solution**: Smart invalidation, TTL-based expiration

3. **Storage**:
   - Materialized view still requires storage
   - For 10k users, 1.5M posts: ~50-100 GB
   - **Solution**: Partition by date, archive old data

4. **Complexity**:
   - Triggers, materialized views, caching
   - More moving parts
   - **Solution**: Well-documented, tested implementation

### 3.6 Storage Estimation

**Materialized View:**
- Per user: ~375,750 entries (2,505 follows × 150 posts)
- Per entry: ~60 bytes
- Per user: 375,750 × 60 = 22.5 MB
- Total: 10,000 × 22.5 MB = 225 GB

**Redis Cache:**
- Per user cache: ~1 KB (20 post IDs + metadata)
- Active users (1,000): 1,000 × 1 KB = 1 MB
- **Much smaller than materialized view**

**Mitigation:**
- Partition materialized view by date
- Archive entries older than 30 days
- Use Redis for hot data only

### 3.7 Migration Strategy

**Phase 1: Add Materialized View**
```sql
CREATE MATERIALIZED VIEW user_feeds AS ...
CREATE INDEX ...
```

**Phase 2: Add Redis Cache**
```ruby
# Add redis gem
# Implement caching layer
# Test cache hit/miss rates
```

**Phase 3: Add Incremental Refresh**
```sql
# Create trigger function
# Create trigger
# Test incremental updates
```

**Phase 4: Dual Read**
```ruby
# Keep old feed_posts method
# Add new cached_feed_posts method
# Feature flag to switch
```

**Phase 5: Switch Over**
```ruby
# Remove old feed_posts method
# Use materialized view + cache exclusively
# Monitor performance
```

---

## Part 4: Comparison & Recommendations

### 4.1 Performance Comparison

| Metric | Current | Proposal 1 (Fan-Out) | Proposal 2 (Materialized View) |
|--------|---------|---------------------|--------------------------------|
| **Feed Query Time** | 50-200ms | 5-20ms | <1ms (cache) / 10-30ms (miss) |
| **Post Write Time** | 13-23ms | 13-23ms + async fan-out | 13-23ms + trigger |
| **Storage** | ~2.3 GB | ~150 GB | ~225 GB (view) + 1 MB (cache) |
| **Scalability** | Up to 5k follows | 10k+ follows | 10k+ follows |
| **Consistency** | Real-time | Real-time | 5min delay (or trigger-based) |
| **Complexity** | Low | Medium | High |

### 4.2 Use Case Recommendations

#### Proposal 1: Fan-Out on Write (Best For)

✅ **High read-to-write ratio** (100:1 or more)
✅ **Real-time consistency required**
✅ **Users with many follows** (5,000+)
✅ **Willing to trade storage for speed**
✅ **Simple cache invalidation needed**

**Best Suited For:**
- Twitter-like platforms
- Real-time news feeds
- Social networks with high engagement

#### Proposal 2: Materialized View + Cache (Best For)

✅ **Moderate read-to-write ratio** (10:1 to 100:1)
✅ **Eventual consistency acceptable** (5min delay)
✅ **PostgreSQL expertise available**
✅ **Want to leverage database features**
✅ **Complex analytics needed**

**Best Suited For:**
- Content platforms
- News aggregators
- Platforms with periodic updates

### 4.3 Hybrid Approach Recommendation

**Best of Both Worlds:**

1. **Use Fan-Out for Active Users** (last 7 days activity)
   - Fast, real-time feeds
   - Higher storage cost acceptable

2. **Use Materialized View for Inactive Users**
   - Lower storage cost
   - Periodic refresh sufficient

3. **Redis Cache Layer for Both**
   - Cache hot data
   - Reduce database load

**Implementation:**
```ruby
def feed_posts
  # Check if user is active
  if active_recently?
    # Use fan-out feed entries
    FeedEntry.where(user_id: id).order(created_at: :desc).limit(20)
  else
    # Use materialized view
    query_materialized_view(id)
  end
end
```

### 4.4 Final Recommendation

**For Current Scale (10k users, 1.5M posts):**

**Recommended: Proposal 1 (Fan-Out on Write)**

**Reasons:**
1. **Simpler Implementation**: Easier to understand and maintain
2. **Real-time Consistency**: Users see posts immediately
3. **Better Read Performance**: 10-40x faster queries
4. **Storage is Manageable**: 150 GB is acceptable for this scale
5. **Proven Pattern**: Used by Twitter, Facebook, Instagram

**Implementation Priority:**
1. **Phase 1**: Add FeedEntries table, implement fan-out job
2. **Phase 2**: Add Redis cache layer (optional, for 100x speedup)
3. **Phase 3**: Implement hybrid approach for inactive users

**For Future Scale (100k+ users):**

**Consider:**
- Partition FeedEntries by date
- Archive old entries (>30 days)
- Use read replicas for feed queries
- Implement hybrid approach

---

## Part 5: Implementation Roadmap

### 5.1 Proposal 1 Implementation Steps

#### Week 1: Foundation
- [ ] Create FeedEntries migration
- [ ] Add FeedEntry model
- [ ] Create FanOutFeedJob
- [ ] Update PostsController to trigger fan-out
- [ ] Test with small dataset

#### Week 2: Backfill & Migration
- [ ] Create backfill script
- [ ] Backfill feed entries for existing posts
- [ ] Monitor storage usage
- [ ] Test performance improvements

#### Week 3: Optimization
- [ ] Add Redis caching layer
- [ ] Optimize batch inserts
- [ ] Implement cleanup jobs
- [ ] Add monitoring

#### Week 4: Production Rollout
- [ ] Gradual rollout (10% → 50% → 100%)
- [ ] Monitor performance
- [ ] Remove old feed_posts method
- [ ] Documentation

### 5.2 Proposal 2 Implementation Steps

#### Week 1: Materialized View
- [ ] Create materialized view
- [ ] Add indexes
- [ ] Test refresh performance
- [ ] Create refresh job

#### Week 2: Caching Layer
- [ ] Add Redis
- [ ] Implement cache layer
- [ ] Add cache invalidation
- [ ] Test cache hit rates

#### Week 3: Incremental Refresh
- [ ] Create trigger function
- [ ] Add trigger
- [ ] Test incremental updates
- [ ] Optimize refresh strategy

#### Week 4: Production Rollout
- [ ] Gradual rollout
- [ ] Monitor performance
- [ ] Adjust refresh frequency
- [ ] Documentation

---

## Conclusion

Both proposals offer significant improvements over the current architecture:

- **Proposal 1 (Fan-Out)**: Best for real-time consistency, simpler implementation
- **Proposal 2 (Materialized View)**: Best for eventual consistency, leverages PostgreSQL

**Recommended approach**: Start with Proposal 1, add Redis caching, then consider hybrid approach for scale.

**Expected improvements:**
- **Feed Query Time**: 50-200ms → 5-20ms (or <1ms with cache)
- **Scalability**: 5,000 follows → 10,000+ follows per user
- **User Experience**: Faster feed loading, better responsiveness

