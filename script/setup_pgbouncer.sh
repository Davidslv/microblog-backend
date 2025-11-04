#!/bin/bash
# Setup script for PgBouncer
# Usage: ./script/setup_pgbouncer.sh

set -e

echo "Setting up PgBouncer..."

# Detect OS
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    PGBOUNCER_CONFIG="/usr/local/etc/pgbouncer.ini"
    INSTALL_CMD="brew install pgbouncer"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    # Linux
    PGBOUNCER_CONFIG="/etc/pgbouncer/pgbouncer.ini"
    INSTALL_CMD="sudo apt-get install pgbouncer"
else
    echo "Unsupported OS: $OSTYPE"
    exit 1
fi

# Check if PgBouncer is installed
if ! command -v pgbouncer &> /dev/null; then
    echo "PgBouncer not found. Installing..."
    echo "Run: $INSTALL_CMD"
    exit 1
fi

echo "PgBouncer is installed: $(pgbouncer --version)"

# Create config directory
if [[ "$OSTYPE" == "darwin"* ]]; then
    sudo mkdir -p /usr/local/etc
    sudo cp config/pgbouncer.ini /usr/local/etc/pgbouncer.ini
    echo "Configuration copied to $PGBOUNCER_CONFIG"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    sudo mkdir -p /etc/pgbouncer
    sudo cp config/pgbouncer.ini /etc/pgbouncer/pgbouncer.ini
    echo "Configuration copied to $PGBOUNCER_CONFIG"
fi

# Check if PostgreSQL is running
if ! pg_isready -h localhost -p 5432 &> /dev/null; then
    echo "Warning: PostgreSQL doesn't appear to be running on port 5432"
    echo "Start PostgreSQL before starting PgBouncer"
fi

echo ""
echo "Setup complete!"
echo ""
echo "To start PgBouncer:"
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "  pgbouncer -d /usr/local/etc/pgbouncer.ini"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    echo "  sudo systemctl start pgbouncer"
    echo "  sudo systemctl enable pgbouncer  # to start on boot"
fi
echo ""
echo "To use PgBouncer with Rails:"
echo "  export USE_PGBOUNCER=true"
echo "  rails server"
echo ""
echo "To verify PgBouncer is running:"
echo "  lsof -i :6432"
echo "  # or"
echo "  psql -h localhost -p 6432 -U postgres pgbouncer"

