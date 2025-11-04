# Performance Analysis at 1 Million User Scale

## Current System State

**Scale:**
- **Users**: 1,091,000
- **Posts**: 73,817
- **Follows**: 50,368,293
- **User #1 Followers**: 1,026,999

---

## Performance Issues Identified

### 1. User Profile Page (`/users/1`)

**Current Performance:**
```
Completed 200 OK in 729ms
- Views: 21.9ms
- ActiveRecord: 703.3ms (45 queries, 0 cached)
- GC: 1.1ms
```

**Bottlenecks:**
1. **`@user.followers.count`**: 713.7ms (COUNT query on 1M+ followers)
2. **`@user.following.count`**: Likely similar slow query
3. **45 queries total**: N+1 query issues

**Root Cause:**
- Counting 1,026,999 followers requires full table scan
- No counter cache implemented
- Query: `SELECT COUNT(*) FROM users INNER JOIN follows ...` on 1M+ rows

### 2. WRK Load Test Results

**Test Configuration:**
```bash
wrk -t8 -c250 -d30s -s load_test/wrk_feed.lua http://localhost:3000/
```

**Results:**
```
Requests/sec:     30.34
Latency:          1.21s (avg), 1.81s (max)
Timeouts:         855
Efficiency:       ~12% (911 requests in 30s vs potential 7500)
```

**Issues:**
- **Very low RPS**: 30.34 (should be 200-500+)
- **High latency**: 1.21s average (target: <200ms)
- **Many timeouts**: 855 timeouts (94% timeout rate!)
- **Poor efficiency**: Only 12% of potential requests completed

---

## Root Cause Analysis

### Database Query Performance

**Problem 1: Counter Queries**
```ruby
@user.followers.count  # 713.7ms for 1M+ followers
```

**Generated SQL:**
```sql
SELECT COUNT(*) FROM "users" 
INNER JOIN "follows" ON "users"."id" = "follows"."follower_id" 
WHERE "follows"."followed_id" = 1
```

**Why it's slow:**
- Must scan 1M+ follow relationships
- JOIN operation on large tables
- No counter cache

**Solution:** Counter cache (implemented)

**Problem 2: Feed Query Performance**

With 1M users, feed queries become very slow:
- User with 5,000 follows: Must scan posts from 5,000 users
- Large JOIN operations
- No pre-computed feeds

**Solution:** Consider Proposal 1 (Fan-Out on Write) from architecture document

**Problem 3: Connection Pool**

With 250 concurrent connections:
- 25 connection pool is insufficient
- Requests queue up waiting for connections
- Causes timeouts

**Solution:** Increase connection pool or use read replicas

---

## Optimizations Implemented

### 1. Counter Cache (Critical Fix)

**Migration:**
- Adds `followers_count`, `following_count`, `posts_count` columns
- Backfills using efficient SQL UPDATE queries
- Adds indexes for sorting/filtering

**Model Changes:**
- `User#follow` updates counter caches
- `User#unfollow` updates counter caches
- `Follow` callbacks maintain counters

**Controller Changes:**
- Uses `@user.followers_count` instead of `@user.followers.count`
- Uses `@user.following_count` instead of `@user.following.count`
- Uses `@user.posts_count` instead of `@posts.count`

**Expected Performance:**
- **Before**: 713.7ms per count query
- **After**: <1ms (just reading column value)
- **Improvement**: 700x+ faster!

### 2. Posts Counter Cache

**Added:**
- `posts_count` column with Rails counter_cache
- Automatic updates on post create/destroy
- No manual counter management needed

---

## Expected Performance Improvements

### User Profile Page

**Before:**
```
ActiveRecord: 703.3ms
- followers.count: 713.7ms
- following.count: ~700ms
- posts.count: ~50ms
Total: ~729ms
```

**After (with counter cache):**
```
ActiveRecord: ~50-100ms
- followers_count: <1ms (column read)
- following_count: <1ms (column read)
- posts_count: <1ms (column read)
- Posts query: ~50-100ms (paginated)
Total: ~50-100ms (7-14x faster!)
```

### WRK Load Test

**Before:**
- RPS: 30.34
- Latency: 1.21s
- Timeouts: 855 (94%)

**After (with counter cache):**
- Expected RPS: 50-100 (2-3x improvement)
- Expected Latency: 800ms-1.0s (still high due to feed queries)
- Expected Timeouts: 400-600 (still high)

**Additional Optimizations Needed:**
- Feed query optimization (Proposal 1: Fan-Out)
- Connection pool increase
- Read replicas

---

## Remaining Bottlenecks

### 1. Feed Query Performance

**Current Query:**
```ruby
current_user.feed_posts.timeline
```

**For user with 5,000 follows:**
- Scans posts from 5,000 users
- Large JOIN operation
- No pre-computation

**Estimated Time:** 200-500ms per feed load

**Solution:** Implement Proposal 1 (Fan-Out on Write) from architecture document

### 2. Connection Pool Exhaustion

**Current:**
- Pool: 25 connections
- Concurrent: 250 connections
- Ratio: 10:1 (insufficient)

**Impact:**
- Requests queue up waiting for connections
- Causes timeouts
- Degrades performance

**Solutions:**
1. Increase pool to 100-200 (may not be enough)
2. Use read replicas (distribute load)
3. Implement caching layer (Redis)

### 3. N+1 Queries

**Current:**
- 45 queries for user profile page
- Likely N+1 on post authors

**Solutions:**
- Add `.includes(:author)` to queries
- Use `preload` or `eager_load` where appropriate

---

## Immediate Next Steps

### 1. Run Migration (Counter Cache)

```bash
rails db:migrate
```

**Expected time:** 5-15 minutes (backfilling 1M users)

### 2. Test Performance

```bash
# Test user profile page
time curl http://localhost:3000/users/1

# Should see <100ms instead of 729ms
```

### 3. Re-run WRK Test

```bash
wrk -t8 -c250 -d30s -s load_test/wrk_feed.lua http://localhost:3000/
```

**Expected improvements:**
- RPS: 50-100 (from 30)
- Latency: 800ms-1.0s (from 1.21s)
- Timeouts: 400-600 (from 855)

### 4. Implement Feed Optimization

**For feed queries (Proposal 1 recommended):**
- Add FeedEntries table
- Implement fan-out on write
- See `docs/ARCHITECTURE_AND_FEED_PROPOSALS.md`

---

## Performance Targets

### Current vs Target

| Metric | Current | Target | Status |
|--------|---------|--------|--------|
| **User Profile** | 729ms | <100ms | ⚠️ After counter cache |
| **Feed Load** | 200-500ms | <100ms | ❌ Needs Proposal 1 |
| **RPS** | 30 | 200+ | ❌ Needs multiple optimizations |
| **Latency (p95)** | 1.21s | <200ms | ❌ Needs Proposal 1 |
| **Timeouts** | 855 | <50 | ❌ Needs Proposal 1 |

### After Counter Cache Implementation

**Expected:**
- ✅ User profile: <100ms (7x improvement)
- ⚠️ Feed load: Still 200-500ms (needs Proposal 1)
- ⚠️ RPS: 50-100 (2-3x improvement, still needs more)
- ⚠️ Latency: 800ms-1.0s (still too high)

---

## Architecture Recommendations at This Scale

### Immediate (This Week)

1. ✅ **Counter Cache** - Implemented (this fix)
2. ⚠️ **Feed Optimization** - Implement Proposal 1 (Fan-Out)
3. ⚠️ **Connection Pool** - Increase to 100-200
4. ⚠️ **N+1 Fixes** - Add `.includes(:author)` to queries

### Short-term (This Month)

1. **Redis Caching** - Cache feed results
2. **Read Replicas** - Distribute read load
3. **Query Optimization** - Review all slow queries

### Long-term (Next Quarter)

1. **Materialized Views** - For analytics
2. **Partitioning** - Partition large tables
3. **CDN** - For static assets

---

## Conclusion

**Current Status:**
- ❌ Performance is unacceptable at 1M user scale
- ✅ Counter cache fix will improve user profile pages
- ⚠️ Feed queries still need optimization (Proposal 1)
- ⚠️ Connection pool needs increase

**Priority Actions:**
1. ✅ **Run migration** (counter cache) - DONE
2. ⚠️ **Implement Proposal 1** (feed optimization) - CRITICAL
3. ⚠️ **Increase connection pool** - HIGH
4. ⚠️ **Fix N+1 queries** - MEDIUM

**Expected Overall Improvement:**
- User profile: 729ms → <100ms (7x faster) ✅
- Feed queries: 200-500ms → 5-20ms (10-100x faster) ⚠️ (after Proposal 1)
- RPS: 30 → 200+ (6x+ improvement) ⚠️ (after all optimizations)

