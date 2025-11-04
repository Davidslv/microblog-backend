# bin/jobs Segmentation Fault Issue

## Overview

When running `bin/jobs` in development with read replicas configured, the process crashes with a segmentation fault during Rails boot. This is a known incompatibility between Ruby 3.4.7 (PRISM) and the `pg` gem when multiple database connections are configured.

## Error Symptoms

```
[BUG] Segmentation fault at 0x0000000122dc08f7
ruby 3.4.7 (2025-10-08 revision 7a5688e2a2) +PRISM [arm64-darwin25]
```

The crash occurs in the `pg` gem when trying to establish database connections during Rails environment initialization, specifically when `ApplicationRecord.connects_to` is evaluated with read replica configuration.

## Root Cause

1. **Ruby 3.4.7 (PRISM)**: This version of Ruby uses the PRISM parser, which has known compatibility issues with certain native extensions.

2. **pg gem incompatibility**: The `pg` gem (PostgreSQL adapter) has issues establishing multiple database connections (primary + replica) during Rails boot when using PRISM.

3. **Read replica configuration**: The `connects_to database: { writing: :primary, reading: :primary_replica }` in `ApplicationRecord` triggers connection establishment during class loading, which causes the segfault.

4. **CLI context**: Unlike web requests, CLI tools like `bin/jobs` don't have request context, so the database selector middleware can't properly route connections, causing initialization issues.

## Workaround: Use Puma Plugin Instead

Since `bin/jobs` cannot be used reliably with read replicas in development, use the Puma plugin approach instead:

### Development Setup

1. **Set environment variable**:
   ```bash
   export SOLID_QUEUE_IN_PUMA=true
   ```

2. **Run the development server**:
   ```bash
   bin/dev
   ```

   Or:
   ```bash
   SOLID_QUEUE_IN_PUMA=true bin/dev
   ```

3. **The `Procfile.dev` already includes** `OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES` to handle macOS fork safety warnings.

### Why This Works

- The Puma plugin initializes Solid Queue within the web server process, which has proper request context
- Database connections are established in a different context (web request handling) rather than during CLI boot
- The fork safety issue is handled by the environment variable in `Procfile.dev`

## Configuration Files

### Procfile.dev
```yaml
web: OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES bin/rails server
css: bin/rails tailwindcss:watch
```

### config/puma.rb
```ruby
# Run the Solid Queue supervisor inside of Puma for single-server deployments.
plugin :solid_queue if ENV["SOLID_QUEUE_IN_PUMA"]
```

### bin/jobs
```ruby
#!/usr/bin/env ruby

# Set environment variable for Solid Queue worker
# This enables eager loading and ensures proper connection setup
ENV["SOLID_QUEUE_WORKER"] = "true"

require_relative "../config/environment"
require "solid_queue/cli"

SolidQueue::Cli.start(ARGV)
```

## Current Status

- ✅ **Puma plugin approach**: Works correctly with `SOLID_QUEUE_IN_PUMA=true`
- ❌ **bin/jobs command**: Segfaults when read replicas are configured
- ✅ **macOS fork safety**: Fixed in `Procfile.dev`

## Future Solutions

1. **Upgrade Ruby**: Wait for Ruby 3.5+ or use Ruby 3.3.x (non-PRISM) which doesn't have this issue
2. **pg gem update**: Wait for a `pg` gem version that fully supports Ruby 3.4.7 PRISM
3. **Temporary workaround**: Disable read replicas in development if `bin/jobs` is required (not recommended as it diverges from production setup)

## Related Documentation

- `docs/026_SOLID_QUEUE_SETUP.md` - Solid Queue setup and configuration
- `docs/034_READ_REPLICAS_SETUP.md` - Read replicas configuration
- `README.md` - Project setup and running instructions

## Testing

To verify Solid Queue is working:

1. Start the server with `SOLID_QUEUE_IN_PUMA=true bin/dev`
2. Check logs for Solid Queue initialization messages
3. Enqueue a test job and verify it's processed
4. Access Mission Control Jobs UI at `/jobs` (if configured)

## Notes

- The `bin/jobs` command may work in production environments where read replicas are properly configured and Ruby version compatibility is different
- For development, always use the Puma plugin approach (`SOLID_QUEUE_IN_PUMA=true`)
- The `SOLID_QUEUE_WORKER=true` environment variable in `bin/jobs` enables eager loading, but this doesn't resolve the segfault issue

