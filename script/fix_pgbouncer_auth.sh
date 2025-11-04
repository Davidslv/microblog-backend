#!/bin/bash
# Quick fix for PgBouncer authentication issue
# This script updates PgBouncer to use trust authentication

set -e

echo "Fixing PgBouncer authentication..."

# Stop PgBouncer
echo "Stopping PgBouncer..."
pkill pgbouncer || true
sleep 2

# Backup current config
if [ -f /opt/homebrew/etc/pgbouncer.ini ]; then
    echo "Backing up current config..."
    sudo cp /opt/homebrew/etc/pgbouncer.ini /opt/homebrew/etc/pgbouncer.ini.backup
fi

# Copy our config
echo "Copying new config..."
sudo cp "$(dirname "$0")/../config/pgbouncer.ini" /opt/homebrew/etc/pgbouncer.ini

# Update paths for macOS
echo "Updating paths for macOS..."
sudo sed -i '' 's|logfile = /tmp/pgbouncer.log|logfile = /opt/homebrew/var/log/pgbouncer.log|' /opt/homebrew/etc/pgbouncer.ini
sudo sed -i '' 's|pidfile = /tmp/pgbouncer.pid|pidfile = /opt/homebrew/var/run/pgbouncer.pid|' /opt/homebrew/etc/pgbouncer.ini

# Verify auth_type
echo ""
echo "Verifying configuration..."
grep "auth_type" /opt/homebrew/etc/pgbouncer.ini

# Start PgBouncer
echo ""
echo "Starting PgBouncer..."
pgbouncer -d /opt/homebrew/etc/pgbouncer.ini

sleep 2
echo ""
echo "Checking if PgBouncer is running..."
if lsof -i :6432 > /dev/null 2>&1; then
    echo "✅ PgBouncer is running on port 6432"
    echo ""
    echo "Configuration updated! Now restart your Rails server."
else
    echo "❌ PgBouncer failed to start. Check logs:"
    echo "   tail -f /opt/homebrew/var/log/pgbouncer.log"
fi

