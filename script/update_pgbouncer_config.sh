#!/bin/bash
# Update PgBouncer configuration to use our settings
# This script updates the active PgBouncer config file

set -e

echo "Updating PgBouncer configuration..."

# Detect OS and config location
if [[ "$OSTYPE" == "darwin"* ]]; then
    PGBOUNCER_CONFIG="/opt/homebrew/etc/pgbouncer.ini"
    PGBOUNCER_PID="/opt/homebrew/var/run/pgbouncer.pid"
    OUR_CONFIG="config/pgbouncer.ini"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    PGBOUNCER_CONFIG="/etc/pgbouncer/pgbouncer.ini"
    PGBOUNCER_PID="/var/run/pgbouncer/pgbouncer.pid"
    OUR_CONFIG="config/pgbouncer.ini"
else
    echo "Unsupported OS: $OSTYPE"
    exit 1
fi

# Check if our config exists
if [ ! -f "$OUR_CONFIG" ]; then
    echo "Error: $OUR_CONFIG not found"
    exit 1
fi

# Backup current config
if [ -f "$PGBOUNCER_CONFIG" ]; then
    echo "Backing up current config to ${PGBOUNCER_CONFIG}.backup"
    sudo cp "$PGBOUNCER_CONFIG" "${PGBOUNCER_CONFIG}.backup"
fi

# Stop PgBouncer if running
if [ -f "$PGBOUNCER_PID" ]; then
    PID=$(cat "$PGBOUNCER_PID")
    if ps -p "$PID" > /dev/null 2>&1; then
        echo "Stopping PgBouncer (PID: $PID)..."
        kill "$PID" || true
        sleep 2
    fi
fi

# Copy our config
echo "Copying configuration to $PGBOUNCER_CONFIG..."
sudo cp "$OUR_CONFIG" "$PGBOUNCER_CONFIG"

# Make sure directories exist
if [[ "$OSTYPE" == "darwin"* ]]; then
    sudo mkdir -p /opt/homebrew/var/log
    sudo mkdir -p /opt/homebrew/var/run
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    sudo mkdir -p /var/log/pgbouncer
    sudo mkdir -p /var/run/pgbouncer
fi

# Update logfile and pidfile paths in config for macOS
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "Updating logfile and pidfile paths for macOS..."
    sudo sed -i '' "s|logfile = /tmp/pgbouncer.log|logfile = /opt/homebrew/var/log/pgbouncer.log|" "$PGBOUNCER_CONFIG"
    sudo sed -i '' "s|pidfile = /tmp/pgbouncer.pid|pidfile = /opt/homebrew/var/run/pgbouncer.pid|" "$PGBOUNCER_CONFIG"
fi

echo ""
echo "Configuration updated!"
echo ""
echo "To start PgBouncer:"
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "  pgbouncer -d $PGBOUNCER_CONFIG"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    echo "  sudo systemctl start pgbouncer"
fi
echo ""
echo "To verify it's running:"
echo "  lsof -i :6432"

