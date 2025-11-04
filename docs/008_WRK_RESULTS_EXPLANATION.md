# Understanding wrk Load Test Results

## Your Test Command

```bash
wrk -t8 -c250 -d30s -s load_test/wrk_feed.lua http://localhost:3000/
```

**Parameters:**
- `-t8`: 8 threads (worker threads)
- `-c250`: 250 concurrent connections (simulating 250 simultaneous users)
- `-d30s`: Duration of 30 seconds
- `-s load_test/wrk_feed.lua`: Custom Lua script (handles login + authenticated feeds)
- `http://localhost:3000/`: Target URL

## Your Results Breakdown

```
Running 30s test @ http://localhost:3000/
  8 threads and 250 connections
```

**Test Configuration:**
- 8 worker threads handling requests
- 250 concurrent connections (simulating 250 simultaneous users)
- 30 seconds test duration

### Thread Stats

```
Thread Stats   Avg      Stdev     Max   +/- Stdev
    Latency     1.10s   552.89ms   1.97s    56.36%
    Req/Sec     5.70      3.97    30.00     71.28%
```

**Latency (Response Time):**
- **Avg: 1.10s** - Average response time per request
- **Stdev: 552.89ms** - High variation (very inconsistent)
- **Max: 1.97s** - Slowest request
- **+/- Stdev: 56.36%** - Only 56% of requests within 1 standard deviation (very inconsistent)

**Interpretation:**
- ⚠️ **Very high latency** - 1.1 seconds average is poor
- ⚠️ **High variation** - Only 56% within range (inconsistent performance)
- 🔴 **Maximum latency of 1.97s** - Some requests taking almost 2 seconds
- **Comparison to previous test**: 523ms → 1,100ms (2x worse!)

**Req/Sec (Requests Per Second per Thread):**
- **Avg: 5.70** - Average requests per second per thread
- **Stdev: 3.97** - Very high variation
- **Max: 30.00** - Peak requests per second per thread
- **+/- Stdev: 71.28%** - 71% within range (better than latency, but still high variation)

**Interpretation:**
- ⚠️ **Very low throughput** - Only 5.7 req/sec per thread
- ⚠️ **High variation** - Inconsistent performance between threads
- **Comparison**: Previous test had 30.71 req/sec per thread (5x better!)

### Overall Statistics

```
832 requests in 30.11s, 32.39MB read
Requests/sec:     27.64
Transfer/sec:      1.08MB

Socket errors: connect 0, read 0, write 0, timeout 777
```

**Total Requests:**
- **832 requests** completed in 30.11 seconds
- **32.39 MB** of data transferred
- **Comparison**: Previous test had 8,217 requests (10x more!)

**Throughput:**
- **27.64 requests/second** - Overall application throughput
- **1.08 MB/second** - Data transfer rate
- **Comparison**: Previous test had 273 RPS (10x better!)

**Calculation:**
- 8 threads × 5.70 avg req/sec = ~45.6 req/sec theoretical max
- Actual: 27.64 req/sec = ~61% efficiency (very poor!)

### Critical Issue: Socket Timeouts

```
Socket errors: connect 0, read 0, write 0, timeout 777
```

**🔴 CRITICAL: 777 Socket Timeouts!**

This means:
- **777 requests timed out** - Server didn't respond in time
- Requests were sent but never got a response
- Server is **overwhelmed** and can't handle the load

**Why Timeouts Occur:**
1. **Too many concurrent connections** (250 is very high)
2. **Database connection pool exhausted** (default 5 connections)
3. **SQLite locks** (single writer limitation)
4. **Server overloaded** - Can't process requests fast enough
5. **wrk_feed.lua complexity** - Login + feed requests take longer

## Performance Analysis

### Why This Test Performed Poorly

**1. Too Many Concurrent Connections:**
- 250 concurrent connections is **very aggressive**
- Previous test: 150 connections → 273 RPS
- This test: 250 connections → 27.64 RPS
- **Diminishing returns** - More connections = worse performance

**2. wrk_feed.lua Script Complexity:**
- Each request does: Login → Extract cookie → Feed request
- More complex than simple GET requests
- Cookie handling adds overhead
- Multiple requests per "session"

**3. Database Bottleneck:**
- SQLite with 250 concurrent connections
- Single writer limitation
- Connection pool likely exhausted (default: 5 connections)
- Database locks causing timeouts

**4. Server Resource Limits:**
- Puma default: 5 threads
- 250 connections ÷ 5 threads = 50 connections queued per thread
- Requests waiting in queue → timeouts

### Comparison to Previous Test

| Metric | Previous (150 conn) | This Test (250 conn) | Difference |
|--------|---------------------|---------------------|------------|
| **RPS** | 273.05 | 27.64 | **10x worse** |
| **Latency** | 523ms | 1,100ms | **2x worse** |
| **Requests** | 8,217 | 832 | **10x fewer** |
| **Timeouts** | 0 | **777** | **Critical** |
| **Efficiency** | 74% | 61% | **13% worse** |

### What This Tells Us

**🔴 Application is Overwhelmed:**
- 250 concurrent connections is beyond capacity
- Server can't handle this load
- Timeouts indicate resource exhaustion

**Root Causes:**
1. **Connection Pool Exhaustion** - Default 5 connections insufficient
2. **SQLite Limitations** - Single writer, can't handle 250 concurrent queries
3. **Puma Thread Pool** - Default 5 threads insufficient
4. **Database Locks** - SQLite struggling with concurrent writes

## Recommendations

### Immediate Fixes

1. **Increase Connection Pool:**
   ```ruby
   # config/database.yml
   pool: 25  # Increase from default 5
   ```

2. **Increase Puma Threads:**
   ```ruby
   # config/puma.rb
   threads 10, 20  # Increase from default 5
   ```

3. **Test with Realistic Load:**
   ```bash
   # Start with lower load
   wrk -t4 -c50 -d30s -s load_test/wrk_feed.lua http://localhost:3000/

   # Gradually increase
   wrk -t8 -c100 -d30s -s load_test/wrk_feed.lua http://localhost:3000/
   ```

### Better Testing Approach

**For wrk (Simple Baseline):**
```bash
# Test public feed (no authentication complexity)
wrk -t8 -c250 -d30s http://localhost:3000/
```

**For Comprehensive Testing (k6):**
```bash
# k6 handles authentication and sessions better
k6 run load_test/k6_comprehensive.js
```

### Understanding the Results

**Good Performance Indicators:**
- ✅ RPS > 100
- ✅ Latency < 500ms
- ✅ No timeouts
- ✅ >80% efficiency

**Poor Performance Indicators (Your Results):**
- 🔴 RPS < 50
- 🔴 Latency > 1s
- 🔴 **777 timeouts** (critical!)
- 🔴 <70% efficiency

## What Happened

**Your Test Scenario:**
1. 250 concurrent connections start
2. Each does: Login → Get cookie → Request feed
3. Server receives 250 login requests simultaneously
4. Database connection pool (5) exhausted
5. Requests queue up waiting for database
6. wrk timeout (default 2s) expires
7. 777 requests timeout before getting response
8. Only 832 requests complete successfully
9. Throughput drops to 27.64 RPS

**Why Previous Test Was Better:**
- Lower concurrency (150 vs 250)
- Simpler requests (public feed, no login)
- Less database load
- No cookie handling overhead

## Action Items

1. **Increase Connection Pool** (Priority 1)
   ```ruby
   # config/database.yml - development
   pool: 25
   ```

2. **Increase Puma Threads** (Priority 1)
   ```ruby
   # config/puma.rb
   threads 10, 20
   ```

3. **Test Gradual Load Increase:**
   - Start: 50 connections
   - Then: 100 connections
   - Then: 150 connections
   - Find breaking point

4. **Use k6 for Realistic Testing:**
   - Better session handling
   - More realistic user behavior
   - Better error reporting

5. **Consider PostgreSQL:**
   - SQLite has single writer limitation
   - PostgreSQL handles concurrent connections better

## Conclusion

**Your Results Show:**
- 🔴 **Application is overwhelmed** at 250 concurrent connections
- 🔴 **777 timeouts** indicate resource exhaustion
- 🔴 **10x worse performance** than previous test
- ⚠️ **Server configuration needs tuning** (connection pool, threads)

**Expected Capacity:**
- **Current**: ~100-150 concurrent connections max
- **With optimizations**: 200-300 concurrent connections
- **Target**: Handle 150 concurrent users (from performance analysis)

**Next Steps:**
1. Increase connection pool and threads
2. Re-test with lower load first
3. Gradually increase to find limit
4. Use k6 for comprehensive testing

See `docs/PERFORMANCE_ANALYSIS.md` for optimization recommendations.