# Understanding wrk Load Test Results

## Your Test Command

```bash
wrk -t12 -c150 -d30s -s load_test/wrk_feed.lua http://localhost:3000/
```

**Parameters:**
- `-t12`: 12 threads (worker threads)
- `-c150`: 150 concurrent connections
- `-d30s`: Duration of 30 seconds
- `-s load_test/wrk_feed.lua`: Custom Lua script for request logic
- `http://localhost:3000/`: Target URL

## Your Results Breakdown

```
Running 30s test @ http://localhost:3000/
  12 threads and 150 connections
```

**Test Configuration:**
- 12 worker threads handling requests
- 150 concurrent connections (simulating 150 simultaneous users)
- 30 seconds test duration

### Thread Stats

```
Thread Stats   Avg      Stdev     Max   +/- Stdev
    Latency   522.89ms   53.82ms 664.54ms   83.46%
    Req/Sec    30.71     20.19   120.00     63.73%
```

**Latency (Response Time):**
- **Avg: 522.89ms** - Average response time per request
- **Stdev: 53.82ms** - Standard deviation (how much variation)
- **Max: 664.54ms** - Slowest request
- **+/- Stdev: 83.46%** - 83.46% of requests were within 1 standard deviation

**Interpretation:**
- Average response time of ~523ms is **moderate** for a feed page
- Most requests (83%) fall within a tight range (523ms ± 54ms)
- Maximum latency of 664ms is reasonable under this load
- **Note**: This is testing the feed page which is the most expensive query

**Req/Sec (Requests Per Second per Thread):**
- **Avg: 30.71** - Average requests per second per thread
- **Stdev: 20.19** - High variation (some threads handling more/less)
- **Max: 120.00** - Peak requests per second per thread
- **+/- Stdev: 63.73%** - 63.73% within 1 standard deviation

**Interpretation:**
- Each thread handles ~31 requests/second on average
- Significant variation between threads (63.73% within range)
- Peak performance shows threads can handle up to 120 req/sec

### Overall Statistics

```
8217 requests in 30.09s, 8.02MB read
Requests/sec:    273.05
Transfer/sec:    272.82KB
```

**Total Requests:**
- **8,217 requests** completed in 30.09 seconds
- **8.02 MB** of data transferred

**Throughput:**
- **273.05 requests/second** - Overall application throughput
- **272.82 KB/second** - Data transfer rate

**Calculation:**
- 12 threads × 30.71 avg req/sec = ~368 req/sec theoretical max
- Actual: 273 req/sec = ~74% efficiency
- This suggests some bottlenecks (database, connection pool, etc.)

## Performance Analysis

### Is This Good or Bad?

**For a Feed Page (Most Expensive Query):**
- ✅ **273 RPS** is decent for a complex feed query
- ✅ Average latency of **523ms** is acceptable under 150 concurrent connections
- ⚠️ **High variation** in req/sec per thread suggests uneven load distribution
- ⚠️ **74% efficiency** indicates some resource contention

### Comparison to Your Performance Analysis

From `PERFORMANCE_ANALYSIS.md`, your target was:
- **33 RPS sustained** (realistic load)
- **100 RPS peak**
- **Feed page: <200ms p95** (target)

**Your Results:**
- ✅ **273 RPS achieved** - Much higher than target! (likely due to simpler test)
- ⚠️ **523ms average latency** - Higher than 200ms target
  - But this is under 150 concurrent connections (very high load)
  - Without pagination, this would be much worse!

### What the Results Tell Us

**Positive Indicators:**
1. **Application is handling load** - 273 RPS sustained
2. **No crashes** - All 8,217 requests completed
3. **Reasonable latency** - 523ms average under 150 concurrent users
4. **Stable performance** - 83% of requests within tight latency range

**Areas of Concern:**
1. **High latency variation** - Some requests much slower (up to 664ms)
2. **Thread efficiency** - Only 74% of theoretical throughput
3. **Inconsistent load** - High variation in req/sec per thread

### Limitations of This Test

**What wrk with this script is testing:**
- Simple GET requests to root path
- No authentication (public feed)
- No CSRF tokens needed
- No POST requests
- No pagination testing
- No filter parameter testing

**What it's NOT testing:**
- Authenticated feed (logged-in users) - more expensive
- Post creation
- Follow/unfollow
- User profiles
- Pagination (cursor-based)
- Filter options

## Recommendations Based on Results

### 1. **Good Performance Under Load**
Your 273 RPS is excellent! This suggests:
- Pagination is working (only loading 20 posts)
- Database queries are efficient
- Server can handle concurrent load

### 2. **Latency Could Be Better**
At 523ms average, consider:
- **Add composite index** on `(author_id, created_at)` for posts
- **Optimize feed query** (use JOIN instead of large IN clause)
- **Increase connection pool** if needed
- **Add caching** for frequently accessed feeds

### 3. **Test Authenticated Feed**
The wrk script tests public feed. Test authenticated feed separately:
```bash
# Use k6 for authenticated testing (see k6_feed_test.js)
k6 run load_test/k6_feed_test.js
```

### 4. **Test with Realistic Data**
Your test uses public feed (no following). With 10k users and following relationships:
- Feed queries would be more expensive
- Latency would likely increase
- Need to test with actual user accounts

## Comparing to k6 Results

**k6 vs wrk:**
- **wrk**: Simple, fast, good for baseline throughput
- **k6**: More realistic, tests authentication, CSRF, pagination, filters

**For comprehensive testing, use k6:**
```bash
k6 run load_test/k6_comprehensive.js
```

This will test:
- Authenticated feeds
- All filter options
- Pagination
- Post creation
- Follow/unfollow
- Realistic user behavior

## Expected Results Under Different Loads

### Low Load (10 concurrent)
- **Expected**: ~50-100 RPS, <200ms latency
- **Your result**: N/A (tested at 150 concurrent)

### Medium Load (50 concurrent)
- **Expected**: ~100-200 RPS, 200-400ms latency
- **Your result**: N/A (tested at 150 concurrent)

### High Load (150 concurrent) - Your Test
- **Your result**: 273 RPS, 523ms latency
- **Assessment**: Good performance under high load

### Extreme Load (300+ concurrent)
- **Expected**: Degradation in throughput, higher latency
- **Recommendation**: Test with k6 stress test

## Action Items

1. ✅ **Current performance is acceptable** for 150 concurrent users
2. ⚠️ **Optimize feed queries** to reduce latency to <200ms
3. ⚠️ **Test authenticated feed** with k6 (more realistic)
4. ⚠️ **Test pagination** to ensure it's working correctly
5. ⚠️ **Monitor database** during tests to identify bottlenecks

## Conclusion

Your wrk test shows **good baseline performance**:
- **273 RPS** is solid throughput
- **523ms average latency** is acceptable under high load
- Application is **stable** (no crashes, all requests completed)

However, this test is **limited** to public, unauthenticated feed. For production readiness, use k6 scripts which test:
- Authenticated users
- All filter options
- Pagination
- Realistic user behavior

The results suggest your application can handle **moderate to high traffic** but would benefit from:
- Query optimization (composite indexes)
- Feed query improvements (JOIN instead of IN clause)
- Caching for frequently accessed content

