#!/bin/bash
# Monitoring script for load testing
# Run this in a separate terminal while running load tests

set -e

echo "Load Test Monitoring"
echo "==================="
echo ""
echo "Press Ctrl+C to stop"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if Rails server is running
check_server() {
  if curl -s http://localhost:3000/up > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Server is running"
  else
    echo -e "${RED}✗${NC} Server is not responding"
    exit 1
  fi
}

# Monitor database size
monitor_database() {
  if [ -f "storage/development.sqlite3" ]; then
    size=$(du -h storage/development.sqlite3 | cut -f1)
    echo "Database size: $size"
  fi
}

# Monitor Rails process
monitor_rails() {
  pid=$(pgrep -f "puma\|rails server" | head -1)
  if [ -n "$pid" ]; then
    mem=$(ps -o rss= -p $pid | awk '{printf "%.1f MB", $1/1024}')
    cpu=$(ps -o %cpu= -p $pid | awk '{print $1"%"}')
    echo "Rails process: PID=$pid, Memory=$mem, CPU=$cpu"
  fi
}

# Count database connections (approximate)
count_connections() {
  # SQLite doesn't easily show connections, but we can check for locks
  if [ -f "storage/development.sqlite3" ]; then
    echo "Database: SQLite (connection count not available)"
  fi
}

# Monitor log file for errors
monitor_errors() {
  if [ -f "log/development.log" ]; then
    recent_errors=$(tail -100 log/development.log | grep -c "Error\|Exception\|Timeout" || echo "0")
    echo "Recent errors (last 100 lines): $recent_errors"
  fi
}

# Monitor slow queries
monitor_slow_queries() {
  if [ -f "log/development.log" ]; then
    slow_queries=$(tail -100 log/development.log | grep -E "\([0-9]+\.[0-9]+ms\)" | awk '{print $NF}' | sed 's/[()ms]//g' | awk '$1 > 100' | wc -l | tr -d ' ')
    echo "Slow queries (>100ms in last 100 lines): $slow_queries"
  fi
}

# Main monitoring loop
main() {
  check_server
  
  while true; do
    clear
    echo "=========================================="
    echo "Load Test Monitor - $(date '+%H:%M:%S')"
    echo "=========================================="
    echo ""
    
    monitor_rails
    monitor_database
    count_connections
    monitor_errors
    monitor_slow_queries
    
    echo ""
    echo "=========================================="
    echo "Press Ctrl+C to stop"
    echo ""
    
    sleep 2
  done
}

# Run main function
main

