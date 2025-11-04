# Load Testing Guide

This guide explains how to stress test and load test the microblog application to analyze performance under realistic conditions.

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Test Data Setup](#test-data-setup)
4. [Load Testing Tools](#load-testing-tools)
5. [Running Load Tests](#running-load-tests)
6. [Monitoring During Tests](#monitoring-during-tests)
7. [Analyzing Results](#analyzing-results)
8. [Performance Targets](#performance-targets)

---

## Overview

Load testing helps identify:
- **Response time bottlenecks** (especially feed queries)
- **Database connection pool exhaustion**
- **Memory leaks and resource usage**
- **Concurrent request handling capacity**
- **Query performance under load**

### Test Scenarios

We'll test the following critical endpoints:

1. **Feed Page** (`GET /`) - Most critical, 50% of traffic
2. **Post View** (`GET /posts/:id`) - 30% of traffic
3. **Post Creation** (`POST /posts`) - 2% of traffic
4. **User Profile** (`GET /users/:id`) - 12% of traffic
5. **Follow/Unfollow** (`POST /follow/:user_id`) - 0.5% of traffic

---

## Prerequisites

### Install Load Testing Tools

**Option 1: k6 (Recommended)**
```bash
# macOS
brew install k6

# Or download from https://k6.io/docs/getting-started/installation/
```

**Option 2: wrk (Simple & Fast)**
```bash
# macOS
brew install wrk

# Linux
sudo apt-get install wrk
```

**Option 3: Apache Bench (ab) - Usually pre-installed**
```bash
# Check if installed
which ab
```

### Verify Rails Server Configuration

Before testing, ensure your Rails server is configured for production-like performance:

```ruby
# config/puma.rb - Check pool size
pool ENV.fetch("RAILS_MAX_THREADS") { 5 }  # Increase to 10-20 for testing

# config/database.yml - Check connection pool
pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>  # Increase to 25-30
```

---

## Test Data Setup

Before running load tests, you need realistic test data. Use the provided seed script:

```bash
# Run the seed script to create test users and posts
rails runner script/load_test_seed.rb
```

This creates:
- 10,000 users
- 1,500,000 posts (150 per user)
- Variable following relationships (10-5,000 follows per user)
- Replies to posts (0-30 per post)

**Note:** This will take several minutes. For faster testing, use smaller numbers:

```ruby
# In script/load_test_seed.rb, adjust:
NUM_USERS = 1000      # Instead of 10,000
POSTS_PER_USER = 50   # Instead of 150
```

---

## Load Testing Tools

### Tool Comparison

| Tool | Pros | Cons | Best For |
|------|------|------|----------|
| **k6** | Modern, great reporting, JavaScript-based scenarios | Requires Node.js/k6 installation | Complex scenarios, detailed metrics |
| **wrk** | Fast, simple, low overhead | Limited scripting | Quick baseline tests |
| **ab** | Pre-installed, simple | Limited features, no scripting | Quick checks |

### Recommended: k6

k6 provides:
- Realistic user behavior simulation
- Detailed metrics and reporting
- Easy scenario scripting
- HTTP/2 support
- Thresholds and alerts

---

## Running Load Tests

### 1. Start Rails Server

```bash
# Development mode (for testing)
RAILS_ENV=development rails server

# Or production-like mode
RAILS_ENV=production rails server

# In another terminal, monitor logs
tail -f log/development.log
```

### 2. Baseline Test (Quick Check)

```bash
# Simple wrk test - 100 requests, 10 concurrent connections
wrk -t4 -c10 -d10s http://localhost:3000/

# Or with k6
k6 run load_test/k6_baseline.js
```

### 3. Feed Page Load Test (Most Critical)

This tests the feed query performance:

```bash
# k6 - Feed page with authentication
k6 run load_test/k6_feed_test.js

# Or wrk (requires cookie handling)
wrk -t4 -c50 -d30s -s load_test/wrk_feed.lua http://localhost:3000/
```

### 4. Comprehensive Load Test

Tests all endpoints with realistic traffic distribution:

```bash
k6 run load_test/k6_comprehensive.js
```

### 5. Stress Test (Find Breaking Point)

Gradually increases load until server fails:

```bash
k6 run load_test/k6_stress_test.js
```

---

## Monitoring During Tests

### 1. Rails Logs

Monitor response times and errors:

```bash
# Watch for slow queries
tail -f log/development.log | grep -E "(Completed|Slow|Error)"

# Or use grep for specific patterns
tail -f log/development.log | grep "SELECT"
```

### 2. Database Queries

Enable query logging in `config/environments/development.rb`:

```ruby
config.active_record.logger = Logger.new(STDOUT)
config.active_record.verbose_query_logs = true
```

### 3. System Resources

```bash
# CPU and Memory usage
top -pid $(pgrep -f "puma")

# Or use htop
htop

# Database connections
sqlite3 storage/development.sqlite3 "SELECT COUNT(*) FROM sqlite_master WHERE type='table';"

# Process monitoring
ps aux | grep -E "(puma|rails)"
```

### 4. Database Size and Performance

```bash
# Database size
du -sh storage/development.sqlite3

# Check database locks (SQLite)
sqlite3 storage/development.sqlite3 "PRAGMA busy_timeout = 5000;"
```

### 5. Puma Threads and Workers

Add to `config/puma.rb` for monitoring:

```ruby
# Puma stats endpoint (add to routes)
get '/puma/stats' => proc { |env|
  require 'json'
  stats = Puma.stats
  [200, {}, [stats.to_json]]
}
```

Then monitor:
```bash
curl http://localhost:3000/puma/stats | jq
```

---

## Analyzing Results

### k6 Metrics

k6 provides detailed metrics:

- **http_req_duration**: Response time (p50, p95, p99)
- **http_req_failed**: Failed requests percentage
- **iterations**: Total requests completed
- **vus**: Virtual users (concurrent)

**Key Metrics to Watch:**

1. **Response Time (p95)**
   - Target: <200ms for feed page
   - Target: <100ms for post view
   - Alert if >500ms

2. **Error Rate**
   - Target: <1%
   - Alert if >5%

3. **Request Rate**
   - Target: 33 RPS sustained
   - Peak: 100+ RPS

### Interpreting Results

**Good Performance:**
```
✓ p95 response time < 200ms
✓ Error rate < 1%
✓ Stable memory usage
✓ No database connection pool exhaustion
```

**Performance Issues:**
```
✗ p95 response time > 500ms → Query optimization needed
✗ Error rate > 5% → Connection pool or memory issues
✗ Memory continuously increasing → Memory leak
✗ Database locks → SQLite limitations or query issues
```

### Common Issues and Solutions

| Issue | Symptoms | Solution |
|-------|----------|----------|
| **Slow feed queries** | p95 > 500ms on feed page | Add composite index, optimize query |
| **Connection pool exhaustion** | 500 errors, "connection pool timeout" | Increase pool size in database.yml |
| **SQLite locks** | "database is locked" errors | Migrate to PostgreSQL |
| **Memory leak** | Memory grows continuously | Check for N+1 queries, add includes() |
| **High CPU** | CPU > 80% sustained | Check for inefficient queries |

---

## Performance Targets

Based on our analysis, here are the targets:

### Response Times (p95)

| Endpoint | Target | Acceptable | Critical |
|----------|--------|------------|----------|
| Feed Page | <100ms | <200ms | >500ms |
| Post View | <50ms | <100ms | >200ms |
| Post Create | <100ms | <200ms | >500ms |
| User Profile | <50ms | <100ms | >200ms |

### Throughput

- **Sustained RPS**: 33 RPS (target from analysis)
- **Peak RPS**: 100 RPS
- **Concurrent Users**: 1,000 users

### Error Rates

- **Target**: <0.1% errors
- **Acceptable**: <1% errors
- **Critical**: >5% errors

### Resource Usage

- **CPU**: <70% average
- **Memory**: Stable (no continuous growth)
- **Database Connections**: <80% of pool size

---

## Test Scenarios

### Scenario 1: Baseline Performance

**Goal**: Establish baseline metrics

```bash
k6 run load_test/k6_baseline.js
```

**Expected Results:**
- Feed page: <200ms p95
- All endpoints responding
- No errors

### Scenario 2: Realistic Load

**Goal**: Test under expected production load

```bash
k6 run load_test/k6_comprehensive.js
```

**Load:**
- 50 concurrent users
- 33 RPS average
- 5-minute duration

**Expected Results:**
- Sustained performance
- Error rate <1%
- Stable memory

### Scenario 3: Stress Test

**Goal**: Find breaking point

```bash
k6 run load_test/k6_stress_test.js
```

**Load:**
- Ramp from 10 to 200 concurrent users
- 10-minute duration

**Watch For:**
- When errors start appearing
- Response time degradation
- Resource exhaustion

### Scenario 4: Feed Query Focus

**Goal**: Test the critical feed query under load

```bash
k6 run load_test/k6_feed_test.js
```

**Load:**
- 100 concurrent users
- All hitting feed page
- 2-minute duration

**Expected Issues:**
- Slow feed queries (150-600ms)
- Large IN clauses
- Database connection pressure

---

## Best Practices

1. **Start Small**: Begin with low load and gradually increase
2. **Monitor Everything**: Watch logs, metrics, and system resources
3. **Test Realistic Scenarios**: Use actual user behavior patterns
4. **Run Multiple Times**: Performance can vary, run 3-5 times
5. **Compare Results**: Track improvements over time
6. **Test Peak Hours**: Simulate 3x average traffic
7. **Warm Up**: Let server run for 30 seconds before testing
8. **Clean State**: Reset database between major test runs

---

## Next Steps

After identifying bottlenecks:

1. **Implement Optimizations** (from PERFORMANCE_ANALYSIS.md)
   - Fix N+1 queries
   - Add composite indexes
   - Increase connection pool
   - Optimize feed queries

2. **Re-run Tests** to verify improvements

3. **Document Results** and track over time

4. **Set Up Continuous Load Testing** (optional)
   - Run nightly tests
   - Track performance regressions
   - Alert on degradation

---

## Troubleshooting

### Tests Fail Immediately

- **Check server is running**: `curl http://localhost:3000/up`
- **Check port**: Default is 3000, adjust in scripts
- **Check firewall**: Ensure port is accessible

### All Requests Timeout

- **Connection pool exhausted**: Increase pool size
- **Database locked**: Check for long-running queries
- **Memory full**: Check system memory

### Inconsistent Results

- **Background processes**: Close other apps
- **Database state**: Reset database between runs
- **System load**: Run on dedicated machine

---

For more details, see the individual test scripts in `load_test/` directory.

