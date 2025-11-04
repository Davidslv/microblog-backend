# Stress Testing with Rate Limiting (rack-attack)

This guide explains how to stress test your application when rack-attack rate limiting middleware is enabled.

## The Challenge

When rate limiting is enabled, stress tests may hit rate limits before finding the application's true capacity. You need strategies to:

1. **Test application capacity** without rate limit interference
2. **Test rate limiting behavior** under load
3. **Test realistic scenarios** with rate limiting enabled

## Strategies

### Strategy 1: Disable Rate Limiting for Capacity Testing

**When to use**: Finding the true breaking point of your application

**How to do it:**

#### Option A: Environment Variable (Recommended)

```bash
# Stop services
docker compose down

# Start with rate limiting disabled
DISABLE_RACK_ATTACK=true docker compose up -d --scale web=3

# Run stress test
k6 run load_test/k6_stress_test_no_limits.js

# Re-enable rate limiting
docker compose down
docker compose up -d --scale web=3
```

#### Option B: Modify docker-compose.yml Temporarily

Edit `docker-compose.yml`:

```yaml
web:
  environment:
    DISABLE_RACK_ATTACK: "true"
    # ... other env vars
```

Then:

```bash
docker compose up -d --scale web=3
k6 run load_test/k6_stress_test_no_limits.js

# Remember to remove DISABLE_RACK_ATTACK after testing!
```

#### Option C: Rails Console (For Local Development)

```ruby
# In Rails console
Rack::Attack.enabled = false

# Run tests...
# Then re-enable
Rack::Attack.enabled = true
```

**What to expect:**
- ✅ No 429 responses (rate limit errors)
- ✅ Higher error rates indicate true application limits
- ✅ Server errors (500, 502, 503) show actual breaking points
- ✅ Database connection pool exhaustion
- ✅ Memory/CPU limits

---

### Strategy 2: Test Rate Limiting Behavior

**When to use**: Validating that rate limiting works correctly under load

**How to do it:**

```bash
# Keep rate limiting enabled (default)
docker compose up -d --scale web=3

# Run stress test that intentionally triggers rate limits
k6 run load_test/k6_stress_test.js
```

**What to expect:**
- ✅ 429 responses (rate limit exceeded)
- ✅ Rate limit headers in responses
- ✅ Retry-After headers
- ✅ Rate limiting protects the application from overload
- ✅ Application stays responsive despite high load

**Metrics to monitor:**
- `rate_limit_hits` counter
- `http_req_status{status:429}` count
- Application response times (should stay reasonable)
- Server errors (should be minimal)

---

### Strategy 3: Distributed Load (IP/User Spoofing)

**When to use**: Testing with realistic load distribution

**How to do it:**

```bash
# Keep rate limiting enabled
docker compose up -d --scale web=3

# Run stress test with distributed user load
k6 run load_test/k6_stress_test_with_ip_spoofing.js
```

**What this does:**
- Distributes requests across many different users
- Each user has separate rate limit counters
- More realistic simulation of real traffic
- Rate limits apply per user, not globally

**Limitations:**
- IP-based limits still apply (300 req/5min per IP)
- k6 runs from one machine, so all requests come from one IP
- For true IP distribution, use multiple k6 instances or k6 Cloud

---

### Strategy 4: Multiple k6 Instances (True IP Distribution)

**When to use**: Testing with multiple source IPs

**How to do it:**

```bash
# Terminal 1
k6 run --vus 50 --duration 5m load_test/k6_stress_test.js

# Terminal 2 (different machine or VPN)
k6 run --vus 50 --duration 5m load_test/k6_stress_test.js

# Terminal 3 (another machine)
k6 run --vus 50 --duration 5m load_test/k6_stress_test.js
```

**Or use k6 Cloud:**
```bash
k6 cloud load_test/k6_stress_test.js
```

k6 Cloud distributes load across multiple geographic locations with different IPs.

---

### Strategy 5: Increase Rate Limits Temporarily

**When to use**: Testing application capacity with higher (but still limited) rate limits

**How to do it:**

Edit `config/initializers/rack_attack.rb` temporarily:

```ruby
# Increase limits for stress testing
throttle("req/ip", limit: 10000, period: 5.minutes) do |req|
  req.ip
end

throttle("feed/requests", limit: 1000, period: 1.minute) do |req|
  # ...
end
```

Then restart:

```bash
docker compose restart web
k6 run load_test/k6_stress_test.js
```

**Remember to revert changes after testing!**

---

## Recommended Testing Workflow

### Step 1: Test Rate Limiting Behavior

```bash
# Verify rate limiting works
docker compose up -d --scale web=3
k6 run load_test/k6_stress_test.js

# Check metrics:
# - rate_limit_hits should be > 0
# - Application should stay responsive
# - 429 responses should be returned correctly
```

### Step 2: Find True Capacity

```bash
# Disable rate limiting
DISABLE_RACK_ATTACK=true docker compose up -d --scale web=3

# Run aggressive stress test
k6 run load_test/k6_stress_test_no_limits.js

# Check metrics:
# - No 429 responses (or very few)
# - Server errors indicate true limits
# - Response times show degradation points
# - Throughput shows maximum capacity
```

### Step 3: Test Realistic Load

```bash
# Re-enable rate limiting
docker compose down
docker compose up -d --scale web=3

# Test with realistic user distribution
k6 run load_test/k6_stress_test_with_ip_spoofing.js

# Check metrics:
# - Some rate limiting (expected)
# - Application handles load gracefully
# - Rate limits protect the system
```

---

## Understanding Results

### With Rate Limiting Enabled

**Good signs:**
- ✅ 429 responses at high load (rate limiting working)
- ✅ Application stays responsive (rate limiting protects it)
- ✅ Low server errors (500, 502, 503)
- ✅ Reasonable response times despite high load

**Bad signs:**
- ❌ Application crashes despite rate limiting
- ❌ High server errors (500, 502, 503)
- ❌ Response times degrade significantly
- ❌ Rate limiting not working (no 429 responses)

### Without Rate Limiting

**Good signs:**
- ✅ High throughput (requests/sec)
- ✅ Reasonable response times up to breaking point
- ✅ Graceful degradation (errors increase gradually)
- ✅ Clear breaking point identified

**Bad signs:**
- ❌ Application crashes immediately
- ❌ Memory leaks (memory usage keeps increasing)
- ❌ Database connection exhaustion
- ❌ No clear breaking point (unstable)

---

## Clearing Rate Limit Counters

If you need to reset rate limits during testing:

```bash
# Clear all cache (includes rate limit counters)
docker compose exec web-1 bin/rails runner "Rails.cache.clear"

# Or clear specific IP/user
docker compose exec web-1 bin/rails runner "script/purge_rack_attack_cache.rb --ip 127.0.0.1"
```

---

## Monitoring During Stress Tests

### Docker Setup

```bash
# Watch all web containers
docker compose logs -f web | grep -E "Completed|Error|Rack::Attack|429"

# Monitor resources
docker stats

# Check rate limit hits
docker compose logs web | grep -i "rack.attack\|throttled" | wc -l

# Check Traefik dashboard
# Open: http://localhost:8080
```

### Key Metrics

1. **Rate Limit Hits**: How many 429 responses
2. **Server Errors**: 500, 502, 503 responses
3. **Response Times**: p95, p99 latencies
4. **Throughput**: Requests per second
5. **Error Rate**: Percentage of failed requests

---

## Best Practices

1. **Always test with rate limiting first** to validate it works
2. **Then test without limits** to find true capacity
3. **Compare results** to understand rate limiting impact
4. **Test incrementally** - don't jump to 500 users immediately
5. **Monitor all metrics** - not just request count
6. **Test realistic scenarios** - user distribution, request patterns
7. **Document breaking points** for capacity planning

---

## Example: Complete Stress Test Session

```bash
# 1. Start services with rate limiting
docker compose up -d --scale web=3

# 2. Test rate limiting behavior
echo "Testing with rate limiting..."
k6 run load_test/k6_stress_test.js --out json=results_with_limits.json

# 3. Disable rate limiting
echo "Disabling rate limiting..."
docker compose down
DISABLE_RACK_ATTACK=true docker compose up -d --scale web=3

# 4. Test true capacity
echo "Testing true capacity..."
k6 run load_test/k6_stress_test_no_limits.js --out json=results_no_limits.json

# 5. Re-enable rate limiting
echo "Re-enabling rate limiting..."
docker compose down
docker compose up -d --scale web=3

# 6. Compare results
echo "Comparing results..."
# Analyze JSON files or use k6's built-in comparison
```

---

## Summary

**For capacity testing**: Disable rate limiting (`DISABLE_RACK_ATTACK=true`)

**For rate limiting validation**: Keep rate limiting enabled

**For realistic testing**: Use distributed load with multiple users

**For production-like testing**: Use multiple k6 instances or k6 Cloud

The key is understanding what you're testing:
- ✅ **Rate limiting behavior** → Keep enabled
- ✅ **Application capacity** → Disable rate limiting
- ✅ **Realistic scenarios** → Distributed load with rate limiting

