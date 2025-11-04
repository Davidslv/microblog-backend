#!/bin/bash
# Quick script to restart PgBouncer with updated config

echo "Restarting PgBouncer..."

# Stop PgBouncer
pkill pgbouncer || true
sleep 2

# Verify it's stopped
if ps aux | grep pgbouncer | grep -v grep > /dev/null; then
    echo "Warning: PgBouncer still running, forcing stop..."
    pkill -9 pgbouncer
    sleep 1
fi

# Update config if needed
if [ -f "config/pgbouncer.ini" ]; then
    echo "Updating PgBouncer config..."
    sudo cp config/pgbouncer.ini /opt/homebrew/etc/pgbouncer.ini
    sudo sed -i '' 's|logfile = /tmp/pgbouncer.log|logfile = /opt/homebrew/var/log/pgbouncer.log|' /opt/homebrew/etc/pgbouncer.ini
    sudo sed -i '' 's|pidfile = /tmp/pgbouncer.pid|pidfile = /opt/homebrew/var/run/pgbouncer.pid|' /opt/homebrew/etc/pgbouncer.ini
fi

# Start PgBouncer
echo "Starting PgBouncer..."
pgbouncer -d /opt/homebrew/etc/pgbouncer.ini

sleep 2

# Verify it's running
if lsof -i :6432 > /dev/null 2>&1; then
    echo "✅ PgBouncer is running on port 6432"
    echo ""
    echo "Restart your Rails server now."
else
    echo "❌ PgBouncer failed to start. Check logs:"
    echo "   tail -f /opt/homebrew/var/log/pgbouncer.log"
    exit 1
fi

