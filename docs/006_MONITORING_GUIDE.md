# Load Testing Monitoring & Visibility Guide

This guide explains how the load testing system works and how to monitor performance in real-time.

## Table of Contents

1. [How Load Testing Works](#how-load-testing-works)
2. [Real-Time Monitoring](#real-time-monitoring)
3. [Understanding k6 Output](#understanding-k6-output)
4. [Rails Application Monitoring](#rails-application-monitoring)
5. [Database Monitoring](#database-monitoring)
6. [System Resource Monitoring](#system-resource-monitoring)
7. [Setting Up Real-Time Dashboards](#setting-up-real-time-dashboards)

---

## How Load Testing Works

### Overview

The load testing setup uses **k6** to simulate multiple users accessing your Rails application simultaneously. Here's how it works:

```
┌─────────────────┐
│   k6 Script     │  ← Defines user behavior (what each "user" does)
│   (JavaScript)  │
└────────┬────────┘
         │
         │ Creates Virtual Users (VUs)
         │
         ▼
┌─────────────────┐
│  Virtual Users  │  ← Each VU = one simulated user
│  (10-200 VUs)   │     - Logs in
│                 │     - Views feed
│                 │     - Creates posts
│                 │     - etc.
└────────┬────────┘
         │
         │ Makes HTTP Requests
         │
         ▼
┌─────────────────┐
│  Rails Server   │  ← Your application
│  (Puma)         │     - Processes requests
│                 │     - Queries database
│                 │     - Renders views
└────────┬────────┘
         │
         │ Returns Response
         │
         ▼
┌─────────────────┐
│  k6 Metrics     │  ← Collects data
│  - Duration     │     - Response times
│  - Status codes│     - Error rates
│  - Throughput   │     - Request counts
└─────────────────┘
```

### What k6 Does

1. **Creates Virtual Users (VUs)**: Each VU simulates a real user
   - Logs in as a specific user
   - Maintains session cookies
   - Performs actions (view feed, create post, etc.)

2. **Sends HTTP Requests**:
   - GET requests (viewing pages)
   - POST requests (creating posts)
   - DELETE requests (unfollowing)

3. **Measures Performance**:
   - Response time (how long each request takes)
   - Status codes (200, 404, 500, etc.)
   - Error rates
   - Requests per second (throughput)

4. **Ramps Load**: Gradually increases or decreases the number of concurrent users

### Example: What One Virtual User Does

```javascript
// This is what happens for EACH virtual user:

1. Login
   GET /dev/login/123 → Sets session cookie

2. View Feed (50% of time)
   GET / → Returns feed page
   - Measures: Response time, status code

3. View Post (30% of time)
   GET /posts/456 → Returns post page
   - Measures: Response time, status code

4. Create Post (5% of time)
   POST /posts → Creates new post
   - Measures: Response time, status code

5. Repeat steps 2-4 for session duration
```

---

## Real-Time Monitoring

### Option 1: k6 Built-in Output (Recommended for Start)

k6 provides real-time metrics in the terminal:

```bash
k6 run load_test/k6_feed_test.js
```

**Output Example:**
```
     ✓ feed page status 200
     ✓ feed page has posts
     ✓ feed page response time acceptable

     checks.........................: 100.00% ✓ 1250    ✗ 0
     data_received..................: 2.5 MB  41 kB/s
     data_sent......................: 180 kB  3.0 kB/s
     feed_page_duration.............: avg=245ms min=120ms med=220ms max=850ms p(90)=420ms p(95)=580ms
     http_req_duration..............: avg=280ms min=100ms med=250ms max=1200ms p(90)=500ms p(95)=650ms p(99)=950ms
       { expected_response:true }...: avg=280ms min=100ms med=250ms max=1200ms p(90)=500ms p(95)=650ms p(99)=950ms
     http_req_failed................: 0.00%   ✓ 0       ✗ 1250
     http_reqs......................: 1250    20.83/s
     iteration_duration.............: avg=3.2s  min=1.5s med=3.0s max=8.5s
     iterations.....................: 50      0.83/s
     vus............................: 10      min=10    max=100
     vus_max........................: 100     min=100   max=100
```

**Understanding the Metrics:**
- `http_req_duration`: How long each request takes
  - `p(95)=650ms`: 95% of requests completed in under 650ms
  - `p(99)=950ms`: 99% of requests completed in under 950ms
- `http_req_failed`: Percentage of failed requests
- `http_reqs`: Total requests and requests per second
- `vus`: Current number of virtual users

### Option 2: k6 Cloud Dashboard (Best Visibility)

k6 Cloud provides a real-time web dashboard with graphs and metrics.

**Setup:**
```bash
# Install k6 Cloud (if not already installed)
# Sign up at https://app.k6.io

# Run with cloud output
k6 cloud load_test/k6_feed_test.js
```

**What You See:**
- Real-time request rate graph
- Response time percentiles over time
- Error rate over time
- Geographic distribution of load
- Custom metrics (feed_page_duration, etc.)

### Option 3: Custom Monitoring Script

Run the monitoring script in a separate terminal:

```bash
# Terminal 1: Start Rails server
rails server

# Terminal 2: Run load test
k6 run load_test/k6_feed_test.js

# Terminal 3: Monitor system
./script/monitor_load_test.sh
```

**What It Shows:**
- Rails process CPU and memory usage
- Database size
- Recent errors from logs
- Slow queries count

---

## Understanding k6 Output

### Response Time Metrics

```
http_req_duration: avg=280ms min=100ms med=250ms max=1200ms p(90)=500ms p(95)=650ms p(99)=950ms
```

**Breakdown:**
- `avg`: Average response time (280ms)
- `min`: Fastest request (100ms)
- `max`: Slowest request (1200ms)
- `med`: Median (50th percentile) - 250ms
- `p(90)`: 90th percentile - 90% of requests faster than 500ms
- `p(95)`: 95th percentile - 95% of requests faster than 650ms
- `p(99)`: 99th percentile - 99% of requests faster than 950ms

**What to Watch:**
- ✅ **p(95) < 200ms**: Excellent performance
- ⚠️ **p(95) 200-500ms**: Acceptable, but could be better
- 🔴 **p(95) > 500ms**: Performance issue, investigate

### Error Rate

```
http_req_failed: 0.00% ✓ 0 ✗ 1250
```

**Breakdown:**
- `0.00%`: Percentage of failed requests
- `✓ 0`: Successful requests (1250)
- `✗ 0`: Failed requests (0)

**What to Watch:**
- ✅ **< 1%**: Good
- ⚠️ **1-5%**: Acceptable under stress
- 🔴 **> 5%**: Critical issue

### Throughput

```
http_reqs: 1250    20.83/s
```

**Breakdown:**
- `1250`: Total requests made
- `20.83/s`: Requests per second (RPS)

**What to Watch:**
- Compare with your target (33 RPS from analysis)
- If RPS is lower than expected, requests are taking too long

### Virtual Users

```
vus: 10      min=10    max=100
vus_max: 100     min=100   max=100
```

**Breakdown:**
- `vus: 10`: Currently 10 active virtual users
- `vus_max: 100`: Maximum VUs configured
- Shows how load is ramping up/down

---

## Rails Application Monitoring

### 1. Rails Logs (Real-Time)

**Watch logs in real-time:**
```bash
tail -f log/development.log
```

**What to Look For:**

**Slow Queries:**
```
Completed 200 OK in 850ms (Views: 120.5ms | ActiveRecord: 720.3ms)
```
- Look for `> 500ms` - these are slow
- Focus on `ActiveRecord` time (database queries)

**Errors:**
```
Error: ActiveRecord::ConnectionTimeoutError
Error: SQLite3::BusyException: database is locked
```

**Pattern Matching:**
```bash
# Watch for slow requests
tail -f log/development.log | grep -E "Completed.*[0-9]{4}ms"

# Watch for errors
tail -f log/development.log | grep -E "Error|Exception"

# Watch for database queries
tail -f log/development.log | grep "SELECT\|INSERT\|UPDATE"
```

### 2. Enable Query Logging

Add to `config/environments/development.rb`:

```ruby
# Show all SQL queries with timing
config.active_record.logger = Logger.new(STDOUT)
config.active_record.verbose_query_logs = true

# Log slow queries
config.active_record.log_slow_queries = true
config.active_record.slow_query_threshold = 100 # milliseconds
```

### 3. Request Timing Breakdown

Rails logs show where time is spent:

```
Completed 200 OK in 850ms (Views: 120.5ms | ActiveRecord: 720.3ms | Allocations: 45000)
```

**Breakdown:**
- Total: 850ms
- Views: 120.5ms (rendering HTML)
- ActiveRecord: 720.3ms (database queries) ← **This is usually the bottleneck**
- Allocations: Memory allocated

**What to Watch:**
- If `ActiveRecord` time is high → Database bottleneck
- If `Views` time is high → Template rendering issue
- If total time > 500ms → Performance problem

### 4. Puma Stats Endpoint

Add to `config/routes.rb` (development only):

```ruby
if Rails.env.development?
  get '/puma/stats' => proc { |env|
    require 'json'
    stats = Puma.stats
    [200, { 'Content-Type' => 'application/json' }, [stats.to_json]]
  }
end
```

**Monitor:**
```bash
# Watch Puma stats
watch -n 1 'curl -s http://localhost:3000/puma/stats | jq'

# Or one-time
curl http://localhost:3000/puma/stats | jq
```

**What You See:**
```json
{
  "workers": 1,
  "phase": 0,
  "booted_workers": 1,
  "old_workers": 0,
  "worker_status": [{
    "pid": 12345,
    "index": 0,
    "phase": 0,
    "booted": true,
    "last_checkin": "2024-01-01T12:00:00Z",
    "last_status": {
      "backlog": 0,
      "running": 5,
      "pool_capacity": 10,
      "max_threads": 5,
      "requests_count": 1250
    }
  }]
}
```

**Key Metrics:**
- `backlog`: Queued requests (should be 0)
- `running`: Active requests being processed
- `pool_capacity`: Available thread capacity
- `requests_count`: Total requests processed

---

## Database Monitoring

### SQLite-Specific Monitoring

**Check Database Size:**
```bash
du -sh storage/development.sqlite3
ls -lh storage/development.sqlite3
```

**Check for Locks:**
```bash
# SQLite shows locks in logs
tail -f log/development.log | grep -i "locked\|busy"
```

**Monitor Query Patterns:**
```bash
# Watch for slow queries
tail -f log/development.log | grep "SELECT" | grep -E "\([0-9]{3,}ms\)"
```

### Connection Pool Monitoring

**Check Connection Pool Usage:**

Add to `config/initializers/database_monitoring.rb`:

```ruby
if Rails.env.development?
  ActiveSupport::Notifications.subscribe('sql.active_record') do |name, start, finish, id, payload|
    if payload[:sql] =~ /SELECT.*FROM.*follows/
      duration = ((finish - start) * 1000).round(2)
      Rails.logger.info "[DB MONITOR] Query: #{payload[:sql][0..100]}... (#{duration}ms)"
    end
  end
end
```

---

## System Resource Monitoring

### macOS Tools

**1. Activity Monitor (GUI)**
- Open Activity Monitor
- Find "ruby" or "puma" process
- Watch CPU and Memory tabs
- Check "Energy" tab for overall impact

**2. Terminal Monitoring**

**CPU and Memory:**
```bash
# Top-like display
top -pid $(pgrep -f "puma\|rails server")

# Or use htop (install with: brew install htop)
htop
```

**Disk I/O:**
```bash
# Monitor disk activity
iostat -w 1
```

**Network:**
```bash
# Monitor network connections
netstat -an | grep :3000

# Count connections
lsof -i :3000 | wc -l
```

### Linux Tools

**1. htop (Better than top)**
```bash
htop
```

**2. iostat (Disk I/O)**
```bash
iostat -x 1
```

**3. vmstat (System stats)**
```bash
vmstat 1
```

---

## Setting Up Real-Time Dashboards

### Option 1: Simple Terminal Dashboard

Create a monitoring script that shows everything:

```bash
# Create: script/full_monitor.sh
#!/bin/bash
watch -n 1 '
echo "=== Rails Server ==="
curl -s http://localhost:3000/puma/stats 2>/dev/null | jq ".worker_status[0].last_status" || echo "Server not responding"
echo ""
echo "=== Database ==="
du -h storage/development.sqlite3 2>/dev/null || echo "No database"
echo ""
echo "=== Process Stats ==="
ps aux | grep -E "puma|rails" | grep -v grep | head -1 | awk "{print \"CPU: \" \$3 \"%  Memory: \" \$4 \"%\"}"
'
```

### Option 2: k6 with InfluxDB + Grafana

For advanced monitoring, set up InfluxDB and Grafana:

**1. Install InfluxDB:**
```bash
brew install influxdb
brew services start influxdb
```

**2. Run k6 with InfluxDB output:**
```bash
k6 run --out influxdb=http://localhost:8086/k6 load_test/k6_feed_test.js
```

**3. Install Grafana:**
```bash
brew install grafana
brew services start grafana
```

**4. Create Dashboard:**
- Access Grafana at http://localhost:3001
- Add InfluxDB data source
- Create dashboard with:
  - Request rate over time
  - Response time percentiles
  - Error rate
  - Virtual users count

### Option 3: Use k6 Cloud (Easiest)

k6 Cloud provides a hosted dashboard:

```bash
# Sign up at https://app.k6.io
# Get your token
export K6_CLOUD_TOKEN=your_token_here

# Run with cloud output
k6 cloud load_test/k6_feed_test.js
```

**Features:**
- Real-time graphs
- Historical data
- Team sharing
- Alerts

---

## Quick Reference: Monitoring Commands

### During Load Test

**Terminal 1 - Rails Server:**
```bash
rails server
```

**Terminal 2 - Load Test:**
```bash
k6 run load_test/k6_feed_test.js
```

**Terminal 3 - Rails Logs:**
```bash
tail -f log/development.log | grep -E "Completed|Error|Slow"
```

**Terminal 4 - System Resources:**
```bash
./script/monitor_load_test.sh
```

**Terminal 5 - Puma Stats:**
```bash
watch -n 1 'curl -s http://localhost:3000/puma/stats | jq ".worker_status[0].last_status"'
```

### Quick Health Checks

**Is server responding?**
```bash
curl http://localhost:3000/up
```

**How many connections?**
```bash
lsof -i :3000 | wc -l
```

**Database size?**
```bash
du -sh storage/development.sqlite3
```

**Recent errors?**
```bash
tail -100 log/development.log | grep -i error | wc -l
```

**Slow queries?**
```bash
tail -100 log/development.log | grep -E "\([0-9]{4,}ms\)"
```

---

## Interpreting Results

### Good Performance Indicators

✅ **k6 Metrics:**
- p(95) response time < 200ms
- Error rate < 1%
- RPS matches target (33 RPS)
- No failed requests

✅ **Rails Logs:**
- ActiveRecord time < 200ms per request
- No errors or exceptions
- No "database locked" messages
- Backlog = 0 in Puma stats

✅ **System Resources:**
- CPU < 70%
- Memory stable (not continuously growing)
- No disk I/O bottlenecks

### Performance Issues Indicators

🔴 **k6 Metrics:**
- p(95) response time > 500ms
- Error rate > 5%
- RPS dropping during test
- Many failed requests

🔴 **Rails Logs:**
- ActiveRecord time > 500ms
- "ConnectionTimeoutError"
- "database is locked"
- Backlog > 10 in Puma stats

🔴 **System Resources:**
- CPU > 90%
- Memory continuously growing (leak)
- Disk I/O at 100%

---

## Next Steps

1. **Start Simple**: Use k6 terminal output first
2. **Add Monitoring**: Run monitoring script in separate terminal
3. **Watch Logs**: Tail Rails logs for slow queries
4. **Analyze**: Look for patterns (which endpoints are slow?)
5. **Optimize**: Fix bottlenecks identified
6. **Re-test**: Verify improvements

For detailed test scenarios, see `docs/LOAD_TESTING.md`.

