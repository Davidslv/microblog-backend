#!/bin/bash
# Setup script for Solid Cache, Queue, and Cable PostgreSQL databases
# Creates dedicated users with passwords and databases for each service
# Run this after switching from SQLite to PostgreSQL

set -e

echo "Setting up Solid Cache, Queue, and Cable databases with dedicated credentials..."
echo ""

# Check if we're in the right environment
if [ -z "$RAILS_ENV" ]; then
  echo "Warning: RAILS_ENV not set, defaulting to development"
  export RAILS_ENV=development
fi

echo "Environment: $RAILS_ENV"
echo ""

# Get credentials from environment or use defaults
CACHE_USER="${CACHE_DB_USERNAME:-microblog_cache}"
CACHE_PASS="${CACHE_DB_PASSWORD:-}"
QUEUE_USER="${QUEUE_DB_USERNAME:-microblog_queue}"
QUEUE_PASS="${QUEUE_DB_PASSWORD:-}"
CABLE_USER="${CABLE_DB_USERNAME:-microblog_cable}"
CABLE_PASS="${CABLE_DB_PASSWORD:-}"

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

# Function to create user and database
create_user_and_db() {
  local username=$1
  local password=$2
  local database=$3
  local service_name=$4

  echo "Setting up $service_name..."

  # Create user if it doesn't exist
  if psql -U postgres -t -c "SELECT 1 FROM pg_user WHERE usename='$username';" | grep -q 1; then
    echo "  ✓ User '$username' already exists"

    # Update password if provided
    if [ -n "$password" ]; then
      psql -U postgres -c "ALTER USER $username WITH PASSWORD '$password';" > /dev/null
      echo "  ✓ Updated password for user '$username'"
    fi
  else
    if [ -n "$password" ]; then
      psql -U postgres -c "CREATE USER $username WITH PASSWORD '$password';" > /dev/null
      echo "  ✓ Created user '$username' with password"
    else
      psql -U postgres -c "CREATE USER $username;" > /dev/null
      echo "  ✓ Created user '$username' (no password)"
    fi
  fi

  # Create database if it doesn't exist
  if psql -U postgres -lqt | cut -d \| -f 1 | grep -qw "$database"; then
    echo "  ✓ Database '$database' already exists"
  else
    psql -U postgres -c "CREATE DATABASE $database OWNER $username;" > /dev/null
    echo "  ✓ Created database '$database' owned by '$username'"
  fi

  # Grant all privileges on database to user
  psql -U postgres -c "GRANT ALL PRIVILEGES ON DATABASE $database TO $username;" > /dev/null
  echo "  ✓ Granted privileges on '$database' to '$username'"
  echo ""
}

# Prompt for passwords if not set (for production)
if [ "$RAILS_ENV" = "production" ] && [ -z "$CACHE_PASS" ]; then
  read -sp "Enter password for cache user ($CACHE_USER): " CACHE_PASS
  echo ""
fi

if [ "$RAILS_ENV" = "production" ] && [ -z "$QUEUE_PASS" ]; then
  read -sp "Enter password for queue user ($QUEUE_USER): " QUEUE_PASS
  echo ""
fi

if [ "$RAILS_ENV" = "production" ] && [ -z "$CABLE_PASS" ]; then
  read -sp "Enter password for cable user ($CABLE_USER): " CABLE_PASS
  echo ""
fi

# Create users and databases
create_user_and_db "$CACHE_USER" "$CACHE_PASS" "$CACHE_DB" "Solid Cache"
create_user_and_db "$QUEUE_USER" "$QUEUE_PASS" "$QUEUE_DB" "Solid Queue"
create_user_and_db "$CABLE_USER" "$CABLE_PASS" "$CABLE_DB" "Solid Cable"

echo "Running Rails install commands..."
echo ""

# Set environment variables for Rails commands
export CACHE_DB_USERNAME="$CACHE_USER"
export CACHE_DB_PASSWORD="$CACHE_PASS"
export QUEUE_DB_USERNAME="$QUEUE_USER"
export QUEUE_DB_PASSWORD="$QUEUE_PASS"
export CABLE_DB_USERNAME="$CABLE_USER"
export CABLE_DB_PASSWORD="$CABLE_PASS"

echo "Installing Solid Cache..."
bin/rails solid_cache:install

echo "Installing Solid Queue..."
bin/rails solid_queue:install

echo "Installing Solid Cable..."
bin/rails solid_cable:install

echo ""
echo "✅ Done! Solid databases are now set up with dedicated credentials."
echo ""
echo "Environment variables to set:"
echo "  CACHE_DB_USERNAME=$CACHE_USER"
echo "  CACHE_DB_PASSWORD=$([ -n "$CACHE_PASS" ] && echo "***" || echo "(not set)")"
echo "  QUEUE_DB_USERNAME=$QUEUE_USER"
echo "  QUEUE_DB_PASSWORD=$([ -n "$QUEUE_PASS" ] && echo "***" || echo "(not set)")"
echo "  CABLE_DB_USERNAME=$CABLE_USER"
echo "  CABLE_DB_PASSWORD=$([ -n "$CABLE_PASS" ] && echo "***" || echo "(not set)")"
