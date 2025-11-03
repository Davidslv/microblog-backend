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
**Purpose**: Find breaking point
- Tests: Feed page under extreme load
- Duration: ~10 minutes
- Users: Ramps to 200 concurrent

## Run Tests

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

### Stress Test
```bash
k6 run load_test/k6_stress_test.js
```

## Customize Tests

Set environment variables:

```bash
# Custom base URL
BASE_URL=http://localhost:3000 k6 run load_test/k6_baseline.js

# Custom user count (must match seeded data)
NUM_USERS=5000 k6 run load_test/k6_comprehensive.js

# Custom post count
NUM_POSTS=200000 k6 run load_test/k6_comprehensive.js
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

## Monitor During Tests

```bash
# Watch Rails logs
tail -f log/development.log | grep -E "Completed|Error|Slow"

# Watch system resources
./script/monitor_load_test.sh
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

See `docs/LOAD_TESTING.md` for detailed documentation.
See `docs/TEST_SCRIPT_ANALYSIS.md` for analysis of what was fixed.
See `docs/WRK_RESULTS_EXPLANATION.md` for interpreting wrk results.
