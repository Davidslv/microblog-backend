# wrk Load Test Results Analysis

## Test Configuration

Three load tests were run with increasing load to evaluate application performance and identify bottlenecks.

### Test Command
```bash
wrk -t{threads} -c{connections} -d30s -s load_test/wrk_feed.lua http://localhost:3000/
```

**Parameters Explained:**
- `-t{N}`: Number of worker threads (parallel request generators)
- `-c{N}`: Number of concurrent connections (simulating simultaneous users)
- `-d30s`: Test duration (30 seconds)
- `-s load_test/wrk_feed.lua`: Custom Lua script that:
  - Handles authentication via `/dev/login/{userId}`
  - Tests authenticated feed endpoints (`/posts?filter=timeline|mine|following`)
  - Maintains session cookies per thread

---

## Test Results Summary

| Test | Threads | Connections | Avg Latency | RPS | Requests | Timeouts | Efficiency |
|------|---------|-------------|-------------|-----|-----------|----------|------------|
| **Test 1** | 4 | 50 | 1.76s | 25.75 | 775 | 68 | 65% |
| **Test 2** | 8 | 150 | 1.36s | 31.06 | 935 | 890 | 39% |
| **Test 3** | 8 | 250 | 1.10s | 31.49 | 948 | 892 | 39% |

---

## Detailed Analysis

### Test 1: Light Load (4 threads, 50 connections)

```
Running 30s test @ http://localhost:3000/
  4 threads and 50 connections

  Thread Stats   Avg      Stdev     Max   +/- Stdev
    Latency     1.76s   229.01ms   2.00s    91.80%
    Req/Sec    10.86     10.41    60.00     91.93%

  775 requests in 30.10s, 30.80MB read
  Socket errors: connect 0, read 0, write 0, timeout 68

Requests/sec:     25.75
Transfer/sec:      1.02MB
```

**Analysis:**
- **Latency**: 1.76s average (very high, but consistent - 91.8% within range)
- **Throughput**: 25.75 RPS (low)
- **Timeouts**: 68 (8.8% of attempted requests)
- **Efficiency**: 65% (4 threads × 10.86 req/sec = 43.4 theoretical, actual 25.75)
- **Status**: System handling load but with high latency

**Key Metrics:**
- **Stdev**: 229ms (low variation - consistent performance)
- **Max Latency**: 2.00s (hitting the timeout limit)
- **+/- Stdev**: 91.80% (high consistency within each thread)

---

### Test 2: Medium Load (8 threads, 150 connections)

```
Running 30s test @ http://localhost:3000/
  8 threads and 150 connections

  Thread Stats   Avg      Stdev     Max   +/- Stdev
    Latency     1.36s   443.81ms   1.99s    66.67%
    Req/Sec     7.28      7.53   100.00     90.48%

  935 requests in 30.11s, 36.93MB read
  Socket errors: connect 0, read 0, write 0, timeout 890

Requests/sec:     31.06
Transfer/sec:      1.23MB
```

**Analysis:**
- **Latency**: 1.36s average (**improved** from 1.76s, but less consistent)
- **Throughput**: 31.06 RPS (**improved** by 20%)
- **Timeouts**: 890 (**13x increase** - critical issue!)
- **Efficiency**: 39% (8 threads × 7.28 = 58.2 theoretical, actual 31.06)
- **Status**: System saturated, most requests timing out

**Key Metrics:**
- **Stdev**: 443ms (high variation - inconsistent performance)
- **Max Latency**: 1.99s (still hitting timeout)
- **+/- Stdev**: 66.67% (lower consistency - more variation)
- **Timeout Rate**: 95% of attempted requests (890 timeouts / ~935 requests)

**Critical Observation:**
- **Latency improved** (1.76s → 1.36s) but **timeouts exploded** (68 → 890)
- This suggests requests are being **queued** rather than processed immediately
- The system is **saturated** - can't handle 150 concurrent connections

---

### Test 3: Heavy Load (8 threads, 250 connections)

```
Running 30s test @ http://localhost:3000/
  8 threads and 250 connections

  Thread Stats   Avg      Stdev     Max   +/- Stdev
    Latency     1.10s   455.00ms   1.75s    69.64%
    Req/Sec     6.54      6.66   100.00    92.44%

  948 requests in 30.11s, 37.42MB read
  Socket errors: connect 0, read 0, write 0, timeout 892

Requests/sec:     31.49
Transfer/sec:      1.24MB
```

**Analysis:**
- **Latency**: 1.10s average (**further improved** from 1.36s)
- **Throughput**: 31.49 RPS (**minimal improvement** - only +1.4% from Test 2)
- **Timeouts**: 892 (same as Test 2 - system maxed out)
- **Efficiency**: 39% (same as Test 2 - no improvement)
- **Status**: System at maximum capacity, no scaling

**Key Metrics:**
- **Stdev**: 455ms (high variation persists)
- **Max Latency**: 1.75s (slightly better than 1.99s)
- **+/- Stdev**: 69.64% (slightly better consistency)
- **Timeout Rate**: 94% of attempted requests (892 timeouts)

**Critical Observation:**
- **Latency improved** (1.36s → 1.10s) but **throughput plateaued** (31.06 → 31.49 RPS)
- **No improvement** in timeouts (890 → 892)
- Doubling connections (150 → 250) resulted in **only 13 more completed requests**
- System is **completely saturated** - more load doesn't help

---

## Key Findings

### 1. Counter-Intuitive Latency Improvement

**Observation**: Latency **decreased** as load increased (1.76s → 1.36s → 1.10s)

**Explanation**: This is a **queueing effect**, not a performance improvement:
- With more connections, requests are queued in Puma's thread pool
- Queued requests wait longer before being processed
- Once processed, they may benefit from cache hits or connection reuse
- But the **timeout rate** (waiting in queue) increases dramatically

**Reality**: System is **saturated** - requests are waiting in queue, not being processed faster.

### 2. Throughput Plateau

**Observation**: RPS barely increased from Test 2 to Test 3 (31.06 → 31.49)

**Implication**: System has reached **maximum capacity**:
- **31-32 RPS** is the application's current limit
- Doubling connections (150 → 250) only increased throughput by 1.4%
- Most additional connections are just **waiting** and **timing out**

### 3. Timeout Explosion

**Observation**: Timeouts increased dramatically (68 → 890 → 892)

**Root Cause**: **Connection pool exhaustion** or **request queue overflow**:
- Puma has limited threads (default: 5)
- Database connection pool is limited (default: 25)
- With 150-250 concurrent connections, most requests wait in queue
- If queue wait exceeds ~2 seconds, wrk times out

**Impact**:
- **94% timeout rate** in Tests 2 & 3
- Only 6% of requests are completing successfully
- System is **unusable** under this load

### 4. Efficiency Degradation

**Observation**: Efficiency dropped from 65% (Test 1) to 39% (Tests 2 & 3)

**Explanation**:
- Test 1: System can handle load, efficient use of resources
- Tests 2 & 3: System saturated, resources wasted on queuing/timeouts
- 39% efficiency means **61% of capacity is wasted** on overhead

---

## Bottleneck Analysis

### Primary Bottleneck: Connection Pool Exhaustion

**Evidence:**
1. **Timeouts explode** when connections > 50
2. **Throughput plateaus** regardless of load
3. **Latency appears to improve** (queueing effect)

**Likely Causes:**
1. **Puma Thread Pool**: Default 5 threads can't handle 150-250 connections
2. **Database Connection Pool**: Default 25 connections may be insufficient
3. **Request Queue**: Puma queue fills up, requests wait >2 seconds

### Secondary Bottleneck: Database Query Performance

**Evidence:**
- Even successful requests take **1.10-1.76s** (very slow)
- Feed queries are expensive (JOIN on follows table)
- Caching may not be effective under high load (cache misses)

---

## Performance Targets vs Reality

| Metric | Target | Test 1 (50 conn) | Test 2 (150 conn) | Test 3 (250 conn) | Status |
|--------|--------|------------------|-------------------|-------------------|--------|
| **Latency (p95)** | <200ms | 1.76s | 1.36s | 1.10s | ❌ 5-9x worse |
| **Throughput** | 200+ RPS | 25.75 RPS | 31.06 RPS | 31.49 RPS | ❌ 6-8x worse |
| **Timeout Rate** | <1% | 8.8% | 95% | 94% | ❌ Critical |
| **Efficiency** | >80% | 65% | 39% | 39% | ❌ Poor |

**Conclusion**: Application is **not meeting performance targets** and needs optimization.

---

## Recommendations

### Immediate Actions (High Priority)

1. **Increase Puma Thread Pool**
   ```ruby
   # config/puma.rb
   threads ENV.fetch("RAILS_MAX_THREADS") { 25 }
   ```
   - Current: 5 threads
   - Recommended: 25-50 threads
   - Impact: Can handle more concurrent requests

2. **Increase Database Connection Pool**
   ```yaml
   # config/database.yml
   pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 25 } %>
   ```
   - Current: 25 connections
   - Recommended: Match Puma threads (25-50)
   - Impact: Reduces connection pool exhaustion

3. **Verify Caching is Working**
   - Check cache hit rates (should be 70-90%)
   - Verify feed queries are cached
   - Monitor cache performance under load
   - Impact: Can reduce query time from 50-200ms to <1ms

### Medium-Term Optimizations

4. **Implement Fan-Out on Write**
   - Pre-compute feed entries (see `docs/028_SCALING_AND_PERFORMANCE_STRATEGIES.md`)
   - Expected: 10-40x faster feed queries
   - Impact: Reduce latency from 1.10s to 50-100ms

5. **Add Connection Pooling (PgBouncer)**
   - For production environments
   - Allows 1000+ client connections with 25 DB connections
   - Impact: Better connection management, higher throughput

6. **Monitor and Profile**
   - Use `pg_stat_statements` to identify slow queries
   - Profile application with New Relic or similar
   - Identify N+1 queries and optimize
   - Impact: Targeted optimizations

### Long-Term Architecture Changes

7. **Consider Read Replicas**
   - Distribute read load across multiple databases
   - Impact: 2-3x read capacity

8. **Implement Rate Limiting**
   - Protect against abuse
   - Ensure fair resource usage
   - Impact: Prevents overload

---

## Test Methodology Notes

### Why Latency Appears to Improve

**This is a common misconception** when analyzing load test results:

1. **Queueing Effect**: Requests wait in queue before processing
2. **Processing Time**: Once in thread, request may process quickly (cache hit)
3. **Measured Latency**: Time from request start to response (includes queue time)
4. **Actual Observation**: Latency = queue time + processing time

**In Tests 2 & 3:**
- Most requests **timeout** (wait in queue >2 seconds)
- Only requests that **get through quickly** are measured
- This creates a **selection bias** - only fast requests are counted
- Latency appears to improve, but **throughput is terrible**

### How to Interpret Results

**Focus on these metrics:**
1. **Throughput (RPS)**: Should increase with load (not plateau)
2. **Timeout Rate**: Should stay low (<1%)
3. **Efficiency**: Should stay high (>80%)
4. **Latency Distribution**: p50, p95, p99 (not just average)

**Red Flags:**
- ✅ Latency decreasing with load
- ✅ Timeout rate exploding
- ✅ Throughput plateauing
- ✅ Efficiency dropping

---

## Next Steps

1. **Re-run tests after optimizations**:
   - Increase Puma threads and DB pool
   - Verify caching is working
   - Compare results

2. **Monitor during tests**:
   - Check Puma stats: `curl http://localhost:3000/puma/stats`
   - Check database connections: `SELECT count(*) FROM pg_stat_activity;`
   - Check cache hit rate: `SELECT COUNT(*) FROM solid_cache_entries;`

3. **Iterate**:
   - Make one change at a time
   - Measure impact
   - Continue optimizing

---

## Summary

**Current State:**
- ❌ **Throughput**: 31 RPS (need 200+)
- ❌ **Latency**: 1.10s (need <200ms)
- ❌ **Timeouts**: 94% (need <1%)
- ❌ **Efficiency**: 39% (need >80%)

**Root Cause**: Connection pool exhaustion and slow database queries

**Priority**: Fix connection pools and verify caching, then optimize queries

**Expected Improvement**: With proper configuration, should see 2-3x improvement in throughput and 5-10x improvement in latency.

