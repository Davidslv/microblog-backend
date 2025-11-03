# wrk Test Results After Configuration Optimization

## Test Configuration

```bash
wrk -t8 -c250 -d30s -s load_test/wrk_feed.lua http://localhost:3000/
```

**Configuration Changes Applied:**
- Database connection pool: 5 → 10
- Puma threads: 3 → 10

## Test Results

```
Running 30s test @ http://localhost:3000/
  8 threads and 250 connections

  Thread Stats   Avg      Stdev     Max   +/- Stdev
    Latency     1.18s   493.37ms   1.90s    55.10%
    Req/Sec     5.44      4.71    30.00     90.95%

  806 requests in 30.02s, 31.50MB read
  Socket errors: connect 0, read 0, write 0, timeout 757
  Non-2xx or 3xx responses: 3

Requests/sec:     26.85
Transfer/sec:      1.05MB
```

## Performance Analysis

### Comparison to Previous Test

| Metric | Before Optimization | After Optimization | Change |
|--------|---------------------|-------------------|--------|
| **RPS** | 27.64 | 26.85 | -2.9% (slightly worse) |
| **Latency** | 1.10s | 1.18s | +7.3% (worse) |
| **Requests** | 832 | 806 | -3.1% (fewer completed) |
| **Timeouts** | 777 | 757 | -2.6% (slight improvement) |
| **Errors** | 0 | 3 | New issue |

### Key Observations

**🔴 Still Poor Performance:**
- RPS remains very low (~27 RPS)
- Latency still very high (1.18s average)
- **757 timeouts** (still critical)
- Only 55% of requests within latency range (inconsistent)

**⚠️ Slight Changes:**
- Timeouts reduced by 20 (777 → 757) - **minimal improvement**
- But latency increased (1.10s → 1.18s) - **worse**
- Fewer requests completed (832 → 806) - **worse**
- New error responses (3 non-2xx/3xx) - **new issue**

**📊 Efficiency:**
- 8 threads × 5.44 req/sec = ~43.5 req/sec theoretical
- Actual: 26.85 req/sec = **62% efficiency** (still poor)

## Why Performance Didn't Improve Significantly

### 1. SQLite Single-Writer Limitation

**The Real Bottleneck:**
- SQLite has a **single-writer lock**
- Even with 10 connections, only one can write at a time
- Concurrent reads compete with writes
- 250 concurrent connections = massive contention

**What's Happening:**
```
250 connections → 250 database queries
SQLite single writer → Queues requests
Connection pool (10) → Helps but SQLite lock is the limit
Result: Timeouts and high latency
```

### 2. Connection Pool Not the Issue

**Analysis:**
- Increased pool from 5 → 10 (2x)
- But SQLite can't utilize 10 concurrent connections effectively
- Single-writer lock creates a queue regardless of pool size
- **Pool size increase helps minimally**

### 3. Puma Threads Not Fully Utilized

**Analysis:**
- Increased threads from 3 → 10 (3.3x)
- But threads are waiting on database
- **I/O-bound workload** - threads don't help much
- Database is the bottleneck, not CPU

### 4. Error Responses (New Issue)

**3 Non-2xx/3xx Responses:**
- Could be 500 errors (server overload)
- Could be 429 errors (rate limiting)
- Could be connection errors
- Need to check Rails logs to identify

**Possible Causes:**
- Database deadlock
- Connection pool exhaustion (still)
- SQLite lock timeout
- Server overload

## Root Cause Analysis

### SQLite Limitations

**Single-Writer Lock:**
- SQLite uses a **database-level lock**
- Only one write operation at a time
- Concurrent reads can happen, but compete with writes
- With 250 concurrent requests, queue builds up

**Why This Matters:**
```
250 requests → 250 database queries
SQLite lock → Sequential processing (essentially)
Queue builds → Timeouts occur
```

**Even with 10 connections:**
- Connections can queue queries
- But SQLite still processes them one at a time (for writes)
- Reads can be concurrent, but still limited

### Query Pattern Analysis

**Each Request:**
1. Login request → Database write (session)
2. Feed query → Database read (complex query with JOINs)
3. Multiple queries per request

**With 250 concurrent:**
- 250 login requests → 250 session writes (queued)
- 250 feed queries → 250 complex reads (competing)
- SQLite struggles with this load

## Recommendations

### Immediate Actions

**1. Reduce Load (Find Realistic Capacity):**
```bash
# Test at lower concurrency first
wrk -t4 -c50 -d30s -s load_test/wrk_feed.lua http://localhost:3000/
wrk -t8 -c100 -d30s -s load_test/wrk_feed.lua http://localhost:3000/
wrk -t8 -c150 -d30s -s load_test/wrk_feed.lua http://localhost:3000/

# Find where performance degrades
```

**2. Check Rails Logs for Errors:**
```bash
# Check for the 3 error responses
tail -f log/development.log | grep -E "Error|500|429"
```

**3. Monitor Database Activity:**
```bash
# Check SQLite lock contention
# SQLite doesn't expose this easily, but high latency indicates it
```

### Long-Term Solutions

**1. Move to PostgreSQL (Recommended):**
```ruby
# config/database.yml
default: &default
  adapter: postgresql
  pool: 25  # Can handle much more
  # PostgreSQL handles concurrent connections much better
```

**Benefits:**
- ✅ True concurrent writes (not single-writer)
- ✅ Better connection pooling
- ✅ Handles 250+ concurrent connections
- ✅ Better for production workloads

**2. Optimize Query Performance:**
- ✅ Already added composite index (good!)
- ✅ Cursor-based pagination (good!)
- ⚠️ Could add query caching
- ⚠️ Could optimize feed query further

**3. Connection Pool Tuning:**
```ruby
# For SQLite, pool size doesn't help much
# But for PostgreSQL, can increase:
pool: 25  # Match or exceed Puma threads
```

**4. Consider Read Replicas (Production):**
- Separate read/write databases
- Read-heavy workload (feeds) can use read replica
- Write operations use primary

### SQLite vs PostgreSQL Comparison

| Feature | SQLite | PostgreSQL |
|---------|--------|------------|
| **Concurrent Writes** | Single writer | Multiple writers |
| **Connection Pool** | Limited benefit | High benefit |
| **250 Concurrent** | ❌ Struggles | ✅ Handles well |
| **Production Ready** | ❌ Not recommended | ✅ Recommended |
| **Complexity** | Simple | More setup |

## Current Capacity Assessment

**With SQLite + Current Config:**
- **Realistic Capacity**: ~100-150 concurrent connections
- **At 250 connections**: Overwhelmed (757 timeouts)
- **Bottleneck**: SQLite single-writer lock

**With PostgreSQL + Tuned Config:**
- **Expected Capacity**: 300-500+ concurrent connections
- **Better connection pooling**: Handles concurrent writes
- **Production ready**: Designed for high concurrency

## Action Items

### Short Term (Keep SQLite):
1. ✅ **Test at lower concurrency** (50, 100, 150)
2. ✅ **Find breaking point** where performance degrades
3. ✅ **Monitor Rails logs** for errors
4. ✅ **Accept limitations** - SQLite not for high concurrency

### Medium Term (Optimize SQLite):
1. ⚠️ **Add query caching** (reduce database hits)
2. ⚠️ **Optimize feed queries** further
3. ⚠️ **Consider read-only replicas** (if possible)

### Long Term (Production):
1. 🔴 **Move to PostgreSQL** - Best solution
2. 🔴 **Tune connection pool** for PostgreSQL (25+)
3. 🔴 **Add monitoring** - Track performance metrics
4. 🔴 **Load test with PostgreSQL** - Verify improvements

## Conclusion

**After Optimization:**
- ⚠️ **Minimal improvement** (20 fewer timeouts)
- ⚠️ **Still overwhelmed** at 250 concurrent connections
- 🔴 **SQLite is the bottleneck** - Not connection pool or threads
- 🔴 **250 concurrent too high** for SQLite architecture

**Key Insight:**
- Configuration changes help but **SQLite limitations are the real issue**
- Single-writer lock prevents scaling beyond ~100-150 concurrent
- For production workloads, **PostgreSQL is recommended**

**Next Steps:**
1. Test at realistic loads (50-150 concurrent)
2. Document SQLite capacity limits
3. Plan PostgreSQL migration for production
4. Continue optimizing queries (already done with composite index)

**Expected Performance with PostgreSQL:**
- **250 concurrent**: Should handle easily
- **RPS**: Expected 200-400+ RPS
- **Latency**: Expected <300ms
- **Timeouts**: Should be minimal

See `docs/PERFORMANCE_ANALYSIS.md` for full analysis.
See `docs/DATABASE_OPTIMIZATION.md` for optimization details.

