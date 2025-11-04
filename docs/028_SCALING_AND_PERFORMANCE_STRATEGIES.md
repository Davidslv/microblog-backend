# Scaling and Performance Strategies

## Overview

This document covers comprehensive strategies for scaling the microblog application, including caching, rate limiting, fan-out on write, read replicas, and connection pooling. Each strategy is explained with implementation details, pros/cons, and recommendations.

---

## Table of Contents

1. [Caching with Solid Cache](#1-caching-with-solid-cache)
2. [Rate Limiting](#2-rate-limiting)
3. [Fan-Out on Write](#3-fan-out-on-write)
4. [Read Replicas](#4-read-replicas)
5. [PgBouncer Connection Pooling](#5-pgbouncer-connection-pooling)

---

## 1. Caching with Solid Cache

### What is Solid Cache?

Solid Cache is Rails 8's built-in database-backed caching solution. It stores cached data in a database (SQLite by default, PostgreSQL supported) rather than requiring a separate Redis/Memcached server.

### Current Implementation

**Status**: ✅ Already configured in production
```ruby
# config/environments/production.rb
config.cache_store = :solid_cache_store
```

**Storage**: Uses SQLite database (`storage/production_cache.sqlite3`)

### Why Use Caching?

**Performance Benefits:**
- **Reduce Database Load**: Cache expensive queries (feed queries, user profiles)
- **Faster Response Times**: Serve cached data in <1ms vs 50-200ms
- **Better Scalability**: Handle more concurrent requests
- **Cost Savings**: Reduce database CPU/memory usage

**Current Performance Context:**
- Feed queries: 50-200ms (see `docs/017_ARCHITECTURE_AND_FEED_PROPOSALS.md`)
- User profile: 67ms (after counter cache, see `docs/027_COUNTER_CACHE_PERFORMANCE_REPORT.md`)
- Timeline scope: Requires JOIN on follows table (50-200ms)

### Where to Apply Caching

#### 1. Feed Queries (HIGHEST PRIORITY)

**Why**: Feed queries are the most expensive and frequent operations.

**Current Query Performance:**
```ruby
# User#feed_posts - 50-200ms per request
def feed_posts
  Post.joins("LEFT JOIN follows ON ...")
      .where("posts.author_id = ? OR follows.followed_id IS NOT NULL", id)
      .distinct
      .order(created_at: :desc)
end
```

**Caching Strategy:**
```ruby
# app/models/user.rb
def feed_posts
  Rails.cache.fetch("user_feed:#{id}", expires_in: 5.minutes) do
    user_id = Post.connection.quote(id)
    Post.joins(
      "LEFT JOIN follows ON posts.author_id = follows.followed_id AND follows.follower_id = #{user_id}"
    ).where(
      "posts.author_id = ? OR follows.followed_id IS NOT NULL",
      id
    ).distinct
  end
end
```

**Cache Key Strategy:**
- **Key**: `"user_feed:#{user_id}:#{cursor}"`
- **TTL**: 5 minutes (balance between freshness and performance)
- **Invalidation**: On post creation by followed users, on follow/unfollow

**Expected Performance:**
- **Cache Hit**: <1ms (vs 50-200ms)
- **Cache Miss**: 50-200ms (same as before)
- **Cache Hit Rate**: 80-90% (after warm-up)

**Invalidation Logic:**
```ruby
# app/models/post.rb
after_create :fan_out_to_followers

def fan_out_to_followers
  # Fan-out to followers via background job
  # Cache will expire naturally via TTL (5 minutes)
  # Note: delete_matched was removed from Rails 8
  FanOutFeedJob.perform_later(id)
end
```

#### 2. User Profile Pages (MEDIUM PRIORITY)

**Why**: Already fast (67ms), but can be improved further.

**Current Performance:**
- User profile: 67ms (with counter caches)
- Posts query: 17.2ms ActiveRecord time

**Caching Strategy:**
```ruby
# app/controllers/users_controller.rb
def show
  @user = Rails.cache.fetch("user:#{params[:id]}", expires_in: 1.hour) do
    User.find(params[:id])
  end

  @posts, @next_cursor, @has_next = Rails.cache.fetch(
    "user_posts:#{params[:id]}:#{params[:cursor]}",
    expires_in: 5.minutes
  ) do
    cursor_paginate(
      @user.posts.top_level.timeline,
      per_page: 20
    )
  end

  @followers_count = @user.followers_count
  @following_count = @user.following_count
end
```

**Expected Performance:**
- **Cache Hit**: <10ms (vs 67ms)
- **Cache Miss**: 67ms (same as before)
- **Cache Hit Rate**: 70-80%

#### 3. Public Posts Feed (LOW PRIORITY)

**Why**: Non-authenticated users see public posts, can cache aggressively.

**Caching Strategy:**
```ruby
# app/controllers/posts_controller.rb
def index
  if current_user.nil?
    @posts, @next_cursor, @has_next = Rails.cache.fetch(
      "public_posts:#{params[:cursor]}",
      expires_in: 1.minute
    ) do
      cursor_paginate(Post.top_level.timeline, per_page: 20)
    end
  else
    # ... existing authenticated logic
  end
end
```

**Expected Performance:**
- **Cache Hit**: <1ms
- **Cache Miss**: 20-50ms
- **Cache Hit Rate**: 95%+ (public content changes less frequently)

### Implementation Options

#### Option A: Solid Cache (Current - Recommended)

**Pros:**
- ✅ **No Additional Infrastructure**: Uses existing database
- ✅ **Rails Native**: Built into Rails 8, no extra gems
- ✅ **Simple Setup**: Already configured
- ✅ **Persistence**: Survives server restarts
- ✅ **ACID Compliance**: Database transactions for cache operations
- ✅ **Cost Effective**: No separate Redis server needed

**Cons:**
- ❌ **Slower than Redis**: SQLite/PostgreSQL slower than in-memory Redis
- ❌ **Database Load**: Cache operations add load to main database
- ❌ **Limited Features**: No pub/sub, no advanced data structures
- ❌ **Scalability**: Harder to scale horizontally (need shared database)

**Performance:**
- Read: ~1-5ms (vs Redis <1ms)
- Write: ~2-10ms (vs Redis <1ms)
- Suitable for: Small to medium scale (1-100k users)

#### Option B: Redis Cache

**Pros:**
- ✅ **Fastest**: In-memory, <1ms operations
- ✅ **Rich Features**: Pub/sub, advanced data structures, Lua scripts
- ✅ **Horizontal Scaling**: Can use Redis Cluster
- ✅ **High Throughput**: 100k+ operations/second
- ✅ **Industry Standard**: Widely used, well-documented

**Cons:**
- ❌ **Additional Infrastructure**: Requires Redis server
- ❌ **Memory Intensive**: All data in RAM
- ❌ **Complexity**: Need to manage Redis separately
- ❌ **Cost**: Additional server/instance
- ❌ **Persistence Options**: Need to configure RDB/AOF for durability

**Performance:**
- Read: <1ms
- Write: <1ms
- Suitable for: Medium to large scale (100k+ users, high traffic)

#### Option C: Hybrid Approach

**Strategy**: Use Solid Cache for development/test, Redis for production.

**Pros:**
- ✅ **Best of Both**: Simple dev/test, fast production
- ✅ **Flexible**: Can switch based on environment
- ✅ **Cost Optimized**: No Redis needed in dev

**Cons:**
- ❌ **Environment Differences**: Different behavior in dev vs prod
- ❌ **Complexity**: Need to manage both

**Implementation:**
```ruby
# config/environments/development.rb
config.cache_store = :solid_cache_store

# config/environments/production.rb
config.cache_store = :redis_cache_store, {
  url: ENV['REDIS_URL'],
  expires_in: 1.hour
}
```

### Cache Invalidation Strategies

#### 1. Time-Based Expiration (TTL)

**Simple but effective:**
```ruby
Rails.cache.fetch("key", expires_in: 5.minutes) do
  # expensive operation
end
```

**Pros:**
- ✅ Simple to implement
- ✅ Automatic cleanup
- ✅ No invalidation logic needed

**Cons:**
- ❌ Stale data for up to TTL duration
- ❌ May serve outdated content

#### 2. Explicit Invalidation

**More control, more complexity:**
```ruby
# On post creation
# Note: delete_matched removed from Rails 8
# Cache expires naturally via TTL (5 minutes)
# With fan-out, feed entries are the source of truth

# On follow/unfollow
# Feed entries are updated directly, cache expires via TTL
```

**Pros:**
- ✅ Immediate freshness
- ✅ No stale data
- ✅ Granular control

**Cons:**
- ❌ More code to maintain
- ❌ Risk of missed invalidations
- ❌ Complex invalidation chains

#### 3. Version-Based Invalidation

**Use version numbers:**
```ruby
cache_key = "user_feed:#{user_id}:#{user.feed_version}"
Rails.cache.fetch(cache_key) do
  # expensive operation
end

# On invalidation
user.increment!(:feed_version)
```

**Pros:**
- ✅ Automatic cleanup of old versions
- ✅ Good for distributed systems
- ✅ Can track cache effectiveness

**Cons:**
- ❌ Need to add version column
- ❌ More complex logic

### Recommended Caching Strategy

**For Current Scale (1M users):**

1. **Start with Solid Cache** (already configured)
   - Cache feed queries: 5-minute TTL
   - Cache user profiles: 1-hour TTL
   - Cache public posts: 1-minute TTL

2. **Add Explicit Invalidation**
   - Invalidate feed cache on post creation
   - Invalidate feed cache on follow/unfollow
   - Use background jobs for invalidation (don't block requests)

3. **Monitor Performance**
   - Track cache hit rates
   - Monitor cache size
   - Measure performance improvements

4. **Consider Redis for Production**
   - If cache hit rate is high but performance still insufficient
   - If need for pub/sub or advanced features
   - If horizontal scaling is required

---

## 2. Rate Limiting

### What is Rate Limiting?

Rate limiting restricts the number of requests a user or IP can make within a time window. It prevents abuse, protects against DDoS attacks, and ensures fair resource usage.

### Why Rate Limiting is Needed

**Protection Against:**
1. **API Abuse**: Malicious users spamming requests
2. **DDoS Attacks**: Flooding servers with requests
3. **Resource Exhaustion**: Preventing one user from consuming all resources
4. **Fair Usage**: Ensuring all users get fair access

**Current Vulnerabilities:**
- No rate limiting on post creation
- No rate limiting on follow/unfollow
- No rate limiting on feed requests
- Connection pool (25) can be exhausted by single user

### Implementation Options

#### Option A: Rack::Attack (Recommended)

**What**: Middleware gem for rate limiting in Rails.

**Installation:**
```ruby
# Gemfile
gem 'rack-attack'
```

**Configuration:**
```ruby
# config/initializers/rack_attack.rb
class Rack::Attack
  # Throttle all requests by IP
  throttle('req/ip', limit: 300, period: 5.minutes) do |req|
    req.ip
  end

  # Throttle post creation by user
  throttle('posts/create', limit: 10, period: 1.minute) do |req|
    if req.path == '/posts' && req.post?
      req.session['user_id'] || req.ip
    end
  end

  # Throttle follow/unfollow by user
  throttle('follows/create', limit: 50, period: 1.hour) do |req|
    if req.path.start_with?('/follow') && (req.post? || req.delete?)
      req.session['user_id'] || req.ip
    end
  end

  # Throttle feed requests by user
  throttle('feed/requests', limit: 100, period: 1.minute) do |req|
    if req.path == '/posts' && req.get?
      req.session['user_id'] || req.ip
    end
  end
end
```

**Response Customization:**
```ruby
# config/initializers/rack_attack.rb
Rack::Attack.throttled_response = lambda do |env|
  match_data = env['rack.attack.match_data']
  now = match_data[:epoch_time]

  headers = {
    'Content-Type' => 'application/json',
    'X-RateLimit-Limit' => match_data[:limit].to_s,
    'X-RateLimit-Remaining' => '0',
    'X-RateLimit-Reset' => (now + (match_data[:period] - now % match_data[:period])).to_s
  }

  [429, headers, [{ error: 'Rate limit exceeded' }.to_json]]
end
```

**Pros:**
- ✅ **Rails Native**: Works seamlessly with Rails
- ✅ **Flexible**: Highly configurable
- ✅ **Multiple Stores**: Redis, Memcached, or memory
- ✅ **Mature**: Widely used, well-tested
- ✅ **Granular Control**: Can limit by IP, user, path, etc.

**Cons:**
- ❌ **Requires Redis**: For distributed systems (can use memory for single server)
- ❌ **Middleware Overhead**: Adds small latency to every request
- ❌ **Configuration Complexity**: Need to tune limits carefully

**Storage Options:**
```ruby
# Option 1: Redis (recommended for production)
Rack::Attack.cache.store = ActiveSupport::Cache::RedisCacheStore.new(url: ENV['REDIS_URL'])

# Option 2: Memory (development/single server)
Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new

# Option 3: Solid Cache (can use existing cache store)
Rack::Attack.cache.store = Rails.cache
```

#### Option B: Application-Level Rate Limiting

**What**: Custom rate limiting in controllers/models.

**Implementation:**
```ruby
# app/models/concerns/rate_limitable.rb
module RateLimitable
  extend ActiveSupport::Concern

  class_methods do
    def rate_limit(action, limit:, period:)
      # Store rate limit data in cache
      key = "rate_limit:#{self.class.name}:#{action}:#{id}"
      count = Rails.cache.read(key) || 0

      if count >= limit
        raise RateLimitExceeded, "Rate limit exceeded for #{action}"
      end

      Rails.cache.write(key, count + 1, expires_in: period)
    end
  end
end

# app/controllers/posts_controller.rb
def create
  current_user.rate_limit(:create_post, limit: 10, period: 1.minute)

  @post = Post.new(post_params)
  # ... rest of create logic
rescue RateLimitExceeded => e
  render json: { error: e.message }, status: 429
end
```

**Pros:**
- ✅ **Full Control**: Complete control over logic
- ✅ **No Dependencies**: Uses existing cache store
- ✅ **Flexible**: Can implement custom rules

**Cons:**
- ❌ **More Code**: Need to implement and maintain
- ❌ **Error Handling**: Need to handle exceptions
- ❌ **Testing**: Need to write tests
- ❌ **Less Efficient**: Middleware is faster

#### Option C: Cloudflare/NGINX Rate Limiting

**What**: Rate limiting at the infrastructure level.

**Pros:**
- ✅ **No Application Load**: Blocked before reaching Rails
- ✅ **DDoS Protection**: Can handle massive attacks
- ✅ **Geographic Filtering**: Can block by country/IP range
- ✅ **Configuration**: Centralized configuration

**Cons:**
- ❌ **Less Granular**: Harder to limit by user vs IP
- ❌ **Infrastructure Dependency**: Need to configure proxy/load balancer
- ❌ **Cost**: Cloudflare Pro/Enterprise for advanced features

### Recommended Rate Limits

**For Microblog Application:**

```ruby
# config/initializers/rack_attack.rb
Rack::Attack.throttle('req/ip', limit: 300, period: 5.minutes)

# Post creation: 10 posts per minute per user
Rack::Attack.throttle('posts/create', limit: 10, period: 1.minute) do |req|
  req.session['user_id'] if req.path == '/posts' && req.post?
end

# Follow/unfollow: 50 actions per hour per user
Rack::Attack.throttle('follows/action', limit: 50, period: 1.hour) do |req|
  req.session['user_id'] if req.path.start_with?('/follow')
end

# Feed requests: 100 requests per minute per user
Rack::Attack.throttle('feed/requests', limit: 100, period: 1.minute) do |req|
  req.session['user_id'] if req.path == '/posts' && req.get?
end

# Search/API: 60 requests per minute per IP
Rack::Attack.throttle('api/requests', limit: 60, period: 1.minute) do |req|
  req.ip if req.path.start_with?('/api')
end
```

### Implementation Recommendation

**For Current Scale:**

1. **Start with Rack::Attack** using Solid Cache
   - Simple setup, no additional infrastructure
   - Can migrate to Redis later if needed
   - Use memory store for development

2. **Implement Key Limits:**
   - Post creation: 10/min
   - Follow/unfollow: 50/hour
   - Feed requests: 100/min
   - General requests: 300/5min per IP

3. **Monitor and Adjust:**
   - Track rate limit hits
   - Adjust limits based on usage patterns
   - Consider user tiers (basic vs premium)

4. **Add Infrastructure-Level Protection:**
   - Use Cloudflare or NGINX for DDoS protection
   - Block known malicious IPs
   - Geographic filtering if needed

---

## 3. Fan-Out on Write

### What is Fan-Out on Write?

Fan-out on write (also called "push model" or "write fan-out") pre-computes feed entries when a post is created, storing them in a dedicated table for each follower. When a user requests their feed, the system simply reads from this pre-computed table instead of joining multiple tables.

### Why Fan-Out is Needed

**Current Problem:**
- Feed queries take 50-200ms (see `docs/017_ARCHITECTURE_AND_FEED_PROPOSALS.md`)
- Query time grows with number of follows (O(F × log(P)))
- Scalability limit: ~5,000 follows per user
- Database load increases with user activity

**Fan-Out Solution:**
- Pre-compute feeds when posts are created
- Feed queries become O(log(N)) instead of O(F × log(P))
- Query time: 5-20ms (vs 50-200ms)
- Works for users with 10,000+ follows

### Detailed Explanation

**Current Architecture (Pull Model):**
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

**Fan-Out Architecture (Push Model):**
```
User creates post
  ↓
Insert post (5-15ms)
  ↓
Background job: Fan-out to followers
  ↓
For each follower:
  INSERT INTO feed_entries (user_id, post_id, ...)
  ↓
User requests feed
  ↓
Query: SELECT * FROM feed_entries WHERE user_id = ?
  ↓
Return results (5-20ms)
```

### Implementation

#### Step 1: Create FeedEntries Table

```ruby
# db/migrate/YYYYMMDDHHMMSS_create_feed_entries.rb
class CreateFeedEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :feed_entries do |t|
      t.bigint :user_id, null: false  # The follower who will see this
      t.bigint :post_id, null: false  # The post to show
      t.bigint :author_id, null: false # Denormalized for filtering
      t.datetime :created_at, null: false # Post creation time (for sorting)

      t.index [:user_id, :created_at], order: { created_at: :desc }
      t.index [:user_id, :post_id], unique: true
      t.index :post_id
    end
  end
end
```

#### Step 2: Create FeedEntry Model

```ruby
# app/models/feed_entry.rb
class FeedEntry < ApplicationRecord
  belongs_to :user
  belongs_to :post
  belongs_to :author, class_name: 'User'

  # Ensure uniqueness
  validates :user_id, uniqueness: { scope: :post_id }
end
```

#### Step 3: Create Fan-Out Background Job

```ruby
# app/jobs/fan_out_feed_job.rb
class FanOutFeedJob < ApplicationJob
  queue_as :default

  def perform(post)
    return unless post.parent_id.nil? # Only top-level posts

    followers = post.author.followers

    # Batch insert for efficiency
    feed_entries = followers.map do |follower|
      {
        user_id: follower.id,
        post_id: post.id,
        author_id: post.author_id,
        created_at: post.created_at,
        updated_at: post.created_at
      }
    end

    # Bulk insert in batches of 1000
    feed_entries.each_slice(1000) do |batch|
      FeedEntry.insert_all(batch) if batch.any?
    end
  end
end
```

#### Step 4: Trigger Fan-Out on Post Creation

```ruby
# app/models/post.rb
after_create :fan_out_to_followers

private

def fan_out_to_followers
  # Only fan-out top-level posts (not replies)
  return if parent_id.present?

  # Queue background job
  FanOutFeedJob.perform_later(self)
end
```

#### Step 5: Update Feed Query

```ruby
# app/models/user.rb
def feed_posts
  # Use feed entries if available, fallback to old method
  if FeedEntry.exists?(user_id: id)
    FeedEntry.where(user_id: id)
             .includes(:post, :author)
             .order(created_at: :desc)
             .limit(1000) # Get more than needed for pagination
             .map(&:post)
  else
    # Fallback to old method (during migration)
    user_id = Post.connection.quote(id)
    Post.joins(
      "LEFT JOIN follows ON posts.author_id = follows.followed_id AND follows.follower_id = #{user_id}"
    ).where(
      "posts.author_id = ? OR follows.followed_id IS NOT NULL",
      id
    ).distinct
  end
end
```

#### Step 6: Handle Follow/Unfollow

```ruby
# app/models/user.rb
def follow(other_user)
  return false if self == other_user
  return false if following?(other_user)

  if active_follows.create(followed_id: other_user.id)
    # Backfill recent posts from followed user
    BackfillFeedJob.perform_later(id, other_user.id)
    true
  else
    false
  end
end

def unfollow(other_user)
  deleted_count = Follow.where(follower_id: id, followed_id: other_user.id).delete_all
  if deleted_count > 0
    # Remove feed entries
    FeedEntry.where(user_id: id, author_id: other_user.id).delete_all
    decrement!(:following_count)
    other_user.decrement!(:followers_count)
    true
  else
    false
  end
end
```

#### Step 7: Backfill Existing Feeds

```ruby
# app/jobs/backfill_feed_job.rb
class BackfillFeedJob < ApplicationJob
  queue_as :default

  def perform(user_id, followed_user_id)
    # Get recent posts from followed user (last 50)
    posts = Post.where(author_id: followed_user_id, parent_id: nil)
                .order(created_at: :desc)
                .limit(50)

    feed_entries = posts.map do |post|
      {
        user_id: user_id,
        post_id: post.id,
        author_id: followed_user_id,
        created_at: post.created_at,
        updated_at: post.created_at
      }
    end

    FeedEntry.insert_all(feed_entries) if feed_entries.any?
  end
end
```

### Performance Comparison

| Metric | Current (Pull) | Fan-Out (Push) | Improvement |
|--------|---------------|----------------|-------------|
| **Feed Query Time** | 50-200ms | 5-20ms | 10-40x faster |
| **Write Time** | 13-23ms | 13-23ms + async fan-out | No user-facing delay |
| **Scalability** | Up to 5k follows | 10k+ follows | 2x+ improvement |
| **Storage** | ~2.3 GB | ~150 GB | 65x increase |
| **Complexity** | Low | Medium | More moving parts |

### Trade-offs

#### Advantages

1. **Extremely Fast Reads**: Feed queries become O(log(N)) instead of O(F × log(P))
2. **Predictable Performance**: Query time doesn't depend on follow count
3. **Better Scalability**: Works for users with 10,000+ follows
4. **Simpler Queries**: No complex JOINs needed
5. **Better Caching**: Can cache feed entries easily
6. **Real-time Consistency**: Users see posts immediately (after fan-out completes)

#### Disadvantages

1. **Storage Overhead**:
   - For user with 5,000 followers: 5,000 feed entries per post
   - Storage: ~1.5M posts × 2,505 avg follows × 40 bytes = ~150 GB
   - **Solution**: Partition by date, archive old entries

2. **Write Complexity**:
   - Must fan-out to all followers
   - Background job overhead (50-500ms for fan-out)
   - **Solution**: Batch inserts, async processing

3. **Consistency Challenges**:
   - Feed entries must be updated if post is deleted
   - Unfollow must clean up entries
   - **Solution**: Cascading deletes, cleanup jobs

4. **Initial Implementation**:
   - Must backfill existing feeds
   - Migration complexity
   - **Solution**: Gradual migration, backfill script

### Storage Management

**Partitioning Strategy:**
```ruby
# Archive old feed entries (older than 30 days)
class ArchiveOldFeedEntriesJob < ApplicationJob
  def perform
    FeedEntry.where('created_at < ?', 30.days.ago).delete_all
  end
end

# Schedule in config/recurring.yml
archive_old_feeds:
  command: "ArchiveOldFeedEntriesJob.perform_now"
  schedule: daily at 2am
```

**Lazy Backfill:**
- Only create entries for active followers (logged in last 7 days)
- Query old method for inactive users
- Reduces storage by 50-70%

### Recommendation

**For Current Scale (1M users, 50M follows):**

1. **Implement Fan-Out** as primary strategy
   - Add FeedEntries table
   - Create FanOutFeedJob
   - Update feed queries to use feed entries
   - Backfill existing feeds

2. **Combine with Caching**
   - Cache feed entries query results
   - 5-minute TTL for feed cache
   - Invalidate on post creation

3. **Monitor Storage**
   - Track feed_entries table size
   - Archive old entries regularly
   - Consider lazy backfill for inactive users

4. **Expected Improvements:**
   - Feed query time: 50-200ms → 5-20ms (or <1ms with cache)
   - Scalability: 5k follows → 10k+ follows per user
   - User experience: Much faster feed loading

---

## 4. Read Replicas

### What are Read Replicas?

Read replicas are copies of the primary database that receive replicated data. Applications read from replicas and write to the primary, distributing the read load across multiple database servers.

### Why Read Replicas are Needed

**Current Bottlenecks:**
- Single PostgreSQL database handles all reads and writes
- Connection pool (25 connections) can be exhausted
- Feed queries (50-200ms) consume database resources
- Concurrent users compete for database connections

**Benefits:**
- **Distribute Read Load**: Reads go to replicas, writes to primary
- **Horizontal Scaling**: Add more replicas as load increases
- **Fault Tolerance**: Replicas can serve reads if primary fails
- **Geographic Distribution**: Replicas can be in different regions

### Architecture

```
┌─────────────────┐
│   Rails App     │
│   (Puma)        │
└────────┬────────┘
         │
         ├─────────────┐
         │             │
         ▼             ▼
    ┌─────────┐   ┌─────────┐
    │Primary  │   │Replica 1│
    │(Writes) │   │(Reads)  │
    └─────────┘   └─────────┘
                       │
                       ▼
                  ┌─────────┐
                  │Replica 2│
                  │(Reads)  │
                  └─────────┘
```

### Setup Options

#### Option A: PostgreSQL Streaming Replication (Recommended)

**What**: Native PostgreSQL replication using WAL (Write-Ahead Logging).

**Setup Steps:**

1. **Configure Primary Database:**
```bash
# postgresql.conf
wal_level = replica
max_wal_senders = 3
max_replication_slots = 3
```

2. **Create Replication User:**
```sql
CREATE USER replicator WITH REPLICATION PASSWORD 'secure_password';
```

3. **Configure pg_hba.conf:**
```
host replication replicator 192.168.1.0/24 md5
```

4. **Setup Replica Server:**
```bash
# On replica server
pg_basebackup -h primary_host -D /var/lib/postgresql/data -U replicator -P -W -R
```

5. **Configure Rails:**
```ruby
# config/database.yml
production:
  primary:
    <<: *default
    database: microblog_production
    host: primary_db_host
    port: 5432

  replica:
    <<: *default
    database: microblog_production
    host: replica_db_host
    port: 5432
    replica: true
```

6. **Configure ActiveRecord:**
```ruby
# config/application.rb
config.active_record.database_selector = { delay: 2.seconds }
config.active_record.database_resolver = ActiveRecord::Middleware::DatabaseSelector::Resolver
config.active_record.database_resolver_context = ActiveRecord::Middleware::DatabaseSelector::Resolver::Session
```

7. **Use Replicas for Reads:**
```ruby
# app/controllers/application_controller.rb
def index
  ActiveRecord::Base.connected_to(role: :reading) do
    @posts = Post.all
  end
end
```

**Pros:**
- ✅ **Native PostgreSQL**: Built-in, well-tested
- ✅ **Low Latency**: Streaming replication (near real-time)
- ✅ **Automatic**: Handles replication automatically
- ✅ **Reliable**: Battle-tested in production

**Cons:**
- ❌ **Complex Setup**: Requires PostgreSQL configuration
- ❌ **Lag**: Small replication lag (milliseconds to seconds)
- ❌ **Resource Intensive**: Replicas need similar resources to primary

#### Option B: Rails 6+ Multiple Databases

**What**: Rails built-in support for multiple databases.

**Setup:**

```ruby
# config/database.yml
production:
  primary:
    <<: *default
    database: microblog_production
    host: primary_db_host

  primary_replica:
    <<: *default
    database: microblog_production
    host: replica_db_host
    replica: true
```

**Automatic Routing:**
```ruby
# Rails automatically routes:
# - Writes (create, update, delete) → primary
# - Reads (find, where, etc.) → replica (if available)
```

**Manual Routing:**
```ruby
# app/controllers/posts_controller.rb
def index
  ActiveRecord::Base.connected_to(role: :reading) do
    @posts = current_user.feed_posts
  end
end

def create
  ActiveRecord::Base.connected_to(role: :writing) do
    @post = Post.create(post_params)
  end
end
```

**Pros:**
- ✅ **Rails Native**: Built into Rails 6+
- ✅ **Automatic Routing**: Can route reads/writes automatically
- ✅ **Simple Configuration**: Easy to set up
- ✅ **Migrations**: Can run migrations on specific database

**Cons:**
- ❌ **Rails Version**: Requires Rails 6+
- ❌ **Configuration**: Need to configure routing logic
- ❌ **Testing**: More complex test setup

#### Option C: Application-Level Routing

**What**: Custom logic to route reads/writes.

**Implementation:**
```ruby
# app/models/application_record.rb
class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true

  def self.read_from_replica
    connection_class = ActiveRecord::Base.connection_pool.connections.find do |conn|
      conn.config[:replica] == true
    end

    if connection_class
      connection_class.connection
    else
      connection
    end
  end
end

# app/models/post.rb
def self.feed_for_user(user_id)
  # Use replica for read
  connection = read_from_replica
  connection.execute("SELECT * FROM posts WHERE ...")
end
```

**Pros:**
- ✅ **Full Control**: Complete control over routing
- ✅ **Flexible**: Can implement custom logic
- ✅ **No Dependencies**: Uses existing infrastructure

**Cons:**
- ❌ **More Code**: Need to implement and maintain
- ❌ **Error Handling**: Need to handle connection failures
- ❌ **Complexity**: More moving parts

### Replication Lag Considerations

**Problem**: Replicas may be slightly behind primary (replication lag).

**Solutions:**

1. **Sticky Sessions**: Route user's writes and reads to same server
```ruby
# Route to primary if user wrote in last 2 seconds
if session[:last_write] && Time.now - session[:last_write] < 2.seconds
  ActiveRecord::Base.connected_to(role: :writing) do
    # read from primary
  end
else
  ActiveRecord::Base.connected_to(role: :reading) do
    # read from replica
  end
end
```

2. **Critical Reads**: Route critical reads to primary
```ruby
# For user profile, use primary (must be up-to-date)
def show
  ActiveRecord::Base.connected_to(role: :writing) do
    @user = User.find(params[:id])
  end
end
```

3. **Acceptable Lag**: For feed queries, small lag (seconds) is acceptable
```ruby
# Feeds can tolerate small lag
def index
  ActiveRecord::Base.connected_to(role: :reading) do
    @posts = current_user.feed_posts
  end
end
```

### Recommended Setup

**For Current Scale:**

1. **Start with Single Replica**
   - Setup PostgreSQL streaming replication
   - Configure Rails to use replica for reads
   - Route feed queries to replica
   - Route user profile queries to primary (for consistency)

2. **Monitor Replication Lag**
   - Track lag time
   - Alert if lag exceeds threshold (>5 seconds)
   - Route critical reads to primary if lag is high

3. **Scale Horizontally**
   - Add more replicas as load increases
   - Use load balancer to distribute reads
   - Consider geographic distribution for global users

4. **Expected Improvements:**
   - Read capacity: 2x (primary + 1 replica)
   - Connection pool: Can use separate pools for reads/writes
   - Fault tolerance: Replicas can serve reads if primary fails

---

## 5. PgBouncer Connection Pooling

### What is PgBouncer?

PgBouncer is a lightweight connection pooler for PostgreSQL. It sits between the application and database, managing a pool of connections to reduce connection overhead and improve performance.

### Why PgBouncer is Needed

**Current Problem:**
- Each Rails request creates a database connection
- Connection establishment overhead: ~10-50ms per connection
- Connection pool (25) can be exhausted under load
- PostgreSQL has connection limits (default: 100 connections)
- Each connection consumes memory (~10MB per connection)

**Benefits:**
- **Connection Reuse**: Share connections across requests
- **Reduced Overhead**: Faster connection establishment
- **Higher Throughput**: Handle more concurrent requests
- **Resource Efficiency**: Fewer actual database connections

### Architecture

```
┌─────────────────┐
│   Rails App     │
│   (25 threads)  │
└────────┬────────┘
         │
         │ (Many app connections)
         │
         ▼
    ┌──────────┐
    │PgBouncer │
    │(Pooler)  │
    └──────────┘
         │
         │ (Few DB connections)
         │
         ▼
    ┌──────────┐
    │PostgreSQL│
    │(Database)│
    └──────────┘
```

### Setup Options

#### Option A: Transaction Pooling (Recommended)

**What**: PgBouncer manages connections at transaction level.

**Configuration:**
```ini
# config/pgbouncer.ini
[databases]
microblog = host=localhost port=5432 dbname=microblog_development

[pgbouncer]
listen_addr = 127.0.0.1
listen_port = 6432
auth_type = md5
auth_file = /etc/pgbouncer/userlist.txt
pool_mode = transaction
max_client_conn = 1000
default_pool_size = 25
reserve_pool_size = 5
```

**Rails Configuration:**
```yaml
# config/database.yml
development:
  adapter: postgresql
  host: localhost
  port: 6432  # PgBouncer port
  database: microblog_development
  username: davidslv
  password: <password>
  prepared_statements: false  # Required for transaction pooling
```

**Pros:**
- ✅ **Efficient**: Maximum connection reuse
- ✅ **High Throughput**: Can handle 1000+ client connections
- ✅ **Low Memory**: Fewer database connections

**Cons:**
- ❌ **No Prepared Statements**: Must disable prepared_statements
- ❌ **Session Variables**: Don't persist across transactions
- ❌ **Some Features**: Some PostgreSQL features may not work

#### Option B: Session Pooling

**What**: PgBouncer manages connections at session level.

**Configuration:**
```ini
# config/pgbouncer.ini
pool_mode = session
max_client_conn = 100
default_pool_size = 25
```

**Pros:**
- ✅ **Prepared Statements**: Can use prepared statements
- ✅ **Session Variables**: Persist across transactions
- ✅ **Full Features**: All PostgreSQL features work

**Cons:**
- ❌ **Less Efficient**: Lower connection reuse
- ❌ **Higher Memory**: More database connections needed
- ❌ **Lower Throughput**: Can handle fewer concurrent connections

#### Option C: Statement Pooling

**What**: PgBouncer manages connections at statement level (not recommended for Rails).

**Pros:**
- ✅ **Maximum Efficiency**: Highest connection reuse

**Cons:**
- ❌ **Very Limited**: Many PostgreSQL features don't work
- ❌ **Not Suitable**: Not recommended for Rails applications

### Authentication Setup

**Problem**: PostgreSQL has no password configured (trust authentication).

**Solution Options:**

#### Option 1: Configure PostgreSQL Password

```bash
# Set password for PostgreSQL user
psql -U postgres
ALTER USER davidslv WITH PASSWORD 'secure_password';
```

Then configure PgBouncer:
```ini
# config/pgbouncer.ini
auth_type = md5
auth_file = /etc/pgbouncer/userlist.txt
```

Create userlist:
```bash
# Generate MD5 hash
echo "md5$(echo -n 'passworddavidslv' | md5sum | cut -d' ' -f1)"
# Output: md5abc123...

# /etc/pgbouncer/userlist.txt
"davidslv" "md5abc123..."
```

#### Option 2: Use Trust Authentication (Development Only)

```ini
# config/pgbouncer.ini
auth_type = trust
```

**Warning**: Only use in development, not production!

#### Option 3: Use Any Authentication

```ini
# config/pgbouncer.ini
auth_type = any
```

Then specify user in connection string:
```yaml
# config/database.yml
development:
  # ...
  username: davidslv
  # PgBouncer will use this username for PostgreSQL connection
```

### Installation

**macOS:**
```bash
brew install pgbouncer
```

**Linux:**
```bash
sudo apt-get install pgbouncer
```

**Configuration File:**
```bash
# macOS
/opt/homebrew/etc/pgbouncer.ini

# Linux
/etc/pgbouncer/pgbouncer.ini
```

### Running PgBouncer

```bash
# Start PgBouncer
pgbouncer -d /opt/homebrew/etc/pgbouncer.ini

# Check status
psql -h localhost -p 6432 -U davidslv -d pgbouncer
SHOW POOLS;
```

### Pros and Cons

#### Pros

1. **Connection Efficiency**:
   - Reuse connections across requests
   - Reduce connection establishment overhead
   - Handle more concurrent requests

2. **Resource Savings**:
   - Fewer database connections (25 vs 1000)
   - Lower memory usage
   - Better resource utilization

3. **Scalability**:
   - Can handle 1000+ client connections
   - Better for high-traffic applications
   - Reduces connection pool exhaustion

4. **Performance**:
   - Faster connection establishment
   - Lower latency for connection requests
   - Better overall throughput

#### Cons

1. **Additional Layer**:
   - Another component to manage
   - Additional point of failure
   - More complex architecture

2. **Configuration Complexity**:
   - Need to configure authentication
   - Pool mode selection
   - Connection limits

3. **Transaction Pooling Limitations**:
   - No prepared statements
   - Session variables don't persist
   - Some PostgreSQL features may not work

4. **Debugging**:
   - Harder to debug connection issues
   - Need to understand PgBouncer behavior
   - Connection pooling can hide issues

### Recommended Setup

**For Current Scale:**

1. **Development**: Skip PgBouncer
   - Current setup (direct PostgreSQL) is sufficient
   - No password needed for development
   - Simpler debugging

2. **Production**: Use PgBouncer with Transaction Pooling
   - Configure PostgreSQL with passwords
   - Use transaction pooling for maximum efficiency
   - Set `prepared_statements: false` in database.yml
   - Monitor connection pool usage

3. **Configuration:**
```ini
# config/pgbouncer.ini
[databases]
microblog = host=localhost port=5432 dbname=microblog_production

[pgbouncer]
listen_addr = 127.0.0.1
listen_port = 6432
auth_type = md5
pool_mode = transaction
max_client_conn = 1000
default_pool_size = 25
reserve_pool_size = 5
```

4. **Expected Improvements:**
   - Connection overhead: 10-50ms → <1ms
   - Concurrent connections: 25 → 1000+
   - Database connections: 25 (unchanged)
   - Throughput: 2-3x improvement

### Alternative: Increase Connection Pool

**Instead of PgBouncer, can increase Rails connection pool:**

```yaml
# config/database.yml
production:
  pool: 100  # Increase from 25 to 100
```

**Pros:**
- ✅ Simpler: No additional component
- ✅ Full features: All PostgreSQL features work
- ✅ Easier debugging: Direct connections

**Cons:**
- ❌ Higher memory: More database connections
- ❌ PostgreSQL limits: May hit max_connections limit
- ❌ Less efficient: Each connection consumes resources

**Recommendation**: Use PgBouncer for production, direct connections for development.

---

## Summary and Recommendations

### Priority Order

1. **Caching (Solid Cache)** - ✅ Already configured
   - Implement feed query caching
   - Add cache invalidation
   - Monitor cache hit rates

2. **Fan-Out on Write** - ⚠️ High priority
   - Implement FeedEntries table
   - Create FanOutFeedJob
   - Update feed queries
   - Expected: 10-40x faster feed queries

3. **Rate Limiting (Rack::Attack)** - ⚠️ Medium priority
   - Protect against abuse
   - Implement key limits
   - Monitor rate limit hits

4. **Read Replicas** - ⚠️ Medium priority
   - Setup PostgreSQL replication
   - Route reads to replicas
   - Monitor replication lag

5. **PgBouncer** - ⚠️ Low priority (production only)
   - Configure for production
   - Use transaction pooling
   - Monitor connection pool usage

### Expected Overall Improvements

**Current Performance:**
- Feed queries: 50-200ms
- User profile: 67ms
- RPS: 30-100
- Latency: 1.21s average

**After All Optimizations:**
- Feed queries: <1ms (with cache) or 5-20ms (fan-out)
- User profile: <10ms (with cache)
- RPS: 200-500+
- Latency: <200ms average

**Combined Effect:**
- **10-100x faster** feed queries
- **6-7x faster** user profiles
- **5-10x higher** throughput
- **6x lower** latency

### Implementation Timeline

**Week 1-2: Caching**
- Implement feed query caching
- Add cache invalidation
- Monitor and tune

**Week 3-4: Fan-Out**
- Create FeedEntries table
- Implement FanOutFeedJob
- Backfill existing feeds
- Update feed queries

**Week 5-6: Rate Limiting**
- Install Rack::Attack
- Configure limits
- Monitor and adjust

**Week 7-8: Read Replicas**
- Setup PostgreSQL replication
- Configure Rails routing
- Monitor replication lag

**Week 9-10: PgBouncer (Production)**
- Configure PgBouncer
- Setup authentication
- Monitor connection pools

---

## References

- **Timeline Scope Performance**: `docs/017_ARCHITECTURE_AND_FEED_PROPOSALS.md`
- **Counter Cache Performance**: `docs/027_COUNTER_CACHE_PERFORMANCE_REPORT.md`
- **Feed Query Optimization**: `docs/012_FEED_QUERY_OPTIMIZATION.md`
- **Performance at Scale**: `docs/022_PERFORMANCE_AT_SCALE.md`
- **Solid Queue Setup**: `docs/026_SOLID_QUEUE_SETUP.md`

