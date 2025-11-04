# wrk Test Results After Increasing Pool and Threads

## Test Configuration

```bash
wrk -t8 -c250 -d30s -s load_test/wrk_feed.lua http://localhost:3000/
```

**Configuration:**
- 8 threads, 250 concurrent connections
- PostgreSQL database
- **Database pool: 25 connections** (increased from 10)
- **Puma threads: 25** (increased from 10)

## Test Results

```
Running 30s test @ http://localhost:3000/
  8 threads and 250 connections

  Thread Stats   Avg      Stdev     Max   +/- Stdev
    Latency     1.18s   441.06ms   1.99s    69.23%
    Req/Sec     6.32      6.34    60.00     91.49%

  830 requests in 30.03s, 32.52MB read
  Socket errors: connect 0, read 0, write 0, timeout 791
  Non-2xx or 3xx responses: 4

Requests/sec:     27.64
Transfer/sec:      1.08MB
```

## Comparison: Before vs After Tuning

| Metric | Before (pool=10, threads=10) | After (pool=25, threads=25) | Change |
|--------|------------------------------|----------------------------|--------|
| **RPS** | 28.30 | 27.64 | -0.66 (-2.3%) |
| **Latency** | 1.06s | 1.18s | +0.12s (+11.3%) |
| **Requests** | 852 | 830 | -22 (-2.6%) |
| **Timeouts** | 795 | 791 | -4 (-0.5%) |
| **Errors** | 0 | 4 | +4 |
| **Efficiency** | 63% | 62% | -1% |

## Analysis

### Unexpected Results

**⚠️ Performance Actually Got Slightly Worse:**
- **RPS decreased** by 2.3% (28.30 → 27.64)
- **Latency increased** by 11.3% (1.06s → 1.18s)
- **Timeouts barely improved** (795 → 791, only 4 fewer)
- **New errors** (4 non-2xx/3xx responses)

### Why This Happened

**1. Thread Contention (Ruby GVL)**
- Ruby's Global VM Lock (GVL) limits true parallelism
- More threads = more contention for the GVL
- **25 threads may be too many** for Ruby's concurrency model
- Diminishing returns after ~10-15 threads

**2. Context Switching Overhead**
- 25 threads competing for CPU
- More context switching between threads
- Overhead of managing more threads

**3. Database Connection Overhead**
- 25 connections maintained even when idle
- Connection management overhead
- PostgreSQL may be thrashing with connection management

**4. Memory Pressure**
- More threads = more memory per thread
- More connections = more memory per connection
- May be hitting system limits

### The Real Issue

**250 Concurrent Connections is Still Too High:**
- Even with 25 pool/threads, 250 concurrent is 10x the capacity
- Each request needs: Login → Feed query → Multiple DB operations
- **Request complexity** is the issue, not just connection count

## Recommendations

### Optimal Configuration

**For 250 Concurrent Connections:**
- **Pool**: 15-20 (not 25)
- **Threads**: 15-20 (not 25)
- **Rationale**: Balance between capacity and overhead

**For Realistic Load (100-150 concurrent):**
- **Pool**: 20-25 ✅
- **Threads**: 20-25 ✅
- **Should perform well**

### Test at Lower Load First

**Gradual Load Testing:**
```bash
# Test at 50 concurrent
wrk -t4 -c50 -d30s -s load_test/wrk_feed.lua http://localhost:3000/

# Test at 100 concurrent
wrk -t8 -c100 -d30s -s load_test/wrk_feed.lua http://localhost:3000/

# Test at 150 concurrent
wrk -t8 -c150 -d30s -s load_test/wrk_feed.lua http://localhost:3000/

# Then try 200, 250
```

**Find the sweet spot** where performance is optimal.

### Alternative: Reduce Connection Pool

**Try 15-20:**
```ruby
# config/database.yml
pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 20 } %>

# config/puma.rb
threads_count = ENV.fetch("RAILS_MAX_THREADS", 20)
```

**Why:**
- Less overhead than 25
- Still 2x the original 10
- Better balance for Ruby's GVL

### Check System Resources

**Monitor During Tests:**
```bash
# CPU usage
top -pid $(pgrep -f "puma")

# Memory usage
ps aux | grep puma

# PostgreSQL connections
psql -c "SELECT count(*) FROM pg_stat_activity;"
```

**Possible Issues:**
- CPU bottleneck (all cores maxed?)
- Memory pressure (swap being used?)
- PostgreSQL connection limits

## Expected Performance

**At 150 Concurrent (Realistic Load):**
- **RPS**: Expected 80-150
- **Latency**: Expected <400ms
- **Timeouts**: Expected <50
- **Efficiency**: Expected >75%

**At 250 Concurrent (Extreme Load):**
- **RPS**: Expected 50-100 (diminishing returns)
- **Latency**: Expected 500-800ms
- **Timeouts**: Expected 200-400 (still high, but better)
- **Efficiency**: Expected 60-70%

## Conclusion

**Key Insights:**
1. **More threads/connections ≠ better performance** at extreme loads
2. **Ruby GVL limits** true parallelism
3. **250 concurrent is still extreme** for a single Rails server
4. **Sweet spot** likely 15-20 threads/pool for most workloads
5. **Need to test at realistic loads** (100-150 concurrent)

**Next Steps:**
1. Test at lower concurrent loads (50, 100, 150)
2. Find optimal pool/threads for your workload
3. Consider horizontal scaling for 250+ concurrent
4. Monitor system resources during tests

**The Real Solution:**
- For 250+ concurrent: **Horizontal scaling** (multiple servers)
- For <150 concurrent: **Current config should work well**
- Need to test at realistic loads to verify

See `docs/WRK_RESULTS_POSTGRESQL.md` for previous analysis.

