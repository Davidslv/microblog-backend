# Cache Verification Guide

This guide explains how to verify that caching is working correctly in the microblog application.

## Quick Verification Methods

### 1. Console Testing

**Test basic cache operations:**
```ruby
rails console

# Test write/read
Rails.cache.write("test_key", "test_value", expires_in: 1.minute)
Rails.cache.read("test_key")  # => "test_value"
Rails.cache.exist?("test_key")  # => true

# Test cache for feed
user = User.first
cache_key = "user_feed:#{user.id}:"
Rails.cache.write(cache_key, [["post1", "post2"], "cursor123", true], expires_in: 5.minutes)
Rails.cache.read(cache_key)  # => [["post1", "post2"], "cursor123", true]
```

### 2. Performance Comparison

**Measure response times before and after caching:**

```ruby
rails console

user = User.first

# Clear cache first
# Note: delete_matched removed from Rails 8
# Cache will expire naturally via TTL (5 minutes for feeds)
# With fan-out on write, feed entries are the source of truth

# First request (cache miss) - should be slower
require 'benchmark'
time1 = Benchmark.realtime do
  posts = user.feed_posts.timeline.limit(20).to_a
end
puts "Cache miss: #{(time1 * 1000).round(2)}ms"

# Second request (cache hit) - should be faster
cache_key = "user_feed:#{user.id}:"
cached = Rails.cache.read(cache_key)
if cached
  time2 = Benchmark.realtime { cached[0] }
  puts "Cache hit: #{(time2 * 1000).round(2)}ms"
  puts "Speedup: #{(time1 / time2).round(2)}x faster"
end
```

### 3. Database Inspection

**Check Solid Cache entries directly:**

```sql
-- Count total cache entries
SELECT COUNT(*) FROM solid_cache_entries;

-- View cache entries (keys are binary, so they look like hex)
SELECT key, byte_size, created_at FROM solid_cache_entries LIMIT 10;

-- Check cache size
SELECT SUM(byte_size) as total_bytes FROM solid_cache_entries;
SELECT SUM(byte_size) / 1024.0 / 1024.0 as total_mb FROM solid_cache_entries;
```

**Via Rails console:**
```ruby
# Count cache entries
ActiveRecord::Base.connection.execute("SELECT COUNT(*) as count FROM solid_cache_entries").first
# => {"count" => 123}

# Get cache size
size = ActiveRecord::Base.connection.execute("SELECT SUM(byte_size) as total FROM solid_cache_entries").first
puts "#{(size['total'].to_f / 1024 / 1024).round(2)} MB"
```

### 4. Request Logs

**Monitor Rails logs for cache activity:**

```bash
# Watch for cache operations
tail -f log/development.log | grep -i cache

# Watch for slow requests (cache miss vs cache hit)
tail -f log/development.log | grep "Completed"
```

**Look for:**
- First request: `Completed 200 OK in 200ms` (cache miss, slower)
- Second request: `Completed 200 OK in 10ms` (cache hit, faster)

### 5. Browser Testing

**Test in browser with network tab:**

1. **First request (cache miss):**
   - Open browser DevTools → Network tab
   - Visit `/posts` or `/users/1`
   - Note the response time (should be 50-200ms for feed queries)

2. **Second request (cache hit):**
   - Refresh the same page
   - Response time should be <10ms (much faster)

3. **Verify cache invalidation:**
   - Visit a user's feed (cache miss)
   - Create a new post as that user
   - Refresh the feed (should be cache miss again, as cache was invalidated)

### 6. Test Script

**Run the automated test script:**
```bash
rails runner script/test_cache.rb
```

This script tests:
- Basic cache operations
- Cache key existence
- Performance comparison (cache hit vs miss)
- Cache database connectivity
- Cache invalidation

## Cache Keys Reference

| Cache Key Pattern | TTL | Invalidated When |
|------------------|-----|------------------|
| `user_feed:{user_id}:{cursor}` | 5 minutes | Post created by followed user, follow/unfollow |
| `user:{user_id}` | 1 hour | User profile updated |
| `user_posts:{user_id}:{cursor}` | 5 minutes | New post by user, user deleted |
| `public_posts:{cursor}` | 1 minute | New post created |

## Expected Performance Improvements

| Operation | Before Caching | After Caching (Cache Hit) | Improvement |
|-----------|---------------|---------------------------|-------------|
| Feed query | 50-200ms | <1ms | 50-200x faster |
| User profile | 67ms | <10ms | 6-7x faster |
| Public posts | 20-50ms | <1ms | 20-50x faster |

## Troubleshooting

### Cache Not Working?

1. **Check Solid Cache table exists:**
   ```ruby
   ActiveRecord::Base.connection.table_exists?('solid_cache_entries')
   # => true
   ```

2. **Check cache store configuration:**
   ```ruby
   Rails.cache.class
   # => SolidCache::Store
   ```

3. **Verify cache is enabled:**
   ```ruby
   Rails.application.config.cache_store
   # => :solid_cache_store
   ```

4. **Check cache writes:**
   ```ruby
   Rails.cache.write("test", "value")
   Rails.cache.read("test")  # => "value"
   ```

### Cache Not Invalidating?

**Note:** `delete_matched` was removed from Rails 8. The current implementation relies on TTL-based expiration:

1. **Short TTLs**: Cache expires naturally (1-5 minutes)
2. **Fan-out on write**: Feed entries are the source of truth, cache is just for performance
3. **Specific key deletion**: We only delete specific keys (e.g., `user:123`), not patterns
4. **TTL-based expiration**: Cache automatically expires via TTL, ensuring freshness

### Cache Size Growing?

**Monitor cache size:**
```sql
SELECT SUM(byte_size) / 1024.0 / 1024.0 as total_mb
FROM solid_cache_entries;
```

**Clean old entries:**
```ruby
# Solid Cache automatically cleans up expired entries
# But you can manually clean:
Rails.cache.clear  # WARNING: Clears ALL cache
```

## Production Monitoring

**Key metrics to monitor:**
- Cache hit rate (should be 70-90%)
- Cache size (should stay under configured max_size)
- Response times (should decrease with caching)
- Database query count (should decrease with caching)

**Monitor via application logs:**
```bash
# Track cache operations
grep -c "Cache read" log/production.log
grep -c "Cache write" log/production.log
```

## Summary

To verify caching is working:
1. ✅ Run test script: `rails runner script/test_cache.rb`
2. ✅ Compare response times (first request vs second request)
3. ✅ Check cache entries in database: `SELECT COUNT(*) FROM solid_cache_entries`
4. ✅ Monitor Rails logs for cache operations
5. ✅ Test in browser (Network tab shows response times)

Expected result: Second request should be **significantly faster** (<10ms vs 50-200ms) when cache is working.

