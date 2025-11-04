# Fan-Out on Write Implementation

## Overview

This document explains the **fan-out on write** architecture implementation for the microblog application. This is a critical performance optimization that makes feed queries 10-40x faster by pre-computing feed entries when posts are created.

**Target Audience**: Software engineers new to this architecture pattern
**Prerequisites**: Understanding of Rails models, background jobs, and database indexes
**Status**: ✅ Implemented and ready for production

---

## Table of Contents

1. [What is Fan-Out on Write?](#what-is-fan-out-on-write)
2. [Why Do We Need It?](#why-do-we-need-it)
3. [How Does It Work?](#how-does-it-work)
4. [Architecture Overview](#architecture-overview)
5. [Implementation Details](#implementation-details)
6. [Database Schema](#database-schema)
7. [Performance Benefits](#performance-benefits)
8. [Trade-offs and Considerations](#trade-offs-and-considerations)
9. [Testing Guide](#testing-guide)
10. [Troubleshooting](#troubleshooting)

---

## What is Fan-Out on Write?

**Fan-out on write** (also called "push model") is an architecture pattern where we **pre-compute** data when it's created, rather than computing it on every read request.

### The Problem It Solves

**Traditional Approach (Pull Model)**:
```
User requests feed
  ↓
Query: JOIN posts + follows tables
  ↓
Filter: posts.author_id IN (followed_user_ids)
  ↓
Sort and paginate
  ↓
Return results (50-200ms)
```

**Problem**: Every feed request requires a complex JOIN query that grows slower as users follow more people.

**Fan-Out Solution (Push Model)**:
```
User creates post
  ↓
Insert post (5-15ms)
  ↓
Background job: Fan-out to followers
  ↓
For each follower: INSERT INTO feed_entries
  ↓
User requests feed
  ↓
Query: SELECT * FROM feed_entries WHERE user_id = ?
  ↓
Return results (5-20ms)
```

**Solution**: Pre-compute feed entries when posts are created. Feed queries become simple, fast lookups.

---

## Why Do We Need It?

### Current Performance Issues

1. **Slow Feed Queries**: 50-200ms per request
2. **Scalability Limit**: Works well up to ~5,000 follows per user
3. **Database Load**: Complex JOINs on every feed request
4. **Growing Complexity**: Query time increases with follow count

### Real-World Impact

**Example: User with 2,505 followers**
- Feed query time: 50-200ms
- Posts to consider: ~375,750 posts (2,505 users × 150 posts)
- Database operations: Complex JOIN + filter + sort

**Example: User with 10,000 followers**
- Feed query time: 200-500ms+ (becomes unusable)
- Posts to consider: ~1.5M posts
- Database operations: Very expensive JOIN

### Fan-Out Benefits

1. **10-40x Faster**: Feed queries become 5-20ms (vs 50-200ms)
2. **Better Scalability**: Works for users with 10,000+ follows
3. **Predictable Performance**: Query time doesn't depend on follow count
4. **Reduced Database Load**: Simple queries instead of complex JOINs

---

## How Does It Work?

### Step-by-Step Flow

#### 1. Post Creation (Write Path)

```
User creates post
  ↓
Post.save → Post created in database
  ↓
after_create callback triggers
  ↓
FanOutFeedJob.perform_later(post_id)
  ↓
Background job processes:
  - Get all followers of post author
  - Create FeedEntry record for each follower
  - Bulk insert for efficiency
  ↓
Feed entries ready for feed queries
```

**Key Points**:
- ✅ Post creation is fast (doesn't wait for fan-out)
- ✅ Fan-out happens asynchronously in background
- ✅ User doesn't experience any delay

#### 2. Feed Request (Read Path)

```
User requests feed
  ↓
User.feed_posts called
  ↓
Check if FeedEntry exists for this user
  ↓
If yes: Query feed_entries table (fast path)
  ↓
SELECT posts.* FROM posts
INNER JOIN feed_entries ON posts.id = feed_entries.post_id
WHERE feed_entries.user_id = ?
ORDER BY feed_entries.created_at DESC
  ↓
Return results (5-20ms)
```

**Key Points**:
- ✅ Simple query (no complex JOINs)
- ✅ Uses index on (user_id, created_at)
- ✅ Fast and predictable

#### 3. Follow/Unfollow Actions

**When User A follows User B:**
```
User A follows User B
  ↓
Follow relationship created
  ↓
BackfillFeedJob.perform_later(user_a_id, user_b_id)
  ↓
Background job:
  - Get last 50 posts from User B
  - Create FeedEntry records for User A
  ↓
User A's feed now includes User B's recent posts
```

**When User A unfollows User B:**
```
User A unfollows User B
  ↓
Follow relationship deleted
  ↓
FeedEntry.remove_for_user_from_author(user_a_id, user_b_id)
  ↓
All feed entries from User B removed from User A's feed
```

---

## Architecture Overview

### Database Schema

```
┌─────────────┐
│   users     │
│─────────────│
│ id          │
│ username    │
│ ...         │
└─────────────┘
      │
      │ 1:N
      │
┌─────────────┐      ┌─────────────┐
│   posts     │      │ feed_entries│
│─────────────│      │─────────────│
│ id          │◄─────┤ user_id     │ (follower)
│ author_id   │      │ post_id     │
│ content     │      │ author_id   │ (denormalized)
│ created_at  │      │ created_at  │ (denormalized)
│ ...         │      │ ...         │
└─────────────┘      └─────────────┘
      │                      │
      │                      │ N:1
      │                      │
      └──────────────────────┘
```

### Key Components

1. **FeedEntry Model**: Represents a pre-computed feed entry
2. **FanOutFeedJob**: Background job to create feed entries when posts are created
3. **BackfillFeedJob**: Background job to backfill feed entries when users follow someone
4. **User#feed_posts**: Updated to use feed entries (with fallback)

---

## Implementation Details

### 1. FeedEntry Model

**Location**: `app/models/feed_entry.rb`

**Purpose**: Represents a pre-computed feed entry (a post that should appear in a user's feed)

**Key Methods**:
- `bulk_insert_for_post(post, follower_ids)`: Bulk insert feed entries
- `remove_for_user_from_author(user_id, author_id)`: Remove entries when unfollowing
- `remove_for_post(post_id)`: Remove entries when post is deleted

**Example**:
```ruby
# Create feed entry manually
FeedEntry.create!(
  user_id: 123,      # The follower who will see this
  post_id: 456,      # The post to show
  author_id: 789,    # The post author (denormalized)
  created_at: post.created_at
)

# Bulk insert for efficiency
FeedEntry.bulk_insert_for_post(post, [1, 2, 3, 4, 5])
```

### 2. FanOutFeedJob

**Location**: `app/jobs/fan_out_feed_job.rb`

**Purpose**: Create feed entries for all followers when a post is created

**Trigger**: `Post.after_create :fan_out_to_followers`

**Performance**:
- For user with 100 followers: ~50-100ms
- For user with 5,000 followers: ~500-1000ms
- Runs asynchronously, so user doesn't wait

**Example**:
```ruby
# Automatically triggered when post is created
post = Post.create!(author: user, content: "Hello!")
# FanOutFeedJob is enqueued automatically

# Or manually:
FanOutFeedJob.perform_later(post.id)
```

### 3. BackfillFeedJob

**Location**: `app/jobs/backfill_feed_job.rb`

**Purpose**: Backfill recent posts when a user follows someone

**Trigger**: `User#follow` method

**Why Backfill?**
- When User A follows User B, User B's existing posts aren't in User A's feed yet
- We backfill the last 50 posts so the new follower sees recent content
- Older posts will appear naturally as new posts are created

**Example**:
```ruby
# Automatically triggered when user follows someone
user_a.follow(user_b)
# BackfillFeedJob is enqueued automatically

# Or manually:
BackfillFeedJob.perform_later(user_a.id, user_b.id)
```

### 4. Updated User#feed_posts

**Location**: `app/models/user.rb`

**Strategy**: Dual-path approach
1. **Fast path**: Use feed entries if they exist
2. **Fallback path**: Use JOIN-based query if no feed entries (during migration)

**Why Fallback?**
- Ensures feed works during migration period
- Allows gradual rollout
- Handles edge cases where feed entries might not exist

**Example**:
```ruby
user = User.find(1)
posts = user.feed_posts  # Automatically uses feed entries if available
```

---

## Database Schema

### FeedEntries Table

**Columns**:
- `user_id` (bigint): The follower who will see this post
- `post_id` (bigint): The post to show in the feed
- `author_id` (bigint): Denormalized author ID (for efficient cleanup)
- `created_at` (datetime): Denormalized post creation time (for sorting)
- `updated_at` (datetime): Timestamp

**Indexes**:
1. `(user_id, created_at DESC)`: Primary query index (feed lookups)
2. `(user_id, post_id) UNIQUE`: Prevents duplicate entries
3. `post_id`: For cleanup when post is deleted
4. `(user_id, author_id)`: For cleanup when user unfollows

**Foreign Keys**:
- `user_id` → `users.id` (CASCADE DELETE)
- `post_id` → `posts.id` (CASCADE DELETE)
- `author_id` → `users.id` (CASCADE DELETE)

### Why Denormalization?

**Denormalized Fields**:
- `author_id`: Allows quick removal of all entries from an author when unfollowing
- `created_at`: Allows sorting without JOINing to posts table

**Benefits**:
- ✅ Faster queries (no JOINs needed)
- ✅ Efficient cleanup (can filter by author_id)
- ✅ Predictable performance

**Trade-off**:
- ⚠️ More storage (denormalized data)
- ⚠️ Must keep in sync (handled by application logic)

---

## Performance Benefits

### Query Performance Comparison

| Metric | Pull Model (JOIN) | Fan-Out (Feed Entries) | Improvement |
|--------|-------------------|------------------------|-------------|
| **Query Time** | 50-200ms | 5-20ms | **10-40x faster** |
| **Complexity** | O(F × log(P)) | O(log(N)) | Much simpler |
| **Scalability** | Up to 5k follows | 10k+ follows | **2x+ better** |
| **Predictability** | Varies with follows | Constant | More predictable |

**Where**:
- F = number of follows
- P = number of posts
- N = number of feed entries

### Real-World Example

**User with 2,505 followers:**

**Before (Pull Model)**:
- Query: JOIN posts + follows tables
- Time: 50-200ms
- Posts considered: ~375,750 posts
- Database operations: Complex JOIN + filter + sort

**After (Fan-Out)**:
- Query: SELECT FROM feed_entries WHERE user_id = ?
- Time: 5-20ms
- Feed entries: ~20-50 entries per page
- Database operations: Simple index lookup

**Result**: **10-40x faster** feed loading

### Storage Impact

**Storage Calculation**:
- Average follows per user: 2,505
- Posts per user: ~150
- Feed entries per post: ~2,505 (number of followers)
- Total feed entries: ~1.5M posts × 2,505 = ~3.75B entries
- Storage per entry: ~40 bytes
- **Total storage: ~150 GB**

**Management**:
- Archive old entries (older than 30 days)
- Lazy backfill (only active followers)
- Partitioning by date (future optimization)

---

## Trade-offs and Considerations

### Advantages ✅

1. **Extremely Fast Reads**: Feed queries become O(log(N)) instead of O(F × log(P))
2. **Predictable Performance**: Query time doesn't depend on follow count
3. **Better Scalability**: Works for users with 10,000+ follows
4. **Simpler Queries**: No complex JOINs needed
5. **Better Caching**: Can cache feed entries easily
6. **Real-time Consistency**: Users see posts immediately (after fan-out completes)

### Disadvantages ⚠️

1. **Storage Overhead**:
   - 65x increase in storage (150 GB vs 2.3 GB)
   - **Solution**: Archive old entries, lazy backfill

2. **Write Complexity**:
   - Must fan-out to all followers
   - Background job overhead (50-500ms)
   - **Solution**: Batch inserts, async processing

3. **Consistency Challenges**:
   - Feed entries must be updated if post is deleted
   - Unfollow must clean up entries
   - **Solution**: Cascading deletes, cleanup jobs

4. **Initial Implementation**:
   - Must backfill existing feeds
   - Migration complexity
   - **Solution**: Gradual migration, backfill script

### When to Use Fan-Out

**Use Fan-Out When**:
- ✅ Feed queries are slow (>50ms)
- ✅ Users follow many people (>1,000)
- ✅ Feed is the primary use case
- ✅ Read operations >> Write operations

**Don't Use Fan-Out When**:
- ❌ Feed queries are already fast (<10ms)
- ❌ Users follow few people (<100)
- ❌ Storage is extremely limited
- ❌ Write operations >> Read operations

---

## Testing Guide

### Manual Testing

#### 1. Test Post Creation with Fan-Out

```ruby
rails console

# Create a user with followers
author = User.first
followers = User.limit(5).where.not(id: author.id)

# Make followers follow author
followers.each { |f| f.follow(author) }

# Create a post
post = author.posts.create!(content: "Test post")

# Wait for job to process (or run manually)
FanOutFeedJob.perform_now(post.id)

# Check feed entries were created
FeedEntry.where(post_id: post.id).count
# Should equal number of followers

# Check followers' feeds include the post
followers.each do |follower|
  posts = follower.feed_posts
  puts "Follower #{follower.id}: #{posts.include?(post) ? 'HAS' : 'MISSING'} post"
end
```

#### 2. Test Feed Query Performance

```ruby
rails console

require 'benchmark'

user = User.first

# Clear cache
Rails.cache.clear

# Test feed query with feed entries
time = Benchmark.realtime do
  posts = user.feed_posts.limit(20).to_a
end

puts "Feed query time: #{(time * 1000).round(2)}ms"
puts "Posts found: #{posts.count}"
```

#### 3. Test Follow/Unfollow

```ruby
rails console

user_a = User.first
user_b = User.second

# Follow
user_a.follow(user_b)

# Wait for backfill (or run manually)
BackfillFeedJob.perform_now(user_a.id, user_b.id)

# Check feed entries
FeedEntry.where(user_id: user_a.id, author_id: user_b.id).count
# Should show recent posts from user_b

# Unfollow
user_a.unfollow(user_b)

# Check feed entries removed
FeedEntry.where(user_id: user_a.id, author_id: user_b.id).count
# Should be 0
```

### Automated Testing

See `spec/models/feed_entry_spec.rb` and `spec/jobs/fan_out_feed_job_spec.rb` for comprehensive test coverage.

---

## Troubleshooting

### Feed Entries Not Created

**Symptom**: Posts created but no feed entries

**Check**:
1. Is Solid Queue running? `bin/rails solid_queue:start`
2. Check job queue: Visit `/jobs` (Mission Control)
3. Check job logs: `log/solid_queue.log`
4. Run job manually: `FanOutFeedJob.perform_now(post.id)`

**Solution**:
```ruby
# Manually trigger fan-out
post = Post.find(post_id)
FanOutFeedJob.perform_now(post.id)
```

### Feed Query Still Slow

**Symptom**: Feed queries taking 50-200ms after implementation

**Check**:
1. Are feed entries being used? `FeedEntry.exists?(user_id: user.id)`
2. Check query: `user.feed_posts.to_sql`
3. Verify indexes: `rails db:migrate:status`

**Solution**:
```ruby
# Check if feed entries exist
user = User.find(user_id)
FeedEntry.where(user_id: user.id).count

# If 0, backfill:
BackfillFeedJob.perform_now(user.id, followed_user.id)
```

### Storage Growing Too Fast

**Symptom**: `feed_entries` table growing very large

**Check**:
```sql
SELECT COUNT(*) FROM feed_entries;
SELECT pg_size_pretty(pg_total_relation_size('feed_entries'));
```

**Solution**:
```ruby
# Archive old entries (older than 30 days)
FeedEntry.where("created_at < ?", 30.days.ago).delete_all

# Or create recurring job:
ArchiveOldFeedEntriesJob.perform_later
```

### Duplicate Feed Entries

**Symptom**: Same post appears multiple times in feed

**Check**:
```sql
SELECT user_id, post_id, COUNT(*)
FROM feed_entries
GROUP BY user_id, post_id
HAVING COUNT(*) > 1;
```

**Solution**: Unique index prevents this, but if it happens:
```ruby
# Remove duplicates
FeedEntry.group(:user_id, :post_id).having("COUNT(*) > 1").each do |entry|
  FeedEntry.where(user_id: entry.user_id, post_id: entry.post_id)
           .offset(1)
           .delete_all
end
```

---

## Summary

**Fan-out on write** is a powerful architecture pattern that makes feed queries **10-40x faster** by pre-computing feed entries when posts are created.

**Key Takeaways**:
- ✅ Pre-compute data on write (not on read)
- ✅ Use background jobs for async processing
- ✅ Denormalize for performance
- ✅ Handle edge cases (follow/unfollow, deletions)
- ✅ Monitor storage and archive old entries

**Next Steps**:
1. Backfill existing feeds (see `script/backfill_existing_feeds.rb`)
2. Monitor performance improvements
3. Archive old entries regularly
4. Consider partitioning for very large datasets

For more details, see:
- `docs/028_SCALING_AND_PERFORMANCE_STRATEGIES.md` (strategy overview)
- `app/models/feed_entry.rb` (model implementation)
- `app/jobs/fan_out_feed_job.rb` (fan-out job)
- `app/jobs/backfill_feed_job.rb` (backfill job)

