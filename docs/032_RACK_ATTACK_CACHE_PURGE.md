# Rack::Attack Cache Purge Guide

## Overview

Rack::Attack stores rate limit counters in the cache (Rails.cache). Sometimes you need to clear these cache entries for testing, troubleshooting, or resetting rate limits.

---

## Quick Methods

### Method 1: Clear All Cache (Simplest)

**Rails Console:**
```ruby
rails console

# Clear all cache (includes Rack::Attack)
Rails.cache.clear
```

**One-liner:**
```bash
rails runner "Rails.cache.clear"
```

**Note**: This clears **ALL** cache, not just Rack::Attack. Use with caution in production.

---

### Method 2: Clear Specific Rate Limit

**Rails Console:**
```ruby
rails console

# Clear specific throttle for IP
Rails.cache.delete("rack::attack:req/ip:127.0.0.1")

# Clear specific throttle for user
Rails.cache.delete("rack::attack:posts/create:123")

# Clear all throttles for an IP
['req/ip', 'posts/create', 'feed/requests', 'api/requests'].each do |throttle|
  Rails.cache.delete("rack::attack:#{throttle}:127.0.0.1")
end

# Clear all throttles for a user
['posts/create', 'follows/action', 'feed/requests'].each do |throttle|
  Rails.cache.delete("rack::attack:#{throttle}:123")
end
```

---

### Method 3: Using the Purge Script

**Clear all cache:**
```bash
rails runner script/purge_rack_attack_cache.rb --all
```

**Clear cache for specific IP:**
```bash
rails runner script/purge_rack_attack_cache.rb --ip 127.0.0.1
```

**Clear cache for specific user:**
```bash
rails runner script/purge_rack_attack_cache.rb --user 123
```

---

## Cache Key Format

Rack::Attack stores cache keys in this format:

```
rack::attack:{throttle_name}:{identifier}
```

**Examples:**
- `rack::attack:req/ip:127.0.0.1` - IP-based general limit
- `rack::attack:posts/create:123` - User-based post creation limit
- `rack::attack:posts/create:127.0.0.1` - IP-based post creation limit (fallback)
- `rack::attack:follows/action:456` - User-based follow/unfollow limit
- `rack::attack:feed/requests:789` - User-based feed request limit

---

## Throttle Names

| Throttle Name | Identifier | Purpose |
|---------------|------------|---------|
| `req/ip` | IP address | General request limit |
| `posts/create` | User ID or IP | Post creation limit |
| `follows/action` | User ID or IP | Follow/unfollow limit |
| `feed/requests` | User ID or IP | Feed request limit |
| `api/requests` | IP address | API request limit |

---

## Methods by Cache Store

### Solid Cache (Current Setup)

**Note**: `delete_matched` was removed from Rails 8.

**Solution**: Clear all cache or delete specific keys:

```ruby
# Clear all (easiest)
Rails.cache.clear

# Or delete specific keys
Rails.cache.delete("rack::attack:req/ip:127.0.0.1")
```

**Cache Expiration**: Rack::Attack cache entries expire naturally via TTL (typically 5 minutes to 1 hour depending on throttle).

---

### Redis (If Using Redis)

**Clear all Rack::Attack keys:**
```ruby
# In Rails console
# Note: delete_matched removed from Rails 8
# Use clear all or specific keys
Rack::Attack.cache.store.clear  # Clears all cache
```

**Or via Redis CLI** (if using Redis):
```bash
redis-cli KEYS "rack::attack:*" | xargs redis-cli DEL
```

---

### Memory Store (Development Only)

**Clear all:**
```ruby
Rails.cache.clear
```

**Clear specific:**
```ruby
Rails.cache.delete("rack::attack:req/ip:127.0.0.1")
```

---

## Use Cases

### 1. Testing Rate Limiting

**Before testing:**
```ruby
rails runner "Rails.cache.clear"
```

**Then trigger rate limits:**
```bash
# Make many rapid requests
for i in {1..20}; do
  curl http://localhost:3000/
done
```

---

### 2. Resetting Rate Limit for User

**After user complains about being rate limited:**
```ruby
rails console

user_id = 123
['posts/create', 'follows/action', 'feed/requests'].each do |throttle|
  Rails.cache.delete("rack::attack:#{throttle}:#{user_id}")
end
```

---

### 3. Resetting Rate Limit for IP

**After IP is blocked:**
```ruby
rails console

ip = '192.168.1.100'
['req/ip', 'posts/create', 'feed/requests', 'api/requests'].each do |throttle|
  Rails.cache.delete("rack::attack:#{throttle}:#{ip}")
end
```

---

### 4. Development/Testing

**Clear all rate limits before testing:**
```bash
# Add to test setup
rails runner "Rails.cache.clear" && rspec
```

**Or in test helper:**
```ruby
# spec/support/rack_attack_helper.rb
module RackAttackHelper
  def clear_rack_attack_cache
    Rails.cache.clear
  end
end

RSpec.configure do |config|
  config.include RackAttackHelper
end

# In tests
before { clear_rack_attack_cache }
```

---

## Monitoring Cache Size

**Check cache entries:**
```ruby
rails console

# Count all cache entries (approximate)
ActiveRecord::Base.connection.execute(
  "SELECT COUNT(*) as count FROM solid_cache_entries"
).first

# Check cache size
size = ActiveRecord::Base.connection.execute(
  "SELECT SUM(byte_size) as total FROM solid_cache_entries"
).first
puts "#{(size['total'].to_f / 1024 / 1024).round(2)} MB"
```

---

## Best Practices

1. **Don't clear in production** unless necessary (affects all users)
2. **Clear specific keys** when possible (more targeted)
3. **Monitor cache size** to ensure it doesn't grow unbounded
4. **Set TTL on cache** (Rack::Attack does this automatically)
5. **Use Redis** for production if you need pattern matching

---

## Troubleshooting

### Cache Not Clearing

**Check cache store:**
```ruby
rails runner "puts Rails.cache.class.name"
```

**Try direct deletion:**
```ruby
Rails.cache.delete("rack::attack:req/ip:127.0.0.1")
Rails.cache.exist?("rack::attack:req/ip:127.0.0.1")  # Should be false
```

### Rate Limit Still Active After Clearing

1. **Check if you cleared the right key** (verify format)
2. **Wait for TTL to expire** (rate limits reset automatically)
3. **Check if multiple throttles apply** (clear all relevant ones)

---

## Summary

**Quick Clear:**
```bash
rails runner "Rails.cache.clear"
```

**Clear Specific:**
```bash
rails runner script/purge_rack_attack_cache.rb --ip 127.0.0.1
rails runner script/purge_rack_attack_cache.rb --user 123
```

**In Code:**
```ruby
Rails.cache.delete("rack::attack:req/ip:127.0.0.1")
```

**Remember**: Clearing cache resets rate limits immediately, so use carefully in production!

