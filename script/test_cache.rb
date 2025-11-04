#!/usr/bin/env ruby
# Script to test and verify caching is working
# Usage: rails runner script/test_cache.rb

require 'benchmark'

puts "=" * 60
puts "Cache Verification Test"
puts "=" * 60
puts

# Test 1: Basic cache read/write
puts "1. Testing Basic Cache Operations"
puts "-" * 60
Rails.cache.write("test_key", "test_value", expires_in: 1.minute)
value = Rails.cache.read("test_key")
puts "   Write & Read: #{value == 'test_value' ? '✅ PASS' : '❌ FAIL'}"
puts

# Test 2: Cache key existence
puts "2. Testing Cache Key Existence"
puts "-" * 60
Rails.cache.write("user_feed:1:", ["posts", "cursor", true], expires_in: 5.minutes)
exists = Rails.cache.exist?("user_feed:1:")
puts "   Cache key exists: #{exists ? '✅ PASS' : '❌ FAIL'}"
puts

# Test 3: Performance comparison (cache hit vs miss)
puts "3. Performance Test: Cache Hit vs Miss"
puts "-" * 60
user = User.first
exit unless user

# Clear cache first (note: delete_matched removed from Rails 8, using clear instead)
# We'll delete known keys manually
["user_feed:#{user.id}:", "user_feed:#{user.id}:123"].each { |k| Rails.cache.delete(k) }

# Cache miss (first request)
puts "   First request (cache miss):"
time_miss = Benchmark.realtime do
  posts_relation = user.feed_posts.timeline
  posts = posts_relation.limit(20).to_a
end
puts "     Time: #{(time_miss * 1000).round(2)}ms"
puts "     Posts loaded: #{posts.count rescue 'N/A'}"
puts

# Cache hit (second request - should be faster)
puts "   Second request (cache hit):"
time_hit = Benchmark.realtime do
  cache_key = "user_feed:#{user.id}:"
  cached = Rails.cache.read(cache_key)
  if cached
    posts = cached[0]
  else
    posts_relation = user.feed_posts.timeline
    posts = posts_relation.limit(20).to_a
    Rails.cache.write(cache_key, [posts, nil, false], expires_in: 5.minutes)
  end
end
puts "     Time: #{(time_hit * 1000).round(2)}ms"
puts "     Posts loaded: #{posts.count rescue 'N/A'}"
puts "     Speedup: #{(time_miss / time_hit).round(2)}x faster" if time_hit > 0
puts

# Test 4: Check Solid Cache entries in database
puts "4. Checking Solid Cache Database"
puts "-" * 60
begin
  cache_entries = ActiveRecord::Base.connection.execute(
    "SELECT COUNT(*) as count FROM solid_cache_entries"
  ).first
  puts "   Cache entries in database: #{cache_entries['count']}"
  puts "   ✅ Solid Cache table accessible"
rescue => e
  puts "   ❌ Error accessing cache: #{e.message}"
end
puts

# Test 5: Cache invalidation
puts "5. Testing Cache Invalidation"
puts "-" * 60
test_key = "user_feed:999:"
Rails.cache.write(test_key, ["test"], expires_in: 5.minutes)
puts "   Before deletion: #{Rails.cache.exist?(test_key) ? 'exists' : 'missing'}"
Rails.cache.delete(test_key)
puts "   After deletion: #{Rails.cache.exist?(test_key) ? '❌ FAIL (still exists)' : '✅ PASS (deleted)'}"
puts

# Test 6: Cache statistics
puts "6. Cache Statistics"
puts "-" * 60
begin
  # Count cache entries by namespace
  namespace = Rails.env
  count = ActiveRecord::Base.connection.execute(
    "SELECT COUNT(*) as count FROM solid_cache_entries WHERE key LIKE ?",
    ["%#{namespace}%"]
  ).first
  puts "   Cache entries for '#{namespace}': #{count['count'] rescue 'N/A'}"

  # Get cache size
  size = ActiveRecord::Base.connection.execute(
    "SELECT SUM(byte_size) as total_size FROM solid_cache_entries"
  ).first
  total_mb = (size['total_size'].to_f / 1024 / 1024).round(2) rescue 0
  puts "   Total cache size: #{total_mb} MB"
rescue => e
  puts "   Could not get statistics: #{e.message}"
end
puts

puts "=" * 60
puts "Test Complete!"
puts "=" * 60
puts
puts "To verify in production:"
puts "1. Check Rails logs for 'Cache read' and 'Cache write' messages"
puts "2. Compare response times (first request vs subsequent requests)"
puts "3. Monitor database query counts (should decrease with caching)"
puts "4. Check Solid Cache table size: SELECT COUNT(*) FROM solid_cache_entries"

