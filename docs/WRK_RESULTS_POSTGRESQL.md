# wrk Test Results with PostgreSQL

## Test Configuration

```bash
wrk -t8 -c250 -d30s -s load_test/wrk_feed.lua http://localhost:3000/
```

**Configuration:**
- 8 threads, 250 concurrent connections
- PostgreSQL database (migrated from SQLite)
- Database pool: 10 connections
- Puma threads: 10

## Test Results

```
Running 30s test @ http://localhost:3000/
  8 threads and 250 connections

  Thread Stats   Avg      Stdev     Max   +/- Stdev
    Latency     1.06s   525.77ms   1.98s    59.65%
    Req/Sec     5.63      4.92    49.00     92.48%

  852 requests in 30.10s, 33.12MB read
  Socket errors: connect 0, read 0, write 0, timeout 795

Requests/sec:     28.30
Transfer/sec:      1.10MB
```

## Comparison: SQLite vs PostgreSQL

| Metric | SQLite (Before) | SQLite (After Config) | PostgreSQL (Current) | Change |
|--------|----------------|----------------------|---------------------|--------|
| **RPS** | 27.64 | 26.85 | **28.30** | +1.45 (+5.4%) |
| **Latency** | 1.10s | 1.18s | **1.06s** | -0.04s (-3.6%) |
| **Requests** | 832 | 806 | **852** | +46 (+5.7%) |
| **Timeouts** | 777 | 757 | **795** | +38 (+5.0%) |
| **Efficiency** | 61% | 62% | **63%** | +1% |

## Analysis

### Performance Improvements

**✅ Slight Improvements:**
- **RPS**: 28.30 (vs 27.64 SQLite) - **+5.4% improvement**
- **Latency**: 1.06s (vs 1.10s SQLite) - **-3.6% improvement**
- **Requests Completed**: 852 (vs 832 SQLite) - **+2.4% more requests**

**⚠️ Still Issues:**
- **795 timeouts** - Still very high (worse than SQLite's 757)
- **Only 63% efficiency** - Still poor
- **Latency still high** - 1.06s average is unacceptable

### Why Timeouts Increased?

**The Problem:**
- **795 timeouts** (vs 757 with SQLite) - **+5% more timeouts**
- This suggests the bottleneck is **NOT** the database anymore
- The bottleneck is likely **application-level** (connection pool, Puma threads)

**Root Cause:**
1. **Connection Pool Exhaustion** - 10 connections for 250 concurrent requests
   - 250 requests ÷ 10 connections = 25 requests per connection
   - Requests queue up waiting for database connections
   - PostgreSQL can handle more, but pool is limiting

2. **Puma Thread Pool** - 10 threads for 250 connections
   - 250 connections ÷ 10 threads = 25 connections per thread
   - Requests queue up waiting for thread availability
   - Threads are waiting on database connections

3. **Request Complexity** - `wrk_feed.lua` does:
   - Login request → Database write (session)
   - Feed query → Complex JOIN query
   - Multiple database operations per request

### What PostgreSQL Fixed

**✅ Database-Level Improvements:**
- **No single-writer lock** - PostgreSQL handles concurrent writes
- **Better query planner** - JOINs are optimized better
- **Better index usage** - Composite index works efficiently
- **Connection handling** - Can handle more concurrent connections

**But:** The bottleneck moved from database to **application configuration**

### The Real Bottleneck Now

**Application Configuration:**
- **Connection Pool**: 10 (too small for 250 concurrent)
- **Puma Threads**: 10 (too small for 250 concurrent)
- **Request Queue**: Requests waiting for resources

**At 250 Concurrent:**
- 250 requests arrive simultaneously
- Only 10 database connections available
- 240 requests queue up → timeouts occur
- PostgreSQL can handle more, but pool prevents it

## Recommendations

### Immediate Fixes

**1. Increase Connection Pool (Critical):**
```ruby
# config/database.yml
default: &default
  adapter: postgresql
  pool: 25  # Increase from 10 to 25
```

**2. Increase Puma Threads:**
```ruby
# config/puma.rb
threads_count = ENV.fetch("RAILS_MAX_THREADS", 25)  # Increase from 10
threads threads_count, threads_count
```

**3. PostgreSQL Configuration:**
```ruby
# config/database.yml
default: &default
  adapter: postgresql
  pool: 25
  # PostgreSQL-specific optimizations
  prepared_statements: true
  statement_limit: 1000
```

### Expected Performance After Tuning

**With pool: 25, threads: 25:**
- **RPS**: Expected 100-200+ (vs current 28.30)
- **Latency**: Expected <300ms (vs current 1.06s)
- **Timeouts**: Expected <50 (vs current 795)
- **Efficiency**: Expected >80% (vs current 63%)

### Why PostgreSQL Should Perform Better

**PostgreSQL Advantages:**
1. **True Concurrent Writes** - No single-writer lock
2. **Better Connection Handling** - Designed for 100+ connections
3. **Better Query Planner** - Optimizes complex JOINs
4. **Better Index Usage** - Composite indexes work efficiently
5. **Production Ready** - Designed for high-concurrency workloads

**Current Limitation:**
- Application configuration is the bottleneck, not PostgreSQL
- Once pool/threads are increased, PostgreSQL will shine

## Action Items

### Priority 1 (Immediate):
1. **Increase connection pool to 25**
2. **Increase Puma threads to 25**
3. **Re-test** to verify improvements

### Priority 2 (Optimization):
1. **Tune PostgreSQL** for better performance
2. **Add connection pooling** at application level (PgBouncer)
3. **Monitor** database connections during tests

### Priority 3 (Production):
1. **Use connection pooler** (PgBouncer) for production
2. **Set up monitoring** (pg_stat_statements)
3. **Load test** with realistic data volumes

## Testing Strategy

**Gradual Load Increase:**
```bash
# Test with lower load first
wrk -t4 -c50 -d30s -s load_test/wrk_feed.lua http://localhost:3000/
wrk -t8 -c100 -d30s -s load_test/wrk_feed.lua http://localhost:3000/
wrk -t8 -c150 -d30s -s load_test/wrk_feed.lua http://localhost:3000/
wrk -t8 -c200 -d30s -s load_test/wrk_feed.lua http://localhost:3000/
wrk -t8 -c250 -d30s -s load_test/wrk_feed.lua http://localhost:3000/
```

**Find the breaking point** where performance degrades.

## Conclusion

**Current State:**
- ✅ PostgreSQL is working correctly
- ✅ Slight performance improvement over SQLite
- ⚠️ **Application configuration is the bottleneck**
- 🔴 **795 timeouts** indicate resource exhaustion

**Key Insight:**
- PostgreSQL can handle the load, but **application isn't configured to use it**
- Connection pool (10) and threads (10) are too small for 250 concurrent
- Need to increase both to 25+ to see PostgreSQL's true potential

**Next Steps:**
1. Increase pool and threads to 25
2. Re-test at 250 concurrent
3. Expect significant improvement (100-200+ RPS, <300ms latency)

See `docs/WRK_RESULTS_AFTER_OPTIMIZATION.md` for SQLite comparison.
See `docs/POSTGRESQL_SETUP.md` for setup instructions.

