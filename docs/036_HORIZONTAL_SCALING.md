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

## Local Development Setup

While you can't fully replicate production horizontal scaling locally, you can simulate it using Docker Compose or by running multiple Puma instances.

### Option 1: Docker Compose (Recommended)

Create a `docker-compose.yml` to run multiple app instances behind nginx:

```yaml
# docker-compose.yml
version: '3.8'

services:
  postgres:
    image: postgres:16
    environment:
      POSTGRES_DB: microblog_development
      POSTGRES_USER: ${DATABASE_USERNAME:-postgres}
      POSTGRES_PASSWORD: ${DATABASE_PASSWORD:-}
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data

  app1:
    build: .
    command: bin/rails server -b 0.0.0.0 -p 3000
    environment:
      DATABASE_URL: postgresql://postgres:password@postgres:5432/microblog_development
      RAILS_ENV: development
    volumes:
      - .:/app
    depends_on:
      - postgres

  app2:
    build: .
    command: bin/rails server -b 0.0.0.0 -p 3001
    environment:
      DATABASE_URL: postgresql://postgres:password@postgres:5432/microblog_development
      RAILS_ENV: development
    volumes:
      - .:/app
    depends_on:
      - postgres

  nginx:
    image: nginx:alpine
    ports:
      - "8080:80"
    volumes:
      - ./config/nginx.conf:/etc/nginx/nginx.conf:ro
    depends_on:
      - app1
      - app2

volumes:
  postgres_data:
```

Create `config/nginx.conf`:

```nginx
upstream app {
    least_conn;
    server app1:3000;
    server app2:3001;
}

server {
    listen 80;
    
    location / {
        proxy_pass http://app;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

**Note**: This is complex for local development. Consider Option 2 for simplicity.

### Option 2: Multiple Puma Instances (Simpler)

Run multiple Puma instances on different ports and use nginx locally:

1. **Start multiple Puma instances**:

```bash
# Terminal 1
PORT=3000 bin/rails server

# Terminal 2
PORT=3001 bin/rails server

# Terminal 3
PORT=3002 bin/rails server
```

2. **Install and configure nginx locally**:

```bash
# macOS
brew install nginx

# Create /usr/local/etc/nginx/servers/microblog.conf
```

```nginx
upstream microblog {
    least_conn;
    server localhost:3000;
    server localhost:3001;
    server localhost:3002;
}

server {
    listen 8080;
    server_name localhost;
    
    location / {
        proxy_pass http://microblog;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

3. **Start nginx**:

```bash
sudo nginx
# or
sudo brew services start nginx
```

4. **Access via nginx**: `http://localhost:8080`

### Option 3: Foreman with Multiple Processes

Create `Procfile.scale`:

```
web1: PORT=3000 bin/rails server
web2: PORT=3001 bin/rails server
web3: PORT=3002 bin/rails server
```

Run with:

```bash
foreman start -f Procfile.scale
```

**Note**: This runs multiple instances but doesn't include a load balancer. You'd need to manually test different ports or add nginx.
