# Horizontal Scaling Guide

This document explains how to scale the microblog application horizontally by running multiple application server instances behind a load balancer.

## Table of Contents

- [Overview](#overview)
- [Shared State Requirements](#shared-state-requirements)
- [Local Development Setup](#local-development-setup)
- [Production/Staging Setup](#productionstaging-setup)
- [Load Balancer Configuration](#load-balancer-configuration)
- [Health Checks](#health-checks)
- [Monitoring Considerations](#monitoring-considerations)
- [Troubleshooting](#troubleshooting)

## Overview

Horizontal scaling means running multiple instances of your Rails application simultaneously, with a load balancer distributing incoming requests across them. This allows you to:

- Handle more concurrent requests
- Improve availability (if one instance fails, others continue serving)
- Scale capacity by adding/removing instances dynamically

### Architecture

```
                    ┌─────────────┐
                    │   Client    │
                    └──────┬──────┘
                           │
                    ┌──────▼──────┐
                    │   Load      │
                    │  Balancer   │
                    │ (nginx/HAProxy) │
                    └──┬───────┬───┘
                       │       │
          ┌────────────┘       └────────────┐
          │                                │
    ┌─────▼─────┐                    ┌─────▼─────┐
    │  App      │                    │  App      │
    │ Instance 1│                    │ Instance 2│
    │ (Puma)    │                    │ (Puma)    │
    └─────┬─────┘                    └─────┬─────┘
          │                                │
          └────────────┬───────────────────┘
                       │
          ┌────────────▼───────────────────┐
          │     Shared PostgreSQL          │
          │  (Primary + Read Replicas)      │
          │  (Cache DB, Queue DB)           │
          └─────────────────────────────────┘
```

## Shared State Requirements

For horizontal scaling to work correctly, all application instances must share certain state:

### 1. Database (PostgreSQL)

**Status**: ✅ Already configured

- **Primary database**: All instances connect to the same PostgreSQL primary
- **Read replicas**: Configured via `database.yml` and `ApplicationRecord.connects_to`
- **Cache database**: Solid Cache uses a shared database (configured in `database.yml`)
- **Queue database**: Solid Queue uses a shared database (configured in `database.yml`)

**Configuration**: See `docs/034_READ_REPLICAS_SETUP.md` for read replica setup.

### 2. Cache (Solid Cache)

**Status**: ⚠️ **Requires configuration change for horizontal scaling**

**Current Setup**: The production configuration uses SQLite for cache:

```yaml
# config/database.yml (current)
production:
  cache:
    adapter: sqlite3
    database: storage/production_cache.sqlite3
```

**Problem**: SQLite files cannot be shared across multiple servers. Each instance would have its own cache, leading to cache inconsistencies.

**Solution**: Switch to PostgreSQL for cache in production:

```yaml
# config/database.yml (for horizontal scaling)
production:
  cache:
    adapter: postgresql
    database: microblog_cache  # Use a shared PostgreSQL database
    host: <%= ENV.fetch("CACHE_DB_HOST") { ENV.fetch("DATABASE_HOST") { "localhost" } } %>
    port: <%= ENV.fetch("CACHE_DB_PORT") { ENV.fetch("DATABASE_PORT") { 5432 } } %>
    username: <%= ENV.fetch("CACHE_DB_USERNAME") { ENV.fetch("DATABASE_USERNAME") } %>
    password: <%= ENV.fetch("CACHE_DB_PASSWORD") { ENV.fetch("DATABASE_PASSWORD") } %>
    pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
    migrations_paths: db/cache_migrate
```

**Migration Steps**:
1. Create the cache database: `createdb microblog_cache`
2. Run migrations: `RAILS_ENV=production bin/rails solid_cache:install`
3. Update `database.yml` as shown above
4. Restart all application instances

**Note**: For development, SQLite is fine since you're typically running a single instance.

### 3. Background Jobs (Solid Queue)

**Status**: ⚠️ **Requires configuration change for horizontal scaling**

**Current Setup**: The production configuration uses SQLite for queue:

```yaml
# config/database.yml (current)
production:
  queue:
    adapter: sqlite3
    database: storage/production_queue.sqlite3
```

**Problem**: SQLite files cannot be shared across multiple servers. Each instance would have its own job queue, preventing proper job distribution.

**Solution**: Switch to PostgreSQL for queue in production:

```yaml
# config/database.yml (for horizontal scaling)
production:
  queue:
    adapter: postgresql
    database: microblog_queue  # Use a shared PostgreSQL database
    host: <%= ENV.fetch("QUEUE_DB_HOST") { ENV.fetch("DATABASE_HOST") { "localhost" } } %>
    port: <%= ENV.fetch("QUEUE_DB_PORT") { ENV.fetch("DATABASE_PORT") { 5432 } } %>
    username: <%= ENV.fetch("QUEUE_DB_USERNAME") { ENV.fetch("DATABASE_USERNAME") } %>
    password: <%= ENV.fetch("QUEUE_DB_PASSWORD") { ENV.fetch("DATABASE_PASSWORD") } %>
    pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
    migrations_paths: db/queue_migrate
```

**Migration Steps**:
1. Create the queue database: `createdb microblog_queue`
2. Run migrations: `RAILS_ENV=production bin/rails solid_queue:install`
3. Update `database.yml` as shown above
4. Restart all application instances

**Worker Configuration**: 
- Option 1: Run workers in each app instance (via Puma plugin with `SOLID_QUEUE_IN_PUMA=true`)
- Option 2: Run dedicated worker processes (via `bin/jobs` on separate servers)

**Note**: For development, SQLite is fine since you're typically running a single instance.

### 4. Sessions

**Status**: ✅ Cookie-based (no shared storage needed)

The application uses cookie-based sessions (Rails default), which are stateless and work across multiple instances without additional configuration.

**Current setup**:
- Sessions stored in encrypted cookies
- No server-side session storage required
- Works automatically with horizontal scaling

### 5. Rate Limiting (Rack::Attack)

**Status**: ✅ Already configured for sharing

Rack::Attack uses `Rails.cache` (Solid Cache), so rate limiting works across all instances:

```ruby
# config/initializers/rack_attack.rb
Rack::Attack.cache.store = Rails.cache  # Uses Solid Cache (shared DB)
```
