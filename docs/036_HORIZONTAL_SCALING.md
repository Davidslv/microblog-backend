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

## Production/Staging Setup

### Prerequisites

1. **Multiple application servers** (VMs, containers, or Kubernetes pods)
2. **Load balancer** (nginx, HAProxy, AWS ALB, etc.)
3. **Shared PostgreSQL database** (primary + read replicas)
4. **Shared cache/queue databases** (or use the same PostgreSQL instance)

### Step 1: Database Configuration

Ensure all instances use the same database configuration:

```yaml
# config/database.yml
production:
  primary:
    <<: *default
    database: microblog_production
    host: <%= ENV.fetch("DATABASE_HOST") { "db-primary.example.com" } %>
    port: <%= ENV.fetch("DATABASE_PORT") { 5432 } %>

  primary_replica:
    <<: *default
    database: microblog_production
    host: <%= ENV.fetch("REPLICA_HOST") { "db-replica.example.com" } %>
    port: <%= ENV.fetch("REPLICA_PORT") { 5432 } %>
    replica: true

  cache:
    adapter: postgresql  # Use PostgreSQL, not SQLite!
    database: microblog_cache
    host: <%= ENV.fetch("CACHE_DB_HOST") { ENV.fetch("DATABASE_HOST") { "db-primary.example.com" } } %>
    port: <%= ENV.fetch("CACHE_DB_PORT") { ENV.fetch("DATABASE_PORT") { 5432 } } %>
    username: <%= ENV.fetch("CACHE_DB_USERNAME") { ENV.fetch("DATABASE_USERNAME") } %>
    password: <%= ENV.fetch("CACHE_DB_PASSWORD") { ENV.fetch("DATABASE_PASSWORD") } %>

  queue:
    adapter: postgresql  # Use PostgreSQL, not SQLite!
    database: microblog_queue
    host: <%= ENV.fetch("QUEUE_DB_HOST") { ENV.fetch("DATABASE_HOST") { "db-primary.example.com" } } %>
    port: <%= ENV.fetch("QUEUE_DB_PORT") { ENV.fetch("DATABASE_PORT") { 5432 } } %>
    username: <%= ENV.fetch("QUEUE_DB_USERNAME") { ENV.fetch("DATABASE_USERNAME") } %>
    password: <%= ENV.fetch("QUEUE_DB_PASSWORD") { ENV.fetch("DATABASE_PASSWORD") } %>
```

**CRITICAL**: The current `database.yml` uses SQLite for cache and queue in production. **You must switch to PostgreSQL before scaling horizontally**, as SQLite files cannot be shared across multiple servers. See the [Shared State Requirements](#shared-state-requirements) section above for the exact configuration changes needed.

### Step 2: Environment Variables

Set these environment variables on each application server:

```bash
# Database
DATABASE_HOST=db-primary.example.com
DATABASE_PORT=5432
DATABASE_USERNAME=microblog
DATABASE_PASSWORD=secure_password

# Read Replica
REPLICA_HOST=db-replica.example.com
REPLICA_PORT=5432
REPLICA_USERNAME=microblog
REPLICA_PASSWORD=secure_password

# Cache Database (can be same as primary)
CACHE_DB_HOST=db-primary.example.com
CACHE_DB_PORT=5432

# Queue Database (can be same as primary)
QUEUE_DB_HOST=db-primary.example.com
QUEUE_DB_PORT=5432

# Application
RAILS_ENV=production
RAILS_MASTER_KEY=your_master_key
SECRET_KEY_BASE=your_secret_key_base

# Solid Queue (if using Puma plugin)
SOLID_QUEUE_IN_PUMA=true
```

### Step 3: Load Balancer Configuration

#### Option A: nginx (Recommended for self-hosted)

```nginx
# /etc/nginx/sites-available/microblog
upstream microblog_app {
    # Least connections balancing
    least_conn;
    
    # Application servers
    server app1.example.com:3000 max_fails=3 fail_timeout=30s;
    server app2.example.com:3000 max_fails=3 fail_timeout=30s;
    server app3.example.com:3000 max_fails=3 fail_timeout=30s;
    
    # Enable keepalive connections
    keepalive 32;
}

server {
    listen 80;
    listen [::]:80;
    server_name microblog.example.com;

    # Redirect HTTP to HTTPS
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name microblog.example.com;

    # SSL certificates (use Let's Encrypt or your CA)
    ssl_certificate /etc/letsencrypt/live/microblog.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/microblog.example.com/privkey.pem;

    # SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    # Logging
    access_log /var/log/nginx/microblog_access.log;
    error_log /var/log/nginx/microblog_error.log;

    # Client body size (for file uploads)
    client_max_body_size 10M;

    # Health check endpoint (bypass load balancing)
    location /up {
        proxy_pass http://microblog_app;
        access_log off;
    }

    # Main application
    location / {
        proxy_pass http://microblog_app;
        proxy_http_version 1.1;
        
        # Headers
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Port $server_port;
        
        # Connection settings
        proxy_set_header Connection "";
        proxy_buffering off;
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # Disable buffering for streaming responses
        proxy_buffering off;
    }

    # Static assets (optional - serve directly from nginx)
    location /assets {
        alias /var/www/microblog/public/assets;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
```

Enable the site:

```bash
sudo ln -s /etc/nginx/sites-available/microblog /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

#### Option B: HAProxy

```haproxy
# /etc/haproxy/haproxy.cfg
global
    log /dev/log local0
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

defaults
    mode http
    log global
    option httplog
    option dontlognull
    timeout connect 5000ms
    timeout client 50000ms
    timeout server 50000ms
    option forwardfor
    option http-server-close

frontend http_front
    bind *:80
    redirect scheme https code 301 if !{ ssl_fc }

frontend https_front
    bind *:443 ssl crt /etc/ssl/certs/microblog.pem
    default_backend microblog_backend

backend microblog_backend
    balance leastconn
    option httpchk GET /up
    
    server app1 app1.example.com:3000 check inter 5s fall 3 rise 2
    server app2 app2.example.com:3000 check inter 5s fall 3 rise 2
    server app3 app3.example.com:3000 check inter 5s fall 3 rise 2
```

#### Option C: AWS Application Load Balancer (ALB)

If using AWS, configure an ALB:

1. **Target Group**: Create a target group with health check path `/up`
2. **Targets**: Register your EC2 instances or ECS tasks
3. **Listener**: Configure HTTPS listener (port 443) with SSL certificate
4. **Rules**: Set default action to forward to target group

**Health Check Configuration**:
- Path: `/up`
- Interval: 30 seconds
- Timeout: 5 seconds
- Healthy threshold: 2
- Unhealthy threshold: 3

### Step 4: Worker Configuration

You have two options for background job processing:

#### Option 1: Workers in Each App Instance (Recommended)

Run Solid Queue workers inside each Puma process using the Puma plugin:

```bash
# Set environment variable on each app server
SOLID_QUEUE_IN_PUMA=true

# Start Puma (workers run automatically)
bin/rails server
```

**Pros**: Simpler deployment, no separate worker processes
**Cons**: Workers compete with web requests for resources

#### Option 2: Dedicated Worker Servers

Run dedicated worker processes on separate servers:

```bash
# On worker servers
bin/jobs
```

**Pros**: Isolated resources, better for CPU-intensive jobs
**Cons**: More servers to manage, separate deployment

**Note**: Due to the `bin/jobs` segfault issue with read replicas (see `docs/035_BIN_JOBS_SEGFAULT_ISSUE.md`), Option 1 is recommended for now.

### Step 5: Deploy to Multiple Instances

Deploy your application to each server using your preferred method:

- **Capistrano**: Configure multiple servers in `config/deploy/production.rb`
- **Docker**: Use Docker Swarm or Kubernetes to deploy multiple containers
- **Manual**: Deploy to each server individually

Ensure all instances:
- Use the same codebase version
- Have the same environment variables
- Connect to the same shared databases
- Run database migrations (or run on one instance only)

## Load Balancer Configuration

### Load Balancing Algorithms

Choose based on your needs:

1. **Least Connections** (recommended): Routes to instance with fewest active connections
   ```nginx
   least_conn;
   ```

2. **Round Robin** (default): Routes requests in rotation
   ```nginx
   # default behavior
   ```

3. **IP Hash**: Routes same IP to same instance (sticky sessions)
   ```nginx
   ip_hash;
   ```

4. **Weighted**: Routes more traffic to certain instances
   ```nginx
   server app1:3000 weight=3;
   server app2:3000 weight=1;
   ```

### Sticky Sessions

**Not Required**: This application uses cookie-based sessions, so sticky sessions are not necessary. However, if you want to ensure session affinity (e.g., for WebSocket connections), you can use IP hash:

```nginx
upstream microblog_app {
    ip_hash;  # Same IP always goes to same server
    server app1:3000;
    server app2:3000;
    server app3:3000;
}
```

## Health Checks

Rails provides a built-in health check endpoint at `/up`. Configure your load balancer to use it:

### nginx

```nginx
location /up {
    proxy_pass http://microblog_app;
    access_log off;
}
```

### HAProxy

```haproxy
option httpchk GET /up
```

### Health Check Behavior

The `/up` endpoint checks:
- Database connectivity
- Application boot status

If health check fails, the load balancer should remove the instance from rotation.

## Monitoring Considerations

When running multiple instances, consider:

1. **Application Logs**: Aggregate logs from all instances (use centralized logging like ELK, Splunk, or CloudWatch)
2. **Metrics**: Monitor each instance separately (CPU, memory, request rate)
3. **Database Connections**: Monitor total connections across all instances
4. **Cache Hit Rate**: Monitor Solid Cache performance
5. **Job Queue Depth**: Monitor Solid Queue job processing

### Recommended Tools

- **Application Performance Monitoring**: New Relic, Datadog, Scout
- **Log Aggregation**: ELK Stack, Splunk, Papertrail
- **Metrics**: Prometheus + Grafana
- **Uptime Monitoring**: Pingdom, UptimeRobot

## Troubleshooting

### Issue: Sessions Not Working Across Instances

**Symptom**: Users get logged out when requests hit different instances

**Solution**: This shouldn't happen with cookie-based sessions. Check:
- Session secret key is the same on all instances (`SECRET_KEY_BASE`)
- Cookies are being set correctly (check `config.action_dispatch.cookies`)
- Load balancer is not stripping cookies

### Issue: Cache Inconsistency

**Symptom**: Different instances see different cached data

**Solution**: 
- Ensure all instances use the same cache database
- For SQLite, switch to PostgreSQL in production
- Check cache database connection settings

### Issue: Jobs Not Processing

**Symptom**: Background jobs are enqueued but not processed

**Solution**:
- Check if workers are running (`SOLID_QUEUE_IN_PUMA=true` or `bin/jobs`)
- Verify all instances connect to the same queue database
- Check worker logs for errors

### Issue: Rate Limiting Not Working

**Symptom**: Rate limits are per-instance, not global

**Solution**:
- Verify `Rack::Attack.cache.store = Rails.cache` is set
- Ensure all instances use the same cache database
- Check cache connection is working

### Issue: Database Connection Pool Exhaustion

**Symptom**: `ActiveRecord::ConnectionTimeoutError`

**Solution**:
- Increase `pool` size in `database.yml` (but be careful - total connections = pool_size × instances)
- Monitor total database connections: `SELECT count(*) FROM pg_stat_activity;`
- Consider using PgBouncer for connection pooling (not currently configured)

### Issue: Read Replica Lag

**Symptom**: Users see stale data after writes

**Solution**:
- Check replication lag: `SELECT * FROM pg_stat_replication;`
- Increase `database_selector.delay` in `config/application.rb` if needed
- Monitor replica lag metrics

## Summary

This application is mostly ready for horizontal scaling, but requires one critical configuration change:

✅ **Shared Database**: PostgreSQL primary and read replicas already configured
✅ **Stateless Sessions**: Cookie-based sessions work across instances
✅ **Shared Rate Limiting**: Rack::Attack uses shared cache (will work once cache DB is shared)
⚠️ **Cache & Queue**: Currently use SQLite - **must switch to PostgreSQL** for horizontal scaling
✅ **Read Replicas**: Already configured for read scaling

**To scale horizontally**:
1. **CRITICAL**: Switch cache and queue from SQLite to PostgreSQL (see [Shared State Requirements](#shared-state-requirements))
2. Deploy to multiple servers
3. Configure a load balancer (nginx, HAProxy, or cloud LB)
4. Ensure all instances use the same database configuration
5. Monitor and adjust as needed

**Next Steps**:
1. Update `database.yml` to use PostgreSQL for cache and queue in production
2. Run migrations on the new PostgreSQL databases
3. Set up load balancer in staging first
4. Test with 2-3 instances
5. Monitor performance and adjust
6. Scale to production gradually
