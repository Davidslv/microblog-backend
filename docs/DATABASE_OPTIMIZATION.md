# Database Optimization Guide

## Composite Index on Posts (author_id, created_at)

### Overview

A composite index has been added to the `posts` table to optimize feed queries that filter by `author_id` and order by `created_at DESC`.

**Index Name:** `index_posts_on_author_id_and_created_at`
**Columns:** `author_id`, `created_at` (DESC order)
**Migration:** `20251103225927_add_composite_index_to_posts_on_author_id_and_created_at.rb`

### Why This Index?

**Problem:**
Feed queries need to:
1. Filter posts by multiple authors: `WHERE author_id IN (1, 2, 3, ..., 2506)`
2. Order by creation time: `ORDER BY created_at DESC`
3. Limit results: `LIMIT 20`

**Without Composite Index:**
```sql
-- Database uses separate indexes
-- 1. Uses index on author_id to filter
-- 2. Then sorts filtered results using index on created_at
-- Result: Sort operation on potentially 375k+ rows
```

**With Composite Index:**
```sql
-- Database uses single composite index
-- 1. Uses (author_id, created_at DESC) index
-- 2. Index already sorted by created_at DESC
-- Result: Direct index scan, no sort operation needed!
```

### Performance Impact

**Before Index:**
- Query time: 150-600ms
- Operations: Filter → Sort → Limit
- Complexity: O(P_a × log(P_a)) where P_a = posts from followed users

**After Index:**
- Query time: 50-200ms (estimated)
- Operations: Index scan → Limit
- Complexity: O(log(P_a))
- **Improvement: 50-70% faster**

### Queries Optimized

This index optimizes the following query patterns:

#### 1. Feed Queries (Most Critical)
```ruby
# In User model
def feed_posts
  following_ids = following.pluck(:id)
  Post.where(author_id: [id] + following_ids).order(created_at: :desc)
end
```

**SQL Generated:**
```sql
SELECT * FROM posts
WHERE author_id IN (1, 2, 3, ..., 2506)
ORDER BY created_at DESC
LIMIT 20
```

**Index Usage:**
- Uses composite index for both WHERE and ORDER BY
- No separate sort operation needed

#### 2. User Profile Posts
```ruby
# In UsersController
@user.posts.top_level.order(created_at: :desc)
```

**SQL Generated:**
```sql
SELECT * FROM posts
WHERE author_id = ? AND parent_id IS NULL
ORDER BY created_at DESC
LIMIT 20
```

**Index Usage:**
- Uses composite index for filtering and sorting

#### 3. Following Posts Filter
```ruby
# In PostsController
following_ids = current_user.following.pluck(:id)
Post.where(author_id: following_ids).order(created_at: :desc)
```

**SQL Generated:**
```sql
SELECT * FROM posts
WHERE author_id IN (?, ?, ...)
ORDER BY created_at DESC
```

**Index Usage:**
- Same optimization as feed queries

### Index Structure

**Column Order:**
1. `author_id` (first) - for filtering
2. `created_at DESC` (second) - for sorting

**Why This Order?**
- `author_id` first: Allows efficient filtering on author
- `created_at DESC` second: Allows efficient sorting without separate operation
- Matches query pattern: filter by author, then sort by date

**Index Size:**
- Additional storage: ~8 bytes per post (for index entries)
- For 1.5M posts: ~12 MB additional storage
- Trade-off: Small storage cost for significant performance gain

### Verification

**Check Index Exists:**
```sql
-- SQLite
SELECT name FROM sqlite_master
WHERE type='index' AND name='index_posts_on_author_id_and_created_at';

-- PostgreSQL
SELECT indexname FROM pg_indexes
WHERE tablename='posts' AND indexname='index_posts_on_author_id_and_created_at';
```

**Check Index Usage:**
```sql
-- SQLite (explain query plan)
EXPLAIN QUERY PLAN
SELECT * FROM posts
WHERE author_id IN (1, 2, 3)
ORDER BY created_at DESC
LIMIT 20;
```

**Expected Result:**
- Should show: `USING INDEX index_posts_on_author_id_and_created_at`
- No `ORDER BY` in execution plan (already sorted in index)

### Migration

**Applied:**
```bash
rails db:migrate
```

**Rollback (if needed):**
```bash
rails db:rollback
```

**Re-run:**
```bash
rails db:migrate:redo
```

### Testing the Improvement

**Before Optimization:**
```bash
# Run load test
k6 run load_test/k6_feed_test.js
# Note: p95 response time ~500-600ms
```

**After Optimization:**
```bash
# Run same test
k6 run load_test/k6_feed_test.js
# Expected: p95 response time ~200-300ms (50% improvement)
```

### Related Optimizations

This index complements other optimizations:

1. **Cursor-based Pagination** - Reduces query size
2. **Includes for N+1 Prevention** - `Post.includes(:author)`
3. **Connection Pool Sizing** - Handles concurrent queries

### Index Maintenance

**Automatic:**
- Index is automatically maintained by the database
- Updates on INSERT/UPDATE/DELETE
- No manual maintenance needed

**Trade-offs:**
- ✅ Faster SELECT queries (50-70% improvement)
- ✅ Faster feed page loads
- ⚠️ Slightly slower INSERTs (index updates)
- ⚠️ Additional storage (~12 MB for 1.5M posts)

**For INSERT Performance:**
- Index updates are minimal overhead
- Modern databases handle this efficiently
- Trade-off is worth it for read-heavy workloads (like feeds)

### Best Practices

1. **Index Order Matters**
   - Match query pattern: filter columns first, sort columns second
   - Our pattern: `WHERE author_id IN (...) ORDER BY created_at DESC`
   - Index: `(author_id, created_at DESC)` ✅

2. **Don't Over-Index**
   - Each index adds write overhead
   - This is a critical path, so worth it
   - We have 4 indexes on posts (reasonable for this use case)

3. **Monitor Index Usage**
   - Check query plans to verify index usage
   - Monitor query performance
   - Remove unused indexes if needed

### Future Considerations

**If Moving to PostgreSQL:**
- Same index will work
- May want to add `NULLS LAST` for author_id NULL handling
- Consider partial indexes for specific queries

**If Adding More Filters:**
- Could add additional composite indexes
- Example: `(author_id, parent_id, created_at)` for reply queries
- Only if query patterns change significantly

### References

- See `docs/PERFORMANCE_ANALYSIS.md` for full performance analysis
- See migration: `db/migrate/20251103225927_add_composite_index_to_posts_on_author_id_and_created_at.rb`
- PostgreSQL Indexing Best Practices: https://www.postgresql.org/docs/current/indexes.html

