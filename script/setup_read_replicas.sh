#!/bin/bash

# Setup script for PostgreSQL read replicas
# This script configures the primary database for replication
# See docs/034_READ_REPLICAS_SETUP.md for detailed instructions

set -e

echo "=========================================="
echo "PostgreSQL Read Replicas Setup"
echo "=========================================="
echo ""

# Detect PostgreSQL configuration location
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS (Homebrew)
    PG_VERSION=$(psql --version | grep -oE '[0-9]+' | head -1)
    PG_DATA_DIR="/opt/homebrew/var/postgresql@${PG_VERSION}"
    PG_CONF="${PG_DATA_DIR}/postgresql.conf"
    PG_HBA="${PG_DATA_DIR}/pg_hba.conf"
    PG_USER=$(whoami)
else
    # Linux
    PG_VERSION=$(psql --version | grep -oE '[0-9]+' | head -1)
    PG_DATA_DIR="/var/lib/postgresql/${PG_VERSION}/main"
    PG_CONF="/etc/postgresql/${PG_VERSION}/main/postgresql.conf"
    PG_HBA="/etc/postgresql/${PG_VERSION}/main/pg_hba.conf"
    PG_USER="postgres"
fi

echo "Detected PostgreSQL version: ${PG_VERSION}"
echo "Configuration file: ${PG_CONF}"
echo ""

# Check if PostgreSQL is running
if ! pg_isready -q; then
    echo "❌ PostgreSQL is not running. Please start PostgreSQL first."
    echo ""
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "Start with: brew services start postgresql@${PG_VERSION}"
    else
        echo "Start with: sudo systemctl start postgresql"
    fi
    exit 1
fi

echo "✅ PostgreSQL is running"
echo ""

# Step 1: Configure postgresql.conf
echo "Step 1: Configuring postgresql.conf for replication..."
echo ""

if [[ ! -f "$PG_CONF" ]]; then
    echo "❌ Configuration file not found: ${PG_CONF}"
    echo "Please run: psql -U postgres -c 'SHOW config_file;' to find the correct path"
    exit 1
fi

# Backup original config
if [[ ! -f "${PG_CONF}.backup" ]]; then
    cp "$PG_CONF" "${PG_CONF}.backup"
    echo "✅ Backed up original config to ${PG_CONF}.backup"
fi

# Check current settings
echo "Current WAL level:"
psql -U postgres -t -c "SHOW wal_level;" | xargs

echo ""
echo "Updating postgresql.conf..."
echo ""

# Update wal_level (requires restart)
if grep -q "^wal_level" "$PG_CONF"; then
    sed -i.bak 's/^wal_level.*/wal_level = replica/' "$PG_CONF"
else
    echo "wal_level = replica" >> "$PG_CONF"
fi

# Update max_wal_senders
if grep -q "^max_wal_senders" "$PG_CONF"; then
    sed -i.bak 's/^max_wal_senders.*/max_wal_senders = 3/' "$PG_CONF"
else
    echo "max_wal_senders = 3" >> "$PG_CONF"
fi

# Update max_replication_slots
if grep -q "^max_replication_slots" "$PG_CONF"; then
    sed -i.bak 's/^max_replication_slots.*/max_replication_slots = 3/' "$PG_CONF"
else
    echo "max_replication_slots = 3" >> "$PG_CONF"
fi

echo "✅ Updated postgresql.conf"
echo ""
echo "⚠️  IMPORTANT: PostgreSQL must be restarted for these changes to take effect."
echo ""

# Step 2: Create replication user
echo "Step 2: Creating replication user..."
echo ""

# Check if replicator user exists
if psql -U postgres -t -c "SELECT 1 FROM pg_user WHERE usename='replicator';" | grep -q 1; then
    echo "✅ Replication user 'replicator' already exists"
else
    echo "Creating replication user..."
    read -sp "Enter password for replicator user: " REPLICA_PASSWORD
    echo ""

    psql -U postgres <<EOF
CREATE USER replicator WITH REPLICATION PASSWORD '${REPLICA_PASSWORD}';
GRANT CONNECT ON DATABASE microblog_development TO replicator;
GRANT CONNECT ON DATABASE microblog_production TO replicator;
EOF

    echo "✅ Created replication user 'replicator'"
fi

echo ""

# Step 3: Configure pg_hba.conf
echo "Step 3: Configuring pg_hba.conf for replication..."
echo ""

if [[ ! -f "$PG_HBA" ]]; then
    echo "❌ pg_hba.conf not found: ${PG_HBA}"
    exit 1
fi

# Backup original
if [[ ! -f "${PG_HBA}.backup" ]]; then
    cp "$PG_HBA" "${PG_HBA}.backup"
    echo "✅ Backed up original pg_hba.conf"
fi

# Check if replication entry exists
if grep -q "host replication replicator" "$PG_HBA"; then
    echo "✅ Replication entry already exists in pg_hba.conf"
else
    echo "Adding replication entry to pg_hba.conf..."
    echo "" >> "$PG_HBA"
    echo "# Replication for read replicas" >> "$PG_HBA"
    echo "host replication replicator 127.0.0.1/32 md5" >> "$PG_HBA"
    echo "✅ Added replication entry"
fi

echo ""

# Step 4: Reload PostgreSQL configuration
echo "Step 4: Reloading PostgreSQL configuration..."
echo ""

if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS - reload config
    psql -U postgres -c "SELECT pg_reload_conf();" > /dev/null
    echo "✅ Reloaded PostgreSQL configuration"
    echo ""
    echo "⚠️  Note: Some changes (wal_level) require a full restart:"
    echo "   brew services restart postgresql@${PG_VERSION}"
else
    # Linux - reload config
    sudo systemctl reload postgresql
    echo "✅ Reloaded PostgreSQL configuration"
    echo ""
    echo "⚠️  Note: Some changes (wal_level) require a full restart:"
    echo "   sudo systemctl restart postgresql"
fi

echo ""

# Step 5: Verify configuration
echo "Step 5: Verifying configuration..."
echo ""

echo "WAL level:"
psql -U postgres -t -c "SHOW wal_level;" | xargs

echo ""
echo "Max WAL senders:"
psql -U postgres -t -c "SHOW max_wal_senders;" | xargs

echo ""
echo "Max replication slots:"
psql -U postgres -t -c "SHOW max_replication_slots;" | xargs

echo ""
echo "Replication user:"
psql -U postgres -t -c "SELECT usename, userepl FROM pg_user WHERE usename='replicator';"

echo ""
echo "=========================================="
echo "✅ Setup complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Restart PostgreSQL if wal_level was changed"
echo "2. Configure Rails application (see docs/034_READ_REPLICAS_SETUP.md)"
echo "3. For production, setup replica server (see documentation)"
echo ""
echo "For development, Rails will use the same database for primary and replica."
echo "This allows testing the read/write routing without actual replication."

