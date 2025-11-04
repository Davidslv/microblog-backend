# Rate Limiting Implementation

## Overview

Rate limiting has been implemented using **Rack::Attack** middleware to protect the application against abuse, DDoS attacks, and ensure fair resource usage.

**Implementation Date**: 2025-11-04
**Strategy**: Option A - Rack::Attack (from `docs/028_SCALING_AND_PERFORMANCE_STRATEGIES.md`)

---

## Configuration

### Gem Installation

Added to `Gemfile`:
```ruby
gem "rack-attack"
```

### Initializer

Created `config/initializers/rack_attack.rb` with the following rate limits:

| Rate Limit | Limit | Period | Scope | Purpose |
|------------|-------|--------|-------|---------|
| **General Requests** | 300 | 5 minutes | IP address | Baseline protection against abuse |
| **Post Creation** | 10 | 1 minute | User (session) or IP | Prevent spam posts |
| **Follow/Unfollow** | 50 | 1 hour | User (session) or IP | Prevent automated following abuse |
| **Feed Requests** | 100 | 1 minute | User (session) or IP | Prevent excessive feed refreshing |
| **API Requests** | 60 | 1 minute | IP address | Future API endpoint protection |

---

## Storage Backend

**Current**: Solid Cache (SQLite in development, can use PostgreSQL in production)

```ruby
Rack::Attack.cache.store = Rails.cache
```

**Benefits**:
- ✅ No additional infrastructure needed
- ✅ Uses existing cache setup
- ✅ Works across multiple server instances (with shared database)

**Alternative Options** (if needed):
- Redis: For high-throughput production environments
- Memory: For single-server development (not recommended for production)

---

## Rate Limit Details

### 1. General IP Rate Limit

```ruby
throttle('req/ip', limit: 300, period: 5.minutes) do |req|
  req.ip
end
```

**Purpose**: Baseline protection against abuse
**Scope**: All requests from same IP address
**Limit**: 300 requests per 5 minutes
**Response**: 429 Too Many Requests after limit exceeded

**Use Case**: Prevents single IP from overwhelming the server

---

### 2. Post Creation Rate Limit

```ruby
throttle('posts/create', limit: 10, period: 1.minute) do |req|
  if req.path == '/posts' && req.post?
    session_key = req.session['user_id'] rescue nil
    session_key || req.ip
  end
end
```

**Purpose**: Prevent spam posts
**Scope**: POST requests to `/posts`
**Limit**: 10 posts per minute per user
**Fallback**: Uses IP if no session (unauthenticated abuse)

**Use Case**: Prevents users from flooding the feed with posts

---

### 3. Follow/Unfollow Rate Limit

```ruby
throttle('follows/action', limit: 50, period: 1.hour) do |req|
  if req.path.start_with?('/follow/') && (req.post? || req.delete?)
    session_key = req.session['user_id'] rescue nil
    session_key || req.ip
  end
end
```

**Purpose**: Prevent automated following/unfollowing abuse
**Scope**: POST and DELETE requests to `/follow/:user_id`
**Limit**: 50 actions per hour per user
**Fallback**: Uses IP if no session

**Use Case**: Prevents bots from rapidly following/unfollowing users

---

### 4. Feed Request Rate Limit

```ruby
throttle('feed/requests', limit: 100, period: 1.minute) do |req|
  if (req.path == '/posts' || req.path == '/') && req.get?
    session_key = req.session['user_id'] rescue nil
    session_key || req.ip
  end
end
```

**Purpose**: Prevent excessive feed refreshing
**Scope**: GET requests to `/posts` or `/` (root)
**Limit**: 100 requests per minute per user
**Fallback**: Uses IP if no session

**Use Case**: Prevents users from rapidly refreshing feed (expensive queries)

---

### 5. API Rate Limit (Future)

```ruby
throttle('api/requests', limit: 60, period: 1.minute) do |req|
  req.ip if req.path.start_with?('/api')
end
```

**Purpose**: Placeholder for future API endpoints
**Scope**: Any request to `/api/*`
**Limit**: 60 requests per minute per IP

---

## Response Format

When a rate limit is exceeded, the server returns:

**Status Code**: `429 Too Many Requests`

**Headers**:
- `X-RateLimit-Limit`: The rate limit (e.g., "300")
- `X-RateLimit-Remaining`: Remaining requests (always "0" when throttled)
- `X-RateLimit-Reset`: Unix timestamp when limit resets
- `Retry-After`: Seconds until limit resets

**Body**:
```json
{
  "error": "Rate limit exceeded",
  "message": "Too many requests. Please try again later.",
  "retry_after": 123
}
```

---

## Testing

### Manual Testing

1. **Start Rails server**:
   ```bash
   rails server
   ```

2. **Run test script**:
   ```bash
   rails runner script/test_rate_limiting.rb
   ```

3. **Test with curl**:
   ```bash
   # Make rapid requests to trigger rate limit
   for i in {1..20}; do
     curl -v http://localhost:3000/
     sleep 0.1
   done
   ```

4. **Check for 429 responses**:
   - Look for `HTTP/1.1 429 Too Many Requests`
   - Check headers for rate limit information

### Expected Behavior

- **First requests**: Should return 200 OK with rate limit headers
- **After limit**: Should return 429 with rate limit exceeded message
- **After reset**: Should return 200 OK again

---

## Monitoring

### Logging

Rate limit events are logged:
```
[Rack::Attack] Throttled 127.0.0.1 for req/ip
```

### Metrics to Monitor

1. **Rate Limit Hit Rate**: How often limits are exceeded
2. **Throttled IPs**: Which IPs are being throttled most
3. **Throttled Endpoints**: Which endpoints are hit most
4. **User Impact**: How many legitimate users are affected

### Monitoring Tools

- **Rails Logs**: Check for `[Rack::Attack]` messages
- **Application Monitoring**: Integrate with New Relic, DataDog, etc.
- **Custom Dashboard**: Track rate limit metrics

---

## Configuration Options

### Disable Rate Limiting

Set environment variable:
```bash
DISABLE_RACK_ATTACK=true rails server
```

Or in initializer:
```ruby
Rack::Attack.enabled = false
```

### Adjust Rate Limits

Edit `config/initializers/rack_attack.rb`:
```ruby
# Increase post creation limit
throttle('posts/create', limit: 20, period: 1.minute) do |req|
  # ...
end
```

### Use Different Cache Store

For Redis (production):
```ruby
Rack::Attack.cache.store = ActiveSupport::Cache::RedisCacheStore.new(
  url: ENV['REDIS_URL']
)
```

For Memory (development only):
```ruby
Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
```

---

## Performance Impact

### Overhead

- **Latency**: ~1-5ms per request (middleware check)
- **Memory**: Minimal (uses cache store)
- **CPU**: Minimal (simple key lookups)

### Scalability

- **Works with**: Single server or multiple servers (with shared cache)
- **Recommended**: Use Redis for high-traffic production
- **Limitation**: Solid Cache may have performance limits at very high throughput

---

## Troubleshooting

### Rate Limiting Not Working

1. **Check Rack::Attack is loaded**:
   ```ruby
   rails runner "puts Rack::Attack.enabled"
   ```

2. **Check cache store**:
   ```ruby
   rails runner "puts Rack::Attack.cache.store.class.name"
   ```

3. **Check middleware**:
   ```ruby
   rails runner "puts Rails.application.middleware.to_a.grep(/Rack::Attack/)"
   ```

### False Positives

If legitimate users are being throttled:

1. **Increase limits** in `config/initializers/rack_attack.rb`
2. **Adjust time windows** (e.g., 5 minutes → 10 minutes)
3. **Add whitelist** for trusted IPs:
   ```ruby
   Rack::Attack.safelist('allow from trusted IP') do |req|
     req.ip == '1.2.3.4'
   end
   ```

### Rate Limits Too Permissive

If abuse is still occurring:

1. **Decrease limits** in `config/initializers/rack_attack.rb`
2. **Add additional throttles** for specific endpoints
3. **Implement IP blocking** for repeat offenders

---

## Best Practices

1. **Start Conservative**: Begin with stricter limits, relax if needed
2. **Monitor Impact**: Track rate limit hits and user complaints
3. **Adjust Based on Usage**: Tune limits based on actual traffic patterns
4. **Document Changes**: Keep track of limit adjustments
5. **Test Regularly**: Verify rate limiting works after deployments

---

## Future Enhancements

1. **User Tiers**: Different limits for basic vs premium users
2. **Dynamic Limits**: Adjust limits based on server load
3. **IP Whitelisting**: Allow trusted IPs to bypass limits
4. **Rate Limit Dashboard**: UI to monitor and adjust limits
5. **Integration with Monitoring**: Send rate limit events to monitoring tools

---

## References

- **Strategy Document**: `docs/028_SCALING_AND_PERFORMANCE_STRATEGIES.md`
- **Rack::Attack Documentation**: https://github.com/rack/rack-attack
- **Test Script**: `script/test_rate_limiting.rb`

---

## Summary

✅ **Rate limiting implemented** using Rack::Attack
✅ **5 rate limits configured** (general, posts, follows, feeds, API)
✅ **Solid Cache storage** (no additional infrastructure)
✅ **429 responses** with helpful headers
✅ **Logging enabled** for monitoring
✅ **Test script** available for verification

**Status**: Ready for production use. Monitor and adjust limits as needed.

