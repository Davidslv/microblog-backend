# Load Testing Scripts

Quick reference for running load tests.

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

## Run Tests

### 1. Baseline Test (Quick Check)
```bash
k6 run load_test/k6_baseline.js
```

### 2. Feed Page Test (Critical Bottleneck)
```bash
k6 run load_test/k6_feed_test.js
```

### 3. Comprehensive Test (Realistic Load)
```bash
k6 run load_test/k6_comprehensive.js
```

### 4. Stress Test (Find Breaking Point)
```bash
k6 run load_test/k6_stress_test.js
```

## Customize Tests

Set environment variables:

```bash
# Custom base URL
BASE_URL=http://localhost:3000 k6 run load_test/k6_baseline.js

# Custom user count
NUM_USERS=5000 k6 run load_test/k6_comprehensive.js
```

## Monitor During Tests

```bash
# Watch Rails logs
tail -f log/development.log | grep -E "(Completed|Slow|Error)"

# Watch system resources
top -pid $(pgrep -f "puma")
```

## Quick wrk Test

```bash
# Simple baseline
wrk -t4 -c10 -d10s http://localhost:3000/
```

See `docs/LOAD_TESTING.md` for detailed documentation.

