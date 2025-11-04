#!/bin/bash
# Setup script for pg_stat_statements
# This script helps configure PostgreSQL to load pg_stat_statements

set -e

echo "Setting up pg_stat_statements..."
echo ""

# Find PostgreSQL config file
echo "Finding PostgreSQL configuration file..."
CONFIG_FILE=$(psql -h localhost -U "$USER" -d postgres -t -c "SHOW config_file;" 2>/dev/null | xargs)

if [ -z "$CONFIG_FILE" ] || [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ Could not find PostgreSQL config file"
    echo ""
    echo "Please find it manually:"
    echo "  psql -h localhost -U $USER -d postgres -c \"SHOW config_file;\""
    exit 1
fi

echo "✅ Found config file: $CONFIG_FILE"
echo ""

# Check if pg_stat_statements is already in shared_preload_libraries
if grep -q "shared_preload_libraries.*pg_stat_statements" "$CONFIG_FILE" 2>/dev/null; then
    echo "✅ pg_stat_statements is already in shared_preload_libraries"
else
    echo "⚠️  pg_stat_statements is NOT in shared_preload_libraries"
    echo ""
    echo "You need to add it manually:"
    echo ""
    echo "1. Edit: $CONFIG_FILE"
    echo ""
    echo "2. Find or add this line:"
    echo "   shared_preload_libraries = 'pg_stat_statements'"
    echo ""
    echo "   If shared_preload_libraries already exists, add pg_stat_statements to the list:"
    echo "   shared_preload_libraries = 'existing_lib,pg_stat_statements'"
    echo ""
    echo "3. Optionally add these settings:"
    echo "   pg_stat_statements.max = 10000"
    echo "   pg_stat_statements.track = all"
    echo ""
    echo "4. Restart PostgreSQL:"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "   brew services restart postgresql@16"
    else
        echo "   sudo systemctl restart postgresql"
    fi
    echo ""
    echo "5. Then run the migration:"
    echo "   rails db:migrate"
    echo ""
    exit 1
fi

# Check if pg_stat_statements settings exist
if ! grep -q "pg_stat_statements.max" "$CONFIG_FILE" 2>/dev/null; then
    echo ""
    echo "💡 Optional: You can add these settings for better monitoring:"
    echo "   pg_stat_statements.max = 10000"
    echo "   pg_stat_statements.track = all"
    echo ""
fi

# Check if extension is enabled in database
echo "Checking if extension is enabled in database..."
if psql -h localhost -U "$USER" -d microblog_development -t -c "SELECT 1 FROM pg_extension WHERE extname = 'pg_stat_statements';" 2>/dev/null | grep -q 1; then
    echo "✅ Extension is enabled in microblog_development"
else
    echo "⚠️  Extension is not enabled. Run: rails db:migrate"
fi

echo ""
echo "Setup complete!"
echo ""
echo "To use pg_stat_statements:"
echo "  rake db:stats:summary"
echo "  rake db:stats:slow_queries"

