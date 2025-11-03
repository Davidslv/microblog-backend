#!/bin/bash
# Quick start script for load testing
# This sets up monitoring and runs a load test

set -e

echo "🚀 Load Testing Quick Start"
echo "============================"
echo ""

# Check if k6 is installed
if ! command -v k6 &> /dev/null; then
    echo "❌ k6 is not installed"
    echo "Install with: brew install k6"
    exit 1
fi

# Check if Rails server is running
if ! curl -s http://localhost:3000/up > /dev/null 2>&1; then
    echo "❌ Rails server is not running"
    echo "Start it with: rails server"
    exit 1
fi

echo "✅ Rails server is running"
echo ""

# Check if test data exists
if [ ! -f "storage/development.sqlite3" ] || [ $(sqlite3 storage/development.sqlite3 "SELECT COUNT(*) FROM users;" 2>/dev/null || echo "0") -lt 100 ]; then
    echo "⚠️  Test data not found or insufficient"
    echo "Creating test data..."
    echo ""
    NUM_USERS=100 POSTS_PER_USER=50 rails runner script/load_test_seed.rb
    echo ""
fi

echo "Select test to run:"
echo "1) Baseline test (quick, 10 users)"
echo "2) Feed page test (focused on feed performance)"
echo "3) Comprehensive test (realistic load, 50 users)"
echo "4) Stress test (find breaking point, up to 200 users)"
echo ""
read -p "Enter choice [1-4]: " choice

case $choice in
    1)
        TEST="k6_baseline.js"
        ;;
    2)
        TEST="k6_feed_test.js"
        ;;
    3)
        TEST="k6_comprehensive.js"
        ;;
    4)
        TEST="k6_stress_test.js"
        ;;
    *)
        echo "Invalid choice"
        exit 1
        ;;
esac

echo ""
echo "Starting load test: $TEST"
echo ""
echo "💡 Tips:"
echo "   - Open another terminal and run: tail -f log/development.log"
echo "   - Or run: ./script/monitor_load_test.sh"
echo "   - Watch for slow queries and errors"
echo ""
echo "Press Ctrl+C to stop the test"
echo ""
echo "============================"
echo ""

# Run the test
k6 run "load_test/$TEST"

