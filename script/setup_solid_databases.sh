#!/bin/bash
# Setup script for Solid Cache, Queue, and Cable PostgreSQL databases
# Run this after switching from SQLite to PostgreSQL

set -e

echo "Setting up Solid Cache, Queue, and Cable databases..."

# Check if we're in the right environment
if [ -z "$RAILS_ENV" ]; then
  echo "Warning: RAILS_ENV not set, defaulting to development"
  export RAILS_ENV=development
fi

echo "Environment: $RAILS_ENV"

# Create databases based on environment
case "$RAILS_ENV" in
  development)
    CACHE_DB="microblog_cache"
    QUEUE_DB="microblog_queue"
    CABLE_DB="microblog_cable"
    ;;
  test)
    CACHE_DB="microblog_cache_test"
    QUEUE_DB="microblog_queue_test"
    CABLE_DB="microblog_cable_test"
    ;;
  production)
    CACHE_DB="microblog_cache"
    QUEUE_DB="microblog_queue"
    CABLE_DB="microblog_cable"
    ;;
  *)
    echo "Unknown environment: $RAILS_ENV"
    exit 1
    ;;
esac

echo "Creating databases: $CACHE_DB, $QUEUE_DB, $CABLE_DB"

# Create databases (will fail gracefully if they already exist)
createdb "$CACHE_DB" 2>/dev/null || echo "Database $CACHE_DB already exists"
createdb "$QUEUE_DB" 2>/dev/null || echo "Database $QUEUE_DB already exists"
createdb "$CABLE_DB" 2>/dev/null || echo "Database $CABLE_DB already exists"

echo "Running Solid Cache install..."
bin/rails solid_cache:install

echo "Running Solid Queue install..."
bin/rails solid_queue:install

echo "Running Solid Cable install..."
bin/rails solid_cable:install

echo "Done! Solid databases are now set up."

