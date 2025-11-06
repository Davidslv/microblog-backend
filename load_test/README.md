# Load Testing Scripts

Quick reference for running load tests with k6.

## Prerequisites

Install k6:
```bash
brew install k6  # macOS
# or visit https://k6.io/docs/getting-started/installation/
```

## Setup Test Data

First, create test data:

```bash
# Quick test (100 users, 50 posts each)
NUM_USERS=100 POSTS_PER_USER=50 rails runner script/load_test_seed.rb

# Full test (1000 users, 150 posts each)
rails runner script/load_test_seed.rb
```

## Test Scripts Overview

### API Tests (New - Phase 1)

**1. API Baseline Test (`k6_api_baseline.js`)**
- **Purpose**: Quick sanity check for API endpoints
- **Tests**: API login, feed endpoint, filtered feeds, post view, user profile
- **Duration**: ~2 minutes
- **Users**: 10 concurrent
- **Endpoints**: `/api/v1/*` (JSON responses)

**2. API Feed Test (`k6_api_feed_test.js`)**
- **Purpose**: Focus on API feed endpoint performance
- **Tests**: API feed with different filters
- **Duration**: ~5 minutes
- **Users**: Ramps to 100 concurrent
- **Endpoints**: `/api/v1/posts` (JSON responses)

**3. API Comprehensive Test (`k6_api_comprehensive.js`)**
- **Purpose**: Realistic API usage simulation
- **Tests**: All API endpoints with realistic distribution
- **Duration**: ~9 minutes
- **Users**: Ramps to 100 concurrent
- **Endpoints**: `/api/v1/*` (JSON responses)

### Monolith Tests (Existing)

### 1. Baseline Test (`k6_baseline.js`)
**Purpose**: Quick sanity check
- Tests: Login, feed page, filtered feeds, post view, user profile
- **Fixed**: Now includes filter testing and user profile testing
- Duration: ~2 minutes
- Users: 10 concurrent

### 2. Feed Test (`k6_feed_test.js`)
**Purpose**: Focus on feed query performance (critical bottleneck)
- Tests: Feed page with different filters
- **Fixed**: Now tests all filter options (timeline, mine, following)
- Duration: ~5 minutes
- Users: Ramps to 100 concurrent

### 3. Comprehensive Test (`k6_comprehensive.js`)
**Purpose**: Realistic user behavior simulation
- Tests: All endpoints with realistic distribution
  - 40% feed views (with filter testing)
  - 25% post views
  - 12% user profiles
  - 5% post creation
  - 3% follow/unfollow
- **Fixed**:
  - Added CSRF token handling for POST requests
  - Added filter parameter testing
  - Added pagination testing (cursor and replies_cursor)
  - Fixed DELETE method handling (uses POST with _method=delete)
  - Added pagination link extraction and testing
- Duration: ~9 minutes
- Users: Ramps to 100 concurrent

### 4. Stress Test (`k6_stress_test.js`)
**Purpose**: Find breaking point WITH rate limiting
- Tests: Feed page under extreme load (will trigger rate limits)
- Duration: ~10 minutes
- Users: Ramps to 200 concurrent
- **Note**: This tests rate limiting behavior under stress

### 5. Stress Test Without Limits (`k6_stress_test_no_limits.js`)
**Purpose**: Find TRUE breaking point (no rate limiting)
- Tests: Feed page under extreme load without rate limit constraints
- Duration: ~12 minutes
- Users: Ramps to 500 concurrent
- **Requires**: `DISABLE_RACK_ATTACK=true` in environment
- **Use**: To find actual application capacity

### 6. Stress Test With IP Spoofing (`k6_stress_test_with_ip_spoofing.js`)
**Purpose**: Test rate limiting with distributed load
- Tests: Feed page with distributed users/IPs
- Duration: ~8 minutes
- Users: Ramps to 300 concurrent
- **Use**: To test rate limiting behavior with realistic load distribution

## Run Tests

### API vs Monolith Comparison

**Compare Performance:**
```bash
# Run monolith baseline
k6 run load_test/k6_baseline.js > monolith_results.txt

# Run API baseline
k6 run load_test/k6_api_baseline.js > api_results.txt

# Compare results
diff monolith_results.txt api_results.txt
```

**Quick API Test:**
```bash
k6 run load_test/k6_api_baseline.js
```

**API Feed Performance:**
```bash
k6 run load_test/k6_api_feed_test.js
```

**API Comprehensive:**
```bash
k6 run load_test/k6_api_comprehensive.js
```

### Docker Setup (Recommended)

**Start services:**
```bash
# Start with 3 web instances for load balancing
docker compose up -d --scale web=3

# Verify services are running
docker compose ps
```

**Run tests:**
```bash
# All tests use http://localhost (Traefik load balancer)
# This tests the full stack: Load Balancer -> 3 Web Servers -> Database

# Quick Baseline
k6 run load_test/k6_baseline.js

# Test Feed Performance
k6 run load_test/k6_feed_test.js

# Comprehensive Test
k6 run load_test/k6_comprehensive.js

# Stress Test (will trigger rate limits)
k6 run load_test/k6_stress_test.js
```

### Local Development

If running locally without Docker:

```bash
# Start Rails server
bin/dev

# Run tests (use direct port)
BASE_URL=http://localhost:3000 k6 run load_test/k6_baseline.js
```

### Quick Baseline
```bash
k6 run load_test/k6_baseline.js
```

### Test Feed Performance
```bash
k6 run load_test/k6_feed_test.js
```

### Comprehensive Test
```bash
k6 run load_test/k6_comprehensive.js
```

### Stress Test (With Rate Limiting)
```bash
# Tests behavior under stress with rate limiting enabled
k6 run load_test/k6_stress_test.js
```

### Stress Test (Without Rate Limiting)
```bash
# Find true application capacity - disable rate limiting first

# Option 1: Set environment variable in docker-compose.yml
# Edit docker-compose.yml and add to web service:
#   environment:
#     DISABLE_RACK_ATTACK: "true"

# Option 2: Restart with environment variable
docker compose down
DISABLE_RACK_ATTACK=true docker compose up -d --scale web=3

# Then run stress test
k6 run load_test/k6_stress_test_no_limits.js

# Remember to re-enable rate limiting after testing!
docker compose down
docker compose up -d --scale web=3
```

### Stress Test (With IP Spoofing / Distributed Load)
```bash
# Tests rate limiting with distributed user load
k6 run load_test/k6_stress_test_with_ip_spoofing.js
```

## Customize Tests

Set environment variables:

```bash
# Custom base URL (default: http://localhost for Docker, use :3000 for local)
BASE_URL=http://localhost:3000 k6 run load_test/k6_baseline.js

# Custom user count (must match seeded data)
NUM_USERS=5000 k6 run load_test/k6_comprehensive.js

# Custom post count
NUM_POSTS=200000 k6 run load_test/k6_comprehensive.js

# Disable rate limiting in application (for testing without limits)
# Note: Set in docker-compose.yml or when starting Rails
DISABLE_RACK_ATTACK=true
```

## What's Tested

✅ **Endpoints:**
- GET / (feed with filters)
- GET /posts/:id (post view with replies)
- GET /users/:id (user profile)
- POST /posts (create post/reply)
- POST /follow/:user_id (follow user)
- DELETE /follow/:user_id (unfollow user)

✅ **Features:**
- Filter parameters (timeline, mine, following)
- Cursor-based pagination (posts feed)
- Replies pagination (replies_cursor)
- User profile pagination
- CSRF token handling
- Session/cookie management

✅ **Metrics:**
- Response times (p95, p99)
- Error rates
- Request throughput
- Custom metrics per endpoint type
- Rate limit hits (429 responses) - NEW
- Load balancing distribution (via Traefik)

✅ **Docker & Load Balancing:**
- Tests through Traefik load balancer (http://localhost)
- Validates load distribution across 3 web servers
- Tests rate limiting (rack-attack) behavior
- Validates distributed caching and session handling

## Monitor During Tests

### Docker Setup

```bash
# Watch web container logs (all instances)
docker compose logs -f web

# Watch specific web container
docker compose logs -f web-1

# Watch database logs
docker compose logs -f db

# Monitor container resources
docker stats

# Check Traefik dashboard (load balancer)
# Open: http://localhost:8080
```

### Local Development

```bash
# Watch Rails logs
tail -f log/development.log | grep -E "Completed|Error|Slow|Rack::Attack"

# Watch system resources
./script/monitor_load_test.sh
```

### Rate Limiting Monitoring

```bash
# Check for rate limit hits in logs
docker compose logs web | grep -i "rack.attack\|throttled\|429"

# Or in Rails logs
tail -f log/development.log | grep -i "rack.attack"
```

## Troubleshooting

**CSRF Token Errors:**
- Scripts now extract tokens from HTML
- If still failing, check that csrf_meta_tags is in layout

**404 Errors:**
- Normal for random post/user IDs
- Scripts handle 404s gracefully
- Use realistic NUM_USERS and NUM_POSTS values

**Session Issues:**
- Cookies are extracted from login response
- Make sure dev login route is working

**Rate Limiting (429 Errors):**
- **Expected behavior** under high load
- Scripts track rate limit hits as a metric
- Rate limits (rack-attack):
  - General: 300 req/5min per IP
  - Posts: 10/min per user
  - Follows: 50/hour per user
  - Feeds: 100/min per user
- To test without rate limits: Set `DISABLE_RACK_ATTACK=true` in docker-compose.yml
- To adjust limits: Edit `config/initializers/rack_attack.rb`

**Load Balancing Issues:**
- Verify all web containers are running: `docker compose ps web`
- Check Traefik dashboard: http://localhost:8080
- Verify requests are distributed: Check logs from different web containers
- Ensure all containers are healthy: `docker compose ps`

**Connection Errors:**
- Verify Docker services are running: `docker compose ps`
- Check network connectivity: `docker compose exec web-1 ping db`
- Verify database is accessible: `docker compose exec db pg_isready`

## wrk Testing (Simple Baseline)

**Simple Public Feed Test:**
```bash
# No authentication - just public feed
wrk -t12 -c150 -d30s http://localhost:3000/

# Or use simple script
wrk -t12 -c150 -d30s -s load_test/wrk_simple.lua http://localhost:3000/
```

**Authenticated Feed Test:**
```bash
# Tests authenticated feeds with filters (basic cookie handling)
wrk -t12 -c150 -d30s -s load_test/wrk_feed.lua http://localhost:3000/
```

**What wrk_feed.lua Tests:**
- ✅ Login via dev route
- ✅ Extracts session cookies
- ✅ Tests filter options (timeline, mine, following)
- ✅ Uses cookies for authenticated requests

**Limitations:**
- ⚠️ Cookie handling is basic (wrk limitation)
- ⚠️ No POST requests (CSRF tokens complex in wrk)
- ⚠️ No pagination testing
- ⚠️ For comprehensive testing, use k6 instead

**When to Use wrk:**
- Quick baseline throughput testing
- Simple public feed performance
- Fast, lightweight testing

**When to Use k6:**
- Comprehensive feature testing
- Authenticated user scenarios
- POST requests (with CSRF)
- Pagination testing
- Realistic user behavior

## Stress Testing with Rate Limiting

When rack-attack is enabled, you have several options for stress testing:

### Quick Reference

**Test WITH rate limiting (default):**
```bash
k6 run load_test/k6_stress_test.js
```

**Test WITHOUT rate limiting (true capacity):**
```bash
# Disable rate limiting
DISABLE_RACK_ATTACK=true docker compose up -d --scale web=3

# Run test
k6 run load_test/k6_stress_test_no_limits.js

# Re-enable after testing
docker compose down && docker compose up -d --scale web=3
```

**Test with distributed load:**
```bash
k6 run load_test/k6_stress_test_with_ip_spoofing.js
```

**📚 See [STRESS_TESTING_WITH_RATE_LIMITS.md](STRESS_TESTING_WITH_RATE_LIMITS.md)** for comprehensive guide on stress testing with rate limiting.

---

See `docs/005_LOAD_TESTING.md` for detailed documentation.
See `docs/009_TEST_SCRIPT_ANALYSIS.md` for analysis of what was fixed.
See `docs/008_WRK_RESULTS_EXPLANATION.md` for interpreting wrk results.
