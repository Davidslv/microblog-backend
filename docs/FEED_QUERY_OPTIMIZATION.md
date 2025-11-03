# Feed Query Optimization: JOIN Instead of IN Clause

## Problem

The original feed query used a large `IN` clause that became inefficient for users with many follows:

```ruby
# Original implementation
def feed_posts
  following_ids = following.pluck(:id)  # Could be 2,500+ IDs
  Post.where(author_id: [id] + following_ids)
end
```

**Generated SQL:**
```sql
SELECT * FROM posts
WHERE author_id IN (?, ?, ?, ..., 2506 times)
ORDER BY created_at DESC
```

**Issues:**
1. **Large IN clauses** - SQLite struggles with 2,500+ item IN clauses
2. **Two queries** - First query to get following IDs, then feed query
3. **Inefficient index usage** - Database may not optimize large IN clauses well
4. **Memory overhead** - Loading all following IDs into memory

## Solution

Use a `JOIN` instead of `IN` clause:

```ruby
# Optimized implementation
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
LEFT JOIN follows ON posts.author_id = follows.followed_id AND follows.follower_id = ?
WHERE posts.author_id = ? OR follows.followed_id IS NOT NULL
ORDER BY created_at DESC
```

## How It Works

1. **LEFT JOIN**: Joins posts with follows table where the post author is followed by the current user
2. **WHERE clause**: Includes own posts (`author_id = ?`) OR posts from followed users (`follows.followed_id IS NOT NULL`)
3. **DISTINCT**: Prevents duplicate posts if user follows themselves or has multiple relationships

## Performance Benefits

### Before (IN Clause)
- **Query 1**: Get following IDs (~50-100ms for 2,500 follows)
- **Query 2**: Get posts with large IN clause (~100-500ms)
- **Total**: ~150-600ms
- **Memory**: Loads all following IDs into memory

### After (JOIN)
- **Single query**: JOIN + WHERE (~50-200ms)
- **Total**: ~50-200ms
- **Memory**: No need to load IDs into memory
- **Better index usage**: Database can optimize JOIN better

**Expected Improvement: 50-70% faster**

## Index Usage

The composite index `(author_id, created_at DESC)` is still used effectively:
- JOIN uses index on `follows.follower_id` and `follows.followed_id`
- WHERE clause uses index on `posts.author_id`
- ORDER BY uses composite index on `(author_id, created_at DESC)`

## Also Optimized

The `following` filter in `PostsController` was also optimized:

**Before:**
```ruby
following_ids = current_user.following.pluck(:id)
posts_relation = Post.where(author_id: following_ids).timeline
```

**After:**
```ruby
user_id = Post.connection.quote(current_user.id)
posts_relation = Post.joins(
  "INNER JOIN follows ON posts.author_id = follows.followed_id AND follows.follower_id = #{user_id}"
).timeline.distinct
```

## Testing

The optimization maintains the same functionality:
- ✅ Includes user's own posts
- ✅ Includes posts from followed users
- ✅ Excludes posts from non-followed users
- ✅ Works with cursor-based pagination
- ✅ Maintains `timeline` scope ordering

## SQLite vs PostgreSQL

**SQLite:**
- JOIN optimization works well
- Better than large IN clauses
- Still has single-writer limitation

**PostgreSQL:**
- JOIN optimization excellent
- Better query planner for complex JOINs
- Handles concurrent connections much better

## Migration Notes

**No database migration needed** - This is a query optimization only.

**Backward compatible:**
- Same results
- Same API
- Same behavior
- Just faster!

## Related Optimizations

1. ✅ **Composite Index** - `(author_id, created_at DESC)` - Already added
2. ✅ **JOIN Query** - This optimization
3. ✅ **Cursor Pagination** - Already implemented
4. ⚠️ **Query Caching** - Future optimization
5. ⚠️ **Read Replicas** - For production scaling

## Performance Testing

**Before Optimization:**
```bash
# Test with user following 2,500 users
# Expected: 150-600ms per feed query
```

**After Optimization:**
```bash
# Test with user following 2,500 users  
# Expected: 50-200ms per feed query
# Improvement: 50-70% faster
```

## Code Locations

- **User Model**: `app/models/user.rb` - `feed_posts` method
- **Posts Controller**: `app/controllers/posts_controller.rb` - `following` filter

## References

- See `docs/PERFORMANCE_ANALYSIS.md` for full bottleneck analysis
- See `docs/DATABASE_OPTIMIZATION.md` for composite index details
- See `docs/WRK_RESULTS_AFTER_OPTIMIZATION.md` for load test results

