# Microblog Performance Analysis Report

## Executive Summary

This report analyzes the performance characteristics, data storage requirements, and potential bottlenecks of the microblog application under a scenario with 10,000 users, variable following patterns, and substantial post volumes.

---

## 1. Single Record Data Size Calculations

### 1.1 User Record Size

**Database Schema:**
- `id`: BIGINT (8 bytes)
- `username`: VARCHAR(50) (50 bytes average, 54 bytes with overhead)
- `description`: VARCHAR(120) (average 60 bytes, 64 bytes with overhead, nullable)
- `password_digest`: VARCHAR (60 bytes for bcrypt, 64 bytes with overhead)
- `created_at`: TIMESTAMP (8 bytes)
- `updated_at`: TIMESTAMP (8 bytes)
- **Index overhead**: ~16 bytes per index (username index)

**Calculation:**
```
Base record size = 8 + 54 + 64 + 64 + 8 + 8 = 206 bytes
Index overhead = 16 bytes
Total per User = ~222 bytes
```

**Actual with SQLite overhead:**
- Row header: ~4 bytes
- **Total: ~226 bytes per user**

### 1.2 Post Record Size

**Database Schema:**
- `id`: INTEGER (4 bytes)
- `author_id`: INTEGER (4 bytes, nullable)
- `content`: VARCHAR(200) (average 100 bytes, 104 bytes with overhead)
- `parent_id`: INTEGER (4 bytes, nullable)
- `created_at`: TIMESTAMP (8 bytes)
- `updated_at`: TIMESTAMP (8 bytes)
- **Index overhead**: ~16 bytes per index (author_id, created_at, parent_id)

**Calculation:**
```
Base record size = 4 + 4 + 104 + 4 + 8 + 8 = 132 bytes
Index overhead = 48 bytes (3 indexes)
Total per Post = ~180 bytes
```

**Actual with SQLite overhead:**
- Row header: ~4 bytes
- **Total: ~184 bytes per post**

### 1.3 Follow Record Size

**Database Schema:**
- `follower_id`: BIGINT (8 bytes)
- `followed_id`: BIGINT (8 bytes)
- `created_at`: TIMESTAMP (8 bytes)
- `updated_at`: TIMESTAMP (8 bytes)
- **Index overhead**: ~16 bytes per index (follower_id+followed_id composite, followed_id)

**Calculation:**
```
Base record size = 8 + 8 + 8 + 8 = 32 bytes
Index overhead = 32 bytes (2 indexes)
Total per Follow = ~64 bytes
```

**Actual with SQLite overhead:**
- Row header: ~4 bytes
- **Total: ~68 bytes per follow relationship**

---

## 2. Total Data Volume Analysis (10k Users Scenario)

### 2.1 Assumptions

- **Users**: 10,000
- **Following per user**: 10 to 5,000 (average: ~2,505 follows per user)
- **Posts per user**: ~150 posts
- **Replies per post**: 0 to 30 (average: 15 replies per post)
- **Reply ratio**: ~30% of posts are replies to other users' posts

### 2.2 Data Volume Calculations

#### Users Table
```
Total Users = 10,000
Size per user = 226 bytes
Total Users size = 10,000 × 226 bytes = 2.26 MB
```

#### Posts Table
```
Total posts per user = 150
Total posts = 10,000 × 150 = 1,500,000 posts
Size per post = 184 bytes
Total Posts size = 1,500,000 × 184 bytes = 276 MB
```

#### Follows Table
```
Average follows per user = (10 + 5,000) / 2 = 2,505
Total follow relationships = 10,000 × 2,505 = 25,050,000 follows
Size per follow = 68 bytes
Total Follows size = 25,050,000 × 68 bytes = 1.70 GB
```

#### Total Database Size
```
Users:        2.26 MB
Posts:        276 MB
Follows:      1.70 GB
Indices:      ~200 MB (estimated)
Overhead:     ~100 MB (SQLite page overhead, fragmentation)
─────────────────────────────
TOTAL:        ~2.28 GB
```

---

## 3. Database Bottleneck Analysis

### 3.1 Critical Query Patterns

#### 3.1.1 Feed Generation Query (Most Critical)

**Current Implementation:**
```ruby
# In User model
def feed_posts
  following_ids = following.pluck(:id)
  Post.where(author_id: [id] + following_ids).timeline
end
```

**Problem Analysis:**

**Step 1: Get Following IDs**
```sql
SELECT "users"."id" FROM "users"
INNER JOIN "follows" ON "users"."id" = "follows"."followed_id"
WHERE "follows"."follower_id" = ?
```

**Bottleneck Formula:**
```
Query Time = O(F × log(F))
Where F = number of users followed

For average user (2,505 follows):
- Index scan: 2,505 lookups
- Estimated time: ~50-100ms per query
- Memory: ~20KB for result set
```

**Step 2: Get Posts with Large IN Clause**
```sql
SELECT * FROM "posts"
WHERE "author_id" IN (?, ?, ..., ?) -- Up to 2,506 IDs
ORDER BY "created_at" DESC
LIMIT 20
```

**Bottleneck Formula:**
```
Query Time = O(P × log(P) + F)
Where P = posts in database, F = following count

For average user:
- IN clause with 2,506 IDs: ~5-10ms parsing
- Index scan on author_id: O(F × log(P/F))
- Sort operation: O(N log N) where N = matching posts
- Estimated time: ~100-500ms depending on post distribution
```

**Total Feed Generation Time:**
```
T_feed = T_following_query + T_posts_query
T_feed ≈ 150-600ms per request
```

**Bottleneck Severity: 🔴 CRITICAL**

**Issues:**
1. **Large IN Clauses**: SQLite has limitations with very large IN clauses (>1000 items)
2. **No Pagination Strategy**: Loading all following IDs into memory
3. **N+1 Potential**: Each post may trigger author lookup
4. **Sort Performance**: Sorting potentially millions of posts

#### 3.1.2 Timeline Query (Posts Index)

**Query:**
```sql
SELECT * FROM "posts"
WHERE "author_id" IN (?)
ORDER BY "created_at" DESC
```

**Bottleneck Formula:**
```
Query Time = O(P_a × log(P_a))
Where P_a = posts by user and their following

For user following 2,505 people with 150 posts each:
P_a = 2,505 × 150 = 375,750 posts to potentially sort
```

**Performance:**
- Index on `created_at` helps but sorting 375k+ records is expensive
- Estimated time: ~200-800ms

#### 3.1.3 Followers/Following Count Queries

**Query:**
```sql
SELECT COUNT(*) FROM "follows" WHERE "followed_id" = ?
SELECT COUNT(*) FROM "follows" WHERE "follower_id" = ?
```

**Bottleneck Formula:**
```
Query Time = O(F)
Where F = number of follows

For users with 5,000 followers:
- Full index scan: ~10-20ms
- Not critical but can be optimized with denormalized counters
```

#### 3.1.4 Post Replies Query

**Query:**
```sql
SELECT * FROM "posts"
WHERE "parent_id" = ?
ORDER BY "created_at" DESC
```

**Bottleneck Analysis:**
```
Query Time = O(R)
Where R = number of replies (0-30)

Performance: ~1-5ms (well-indexed, small result set)
Bottleneck Severity: 🟢 LOW
```

### 3.2 Index Analysis

**Current Indexes:**
1. `posts.author_id` - ✅ Critical for feed queries
2. `posts.created_at` - ✅ Critical for timeline sorting
3. `posts.parent_id` - ✅ Good for replies
4. `follows.follower_id + followed_id` (composite) - ✅ Critical
5. `follows.followed_id` - ✅ Good for reverse lookups

**Missing Indexes:**
- **Composite index on `(author_id, created_at)`** - Would significantly improve feed queries
- **Covering index optimization** - Could reduce table lookups

**Recommended Index:**
```sql
CREATE INDEX idx_posts_author_created ON posts(author_id, created_at DESC);
```

**Impact:**
```
Before: O(P × log(P)) sort operation
After: O(P) index scan
Time improvement: ~50-70% reduction
```

### 3.3 Database Connection Pool Pressure

**Formula:**
```
Concurrent Requests = Active Users × Request Rate × Avg Request Duration
```

**Estimation:**
- Active users: 1,000 (10% of total)
- Request rate: 2 requests/second per user
- Avg request duration: 200ms (database time)

```
Concurrent DB Connections = 1,000 × 2 × 0.2 = 400 connections
```

**Default Rails pool size: 5 connections** - This will be a major bottleneck!

**Recommendation:** Increase pool size to at least 20-50 connections.

---

## 4. Web Application Bottleneck Analysis

### 4.1 Request Processing Time Breakdown

**Feed Page Load (Posts#index):**

```
T_total = T_auth + T_following_query + T_posts_query + T_render + T_network

Breakdown:
- Authentication: ~5ms
- Get following IDs: ~50-100ms
- Get posts: ~100-500ms
- Render view: ~50-100ms
- Network: ~50-200ms
─────────────────────────────
Total: ~255-905ms
```

**Bottleneck:** Database queries (75-80% of total time)

### 4.2 Memory Usage

**Per Request Memory:**
```
Following IDs array: ~20KB (2,505 IDs × 8 bytes)
Posts array (20 posts): ~20KB (20 posts × 1KB per post object)
View rendering: ~500KB (Rails overhead)
─────────────────────────────
Per request: ~540KB
```

**Concurrent Requests:**
```
With 400 concurrent requests:
Total memory = 400 × 540KB = 216 MB
```

### 4.3 N+1 Query Problems

**Potential N+1 Issues:**

1. **Post Author Lookups:**
```ruby
# In view: @posts.each { |post| post.author.username }
# Triggers: N queries for N posts
```

**Impact:**
```
For 20 posts in feed:
- Without fix: 20 additional queries = ~100-200ms
- With includes: 1 query = ~5-10ms
```

2. **Reply Count Queries:**
```ruby
# If counting replies per post
post.replies.count  # N queries
```

**Fix Required:**
```ruby
@posts = Post.includes(:author).where(...)
```

---

## 5. Request Rate Analysis

### 5.1 User Behavior Assumptions

Based on typical social media patterns:

- **Daily Active Users (DAU)**: 30% = 3,000 users
- **Peak concurrent users**: 10% = 1,000 users
- **Average session duration**: 15 minutes
- **Page views per session**: 10 pages
- **Actions per session**:
  - View feed: 5 times
  - View post: 3 times
  - Create post: 0.2 times (1 post per 5 sessions)
  - Reply: 0.5 times
  - Follow/unfollow: 0.1 times

### 5.2 Requests Per Second Calculation

**Peak Hour Traffic (assuming 3x average):**

```
Active Users = 1,000
Session Duration = 15 minutes = 900 seconds
Page Views per Session = 10
Average Time per Page = 900 / 10 = 90 seconds

Requests per User per Second = 1 / 90 = 0.011 RPS
Total RPS = 1,000 × 0.011 = 11 RPS (average)

Peak RPS (3x average) = 33 RPS
```

**Request Distribution:**

```
Feed Views:        33 × 0.5 = 16.5 RPS
Post Views:        33 × 0.3 = 9.9 RPS
Post Creation:     33 × 0.02 = 0.66 RPS
Reply Creation:    33 × 0.05 = 1.65 RPS
Follow/Unfollow:   33 × 0.01 = 0.33 RPS
User Profile:      33 × 0.12 = 4.0 RPS
─────────────────────────────────────
Total:             ~33 RPS
```

### 5.3 Database Queries Per Second

**Query Breakdown per Request Type:**

1. **Feed View (Posts#index):**
   - Get following: 1 query
   - Get posts: 1 query
   - Load authors (if N+1): 20 queries
   - **Total: 2-22 queries**

2. **Post View (Posts#show):**
   - Get post: 1 query
   - Get replies: 1 query
   - Load authors: 1 + N queries (N = replies)
   - **Total: 3-32 queries**

3. **Post Creation:**
   - Insert post: 1 query
   - **Total: 1 query**

**Total Database Queries Per Second:**

```
Feed Views:        16.5 × 2 = 33 QPS (with fix) or 16.5 × 22 = 363 QPS (with N+1)
Post Views:        9.9 × 3 = 30 QPS (with fix) or 9.9 × 32 = 317 QPS (with N+1)
Post Creation:     0.66 × 1 = 0.66 QPS
Reply Creation:    1.65 × 1 = 1.65 QPS
User Profile:      4.0 × 3 = 12 QPS
─────────────────────────────────────────────────────────────
Total (optimized):  ~77 QPS
Total (with N+1):   ~693 QPS ⚠️
```

---

## 6. Performance Bottleneck Formulas

### 6.1 Feed Query Complexity

**Current Implementation:**
```
T_feed = T_get_following + T_get_posts + T_sort

T_get_following = O(F × log(F))
  Where F = number of users followed
  Constants: ~0.02ms per follow

T_get_posts = O(P_f × log(P_f))
  Where P_f = posts from followed users
  Constants: ~0.001ms per post in result set

T_sort = O(N × log(N))
  Where N = number of posts to sort
  Constants: ~0.0001ms per post

Total: T_feed ≈ 0.02F + 0.001P_f + 0.0001N × log(N)
```

**Example Calculation (User with 2,505 follows):**
```
T_feed = 0.02 × 2,505 + 0.001 × 375,750 + 0.0001 × 375,750 × log(375,750)
T_feed = 50.1 + 375.75 + 0.0001 × 375,750 × 12.86
T_feed = 50.1 + 375.75 + 483.4
T_feed ≈ 909ms
```

### 6.2 Database Connection Pool Exhaustion

**Formula:**
```
P_required = RPS × T_avg × S
Where:
  P_required = Required pool size
  RPS = Requests per second
  T_avg = Average request duration (seconds)
  S = Safety factor (1.5-2.0)
```

**Example:**
```
P_required = 33 × 0.2 × 1.5 = 9.9 ≈ 10 connections minimum
Recommended: 20-30 connections for safety margin
```

### 6.3 Memory Pressure

**Formula:**
```
M_total = R_concurrent × M_request
Where:
  M_total = Total memory required
  R_concurrent = Concurrent requests
  M_request = Memory per request
```

**Example:**
```
M_total = 400 × 540KB = 216 MB (just for requests)
Add Rails overhead: ~500 MB total
```

### 6.4 Disk I/O Bottleneck

**Formula:**
```
IOPS_required = QPS × R_per_query
Where:
  IOPS_required = Input/Output Operations Per Second
  QPS = Queries per second
  R_per_query = Reads per query (average)
```

**For SQLite:**
```
IOPS_required = 77 × 10 = 770 IOPS
SQLite limitations: ~100-500 IOPS (single writer)
⚠️ This will be a bottleneck!
```

---

## 7. Expected User Interactions

### 7.1 Session Characteristics

**Average Session:**
- **Duration**: 15 minutes (900 seconds)
- **Page Views**: 10 pages
- **Time per Page**: 90 seconds
- **Interactions per Session**: 6-8 interactions

### 7.2 Interaction Types and Frequencies

| Interaction Type | Frequency per Session | Percentage |
|-----------------|----------------------|------------|
| View Feed | 5 times | 50% |
| View Post Details | 3 times | 30% |
| Create Post | 0.2 times | 2% |
| Reply to Post | 0.5 times | 5% |
| Follow User | 0.05 times | 0.5% |
| Unfollow User | 0.05 times | 0.5% |
| View Profile | 1.2 times | 12% |

### 7.3 Peak Usage Patterns

**Peak Hours (6 PM - 10 PM):**
- Traffic multiplier: 3x average
- Concurrent users: 1,000 (vs 333 average)
- Requests per second: 33 (vs 11 average)

**Weekend Patterns:**
- 1.5x weekday traffic
- Longer session durations (20 minutes)
- More content creation (1.5x posts)

---

## 8. Critical Bottlenecks Summary

### 8.1 🔴 CRITICAL Issues

1. **Large IN Clauses in Feed Queries**
   - **Impact**: SQLite struggles with 2,500+ item IN clauses
   - **Solution**: Use JOIN or temporary table approach
   - **Formula**: `T_query = O(F × log(P))` where F > 1000 becomes problematic

2. **Database Connection Pool Exhaustion**
   - **Current**: 5 connections (default)
   - **Required**: 20-30 connections
   - **Risk**: High latency, request queuing

3. **Feed Query Performance**
   - **Current**: 150-600ms per request
   - **Target**: <100ms
   - **Impact**: 75% of page load time

4. **SQLite Limitations**
   - **IOPS**: Limited to ~100-500 IOPS
   - **Concurrent Writes**: Single writer limitation
   - **Recommendation**: Migrate to PostgreSQL for production

### 8.2 🟡 MODERATE Issues

1. **N+1 Query Problems**
   - **Impact**: 20-30x query multiplication
   - **Fix**: Use `includes(:author)` in queries
   - **Impact**: Reduces queries from 693 QPS to 77 QPS

2. **Missing Composite Index**
   - **Impact**: 50-70% slower feed queries
   - **Fix**: Add `(author_id, created_at)` composite index

3. **Sorting Large Result Sets**
   - **Impact**: O(N log N) complexity
   - **Solution**: Use indexed sorting, limit result sets

### 8.3 🟢 MINOR Issues

1. **Followers/Following Count Queries**
   - **Impact**: Small, but can be cached
   - **Solution**: Denormalize counters or cache

2. **Reply Queries**
   - **Status**: Well-optimized
   - **No action needed**

---

## 9. Recommendations

### 9.1 Immediate Fixes (Priority 1)

1. **Add Composite Index:**
   ```sql
   CREATE INDEX idx_posts_author_created ON posts(author_id, created_at DESC);
   ```

2. **Fix N+1 Queries:**
   ```ruby
   # In PostsController
   @posts = current_user.feed_posts.includes(:author).timeline.limit(20)
   ```

3. **Increase Connection Pool:**
   ```ruby
   # config/database.yml
   pool: 25
   ```

4. **Optimize Feed Query:**
   ```ruby
   # Use JOIN instead of IN clause
   def feed_posts
     Post.joins("INNER JOIN follows ON posts.author_id = follows.followed_id")
         .where("follows.follower_id = ? OR posts.author_id = ?", id, id)
         .order(created_at: :desc)
   end
   ```

### 9.2 Short-term Improvements (Priority 2)

1. **Implement Caching:**
   - Cache feed results for 30-60 seconds
   - Cache follower/following counts
   - Use Redis or Memcached

2. **Add Pagination:**
   - Implement cursor-based pagination
   - Reduce initial query size

3. **Database Migration:**
   - Migrate from SQLite to PostgreSQL
   - Better concurrent write handling
   - Higher IOPS capacity

### 9.3 Long-term Optimizations (Priority 3)

1. **Implement Read Replicas:**
   - Separate read/write databases
   - Distribute query load

2. **Denormalize Counters:**
   - Add `followers_count` and `following_count` to users table
   - Update on follow/unfollow actions

3. **Implement Materialized Views:**
   - Pre-compute user feeds
   - Update asynchronously

4. **Add Full-Text Search:**
   - For future search functionality
   - Use PostgreSQL full-text or Elasticsearch

---

## 10. Performance Targets

### 10.1 Current Performance

- **Feed Load Time**: 255-905ms
- **Post View Time**: 100-300ms
- **Database Queries**: 77 QPS (optimized) or 693 QPS (with N+1)
- **Connection Pool**: 5 (insufficient)

### 10.2 Target Performance

- **Feed Load Time**: <200ms (p95)
- **Post View Time**: <100ms (p95)
- **Database Queries**: <100 QPS
- **Connection Pool**: 25-30
- **Database**: PostgreSQL (production)
- **Cache Hit Rate**: >80%

---

## 11. Conclusion

The microblog application will face significant performance challenges at scale, particularly:

1. **Feed generation queries** are the primary bottleneck, taking 150-600ms per request
2. **Database connection pool** is insufficient (5 vs required 20-30)
3. **SQLite limitations** will become problematic with concurrent writes
4. **N+1 queries** can multiply database load by 10x if not addressed

**Total database size** of ~2.28 GB is manageable, but the **query patterns** need optimization. The application should be able to handle 33 RPS with proper optimizations, but will struggle without the recommended fixes.

**Priority actions:**
1. Fix N+1 queries immediately
2. Add composite index on posts
3. Increase connection pool
4. Optimize feed query (JOIN instead of IN clause)
5. Plan migration to PostgreSQL for production

---

## Appendix A: Data Size Reference

| Entity | Single Record | 10k Users Scenario |
|--------|--------------|-------------------|
| User | 226 bytes | 2.26 MB |
| Post | 184 bytes | 276 MB |
| Follow | 68 bytes | 1.70 GB |
| **Total** | - | **~2.28 GB** |

## Appendix B: Query Performance Reference

| Query Type | Current Time | Target Time | Complexity |
|-----------|--------------|-------------|------------|
| Feed Generation | 150-600ms | <100ms | O(F × log(P)) |
| Post View | 100-300ms | <100ms | O(R) |
| Followers Count | 10-20ms | <5ms | O(F) |
| Create Post | 5-10ms | <10ms | O(1) |

## Appendix C: Scaling Formulas Reference

```
Feed Query Time: T = 0.02F + 0.001P_f + 0.0001N × log(N)
Connection Pool: P = RPS × T_avg × 1.5
Memory Usage: M = R_concurrent × 540KB
IOPS Required: IOPS = QPS × 10
```

Where:
- F = number of users followed
- P_f = posts from followed users
- N = number of posts to sort
- RPS = Requests per second
- T_avg = Average request duration
- R_concurrent = Concurrent requests
- QPS = Queries per second

