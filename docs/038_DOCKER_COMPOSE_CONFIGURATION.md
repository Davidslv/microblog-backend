# Docker Compose Configuration Guide

This document explains the Docker Compose setup for horizontal scaling and the configuration fixes required to ensure proper database connectivity and container communication.

## Table of Contents

- [Overview](#overview)
- [Common Issues](#common-issues)
- [Database Connection Problems](#database-connection-problems)
- [Container Networking](#container-networking)
- [Environment Variables](#environment-variables)
- [Scaling Configuration](#scaling-configuration)
- [Troubleshooting](#troubleshooting)

## Overview

The `docker-compose.yml` file configures a multi-container setup for the microblog application with:

- **PostgreSQL database** (`db` service) - Shared database for all application instances
- **Rails application** (`web` service) - Scalable application instances
- **Traefik load balancer** (`traefik` service) - Automatic request distribution
- **Migration service** (`migrate` service) - One-time database setup

### Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Docker Network                       │
│              (microblog-network)                         │
│                                                          │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐        │
│  │  web-1   │    │  web-2   │    │  web-3   │        │
│  │ (Puma)   │    │ (Puma)   │    │ (Puma)   │        │
│  └────┬─────┘    └────┬─────┘    └────┬─────┘        │
│       │                │                │                │
│       └────────┬──────┴───────────────┘                │
│                │                                        │
│         ┌─────▼─────┐                                  │
│         │    db     │                                  │
│         │(PostgreSQL)│                                 │
│         └───────────┘                                  │
│                                                          │
│         ┌──────────┐                                   │
│         │ traefik  │                                   │
│         │(Load Bal)│                                   │
│         └──────────┘                                   │
└─────────────────────────────────────────────────────────┘
```

## Common Issues

### Issue 1: Database Connection Refused

**Symptoms:**
```
ActiveRecord::ConnectionNotEstablished (connection to server at "::1", port 5432 failed: Connection refused
        Is the server running on that host and accepting TCP/IP connections?
connection to server at "127.0.0.1", port 5432 failed: Connection refused
        Is the server running on that host and accepting TCP/IP connections?
)
```

**Root Cause:**
- Containers are trying to connect to `localhost` (127.0.0.1 or ::1) instead of the `db` service
- Docker Compose uses service names as DNS hostnames within the network
- Environment variables may not be properly configured or Rails may be using cached connection settings

**Solution:**
1. Ensure `DATABASE_HOST=db` is set in environment variables
2. Set `REPLICA_HOST=db` for read replica configuration
3. Configure explicit Docker network so containers can communicate
4. Use `DATABASE_URL` with the service name: `postgresql://user:pass@db:5432/database`

## Database Connection Problems

### Problem: Containers Connect to Localhost Instead of Service

When Rails tries to connect to the database, it may use `localhost` instead of the Docker service name `db`. This happens because:

1. **Default database.yml configuration**: Falls back to `localhost` if `DATABASE_HOST` is not set
2. **Rails read replica configuration**: The database selector middleware may try to use replica connections that also default to `localhost`
3. **Missing network configuration**: Containers may not be on the same Docker network

### Solution: Configure Environment Variables

**In `docker-compose.yml`:**

```yaml
web:
  environment:
    # Primary database connection
    DATABASE_URL: postgresql://${DATABASE_USERNAME:-postgres}:${DATABASE_PASSWORD:-postgres}@db:5432/microblog_development
    DATABASE_HOST: db
    DATABASE_PORT: 5432
    DATABASE_USERNAME: ${DATABASE_USERNAME:-postgres}
    DATABASE_PASSWORD: ${DATABASE_PASSWORD:-postgres}
    
    # Read replica configuration (in Docker, same as primary)
    REPLICA_HOST: db
    REPLICA_PORT: 5432
    
    # Solid Cache, Queue, and Cable databases
    CACHE_DB_HOST: db
    CACHE_DB_PORT: 5432
    QUEUE_DB_HOST: db
    QUEUE_DB_PORT: 5432
    CABLE_DB_HOST: db
    CABLE_DB_PORT: 5432
```

**Key Points:**
- Use `db` (the service name) instead of `localhost`
- `DATABASE_URL` takes precedence over `database.yml` in Rails
- Set `REPLICA_HOST` to `db` even if you're not using real replicas (Rails will use the same database)
- All Solid adapter databases should also point to `db`

### Problem: SECRET_KEY_BASE Error

**Symptoms:**
```
`secret_key_base` for development environment must be a type of String` (ArgumentError)
```

**Root Cause:**
- Setting `SECRET_KEY_BASE` to an empty string (`${SECRET_KEY_BASE:-}`) causes Rails to fail
- In development, Rails can auto-generate `SECRET_KEY_BASE` if it's not set

**Solution:**
- **Remove** the `SECRET_KEY_BASE` environment variable from development configuration
- Rails will automatically generate it if not provided
- Only set `SECRET_KEY_BASE` in production or when you have a specific value

```yaml
# ❌ Wrong - causes error
environment:
  SECRET_KEY_BASE: ${SECRET_KEY_BASE:-}

# ✅ Correct - let Rails auto-generate in development
environment:
  # SECRET_KEY_BASE is auto-generated in development if not set
  # Only set it explicitly for production
```

## Container Networking

### Docker Compose Networking

Docker Compose automatically creates a network for services defined in the same `docker-compose.yml` file. However, for reliability and clarity, it's recommended to explicitly define the network.

### Explicit Network Configuration

**In `docker-compose.yml`:**

```yaml
services:
  db:
    # ... other config ...
    networks:
      - microblog-network

  web:
    # ... other config ...
    networks:
      - microblog-network

  traefik:
    # ... other config ...
    networks:
      - microblog-network

# Define the network at the bottom
networks:
  microblog-network:
    driver: bridge
```

**Benefits:**
- **Explicit communication**: Containers can resolve service names via DNS
- **Isolation**: Containers on this network can only communicate with each other
- **Predictable**: No reliance on default network behavior
- **Scalability**: Works correctly when scaling services

### Service Name Resolution

Within the Docker network, containers can resolve service names to IP addresses:

- `db` → Resolves to the PostgreSQL container's IP
- `web-1`, `web-2`, `web-3` → Individual container hostnames when scaled
- `web` → Service name (used in depends_on, but not for direct connections)

**Important:** Always use the service name (`db`) for connections, not container names (`microblog-db-1`).

## Environment Variables

### Required Environment Variables

| Variable | Description | Example | Default |
|----------|-------------|---------|---------|
| `DATABASE_HOST` | Database service name | `db` | `localhost` |
| `DATABASE_PORT` | Database port | `5432` | `5432` |
| `DATABASE_USERNAME` | Database user | `postgres` | `postgres` |
| `DATABASE_PASSWORD` | Database password | `password` | `postgres` |
| `DATABASE_URL` | Full connection string | `postgresql://user:pass@db:5432/dbname` | Auto-generated |
| `REPLICA_HOST` | Read replica host | `db` | `localhost` |
| `REPLICA_PORT` | Read replica port | `5432` | `5432` |
| `CACHE_DB_HOST` | Solid Cache database host | `db` | `localhost` |
| `QUEUE_DB_HOST` | Solid Queue database host | `db` | `localhost` |
| `CABLE_DB_HOST` | Solid Cable database host | `db` | `localhost` |

### Environment Variable Precedence

Rails uses the following precedence for database configuration:

1. **`DATABASE_URL`** (highest priority) - If set, Rails uses this directly
2. **`database.yml`** - Reads from `config/database.yml` using ERB to substitute environment variables
3. **Defaults** - Falls back to `localhost` if environment variables are not set

### Using .env File (Optional)

You can create a `.env` file in the project root to set default values:

```bash
# .env
DATABASE_USERNAME=postgres
DATABASE_PASSWORD=your_password
CACHE_DB_PASSWORD=cache_password
QUEUE_DB_PASSWORD=queue_password
CABLE_DB_PASSWORD=cable_password
```

Docker Compose will automatically read `.env` file and use `${VARIABLE:-default}` syntax for fallbacks.

## Scaling Configuration

### Scaling Web Instances

To run multiple web containers:

```bash
docker compose up -d --scale web=3
```

This creates three web containers: `microblog-web-1`, `microblog-web-2`, `microblog-web-3`.

### Port Mapping

When scaling, Docker Compose automatically maps ports:

```yaml
ports:
  - "3000-3009:3000"  # Range for multiple instances
```

- `web-1` → `localhost:3000`
- `web-2` → `localhost:3001`
- `web-3` → `localhost:3002`
- etc.

The load balancer (Traefik) should handle routing to these instances.

### PID File Conflicts

**Problem:** When multiple containers share a volume, they may conflict on the PID file:

```
A server is already running (pid: 1, file: /rails/tmp/pids/server.pid).
```

**Solution:** Remove PID files before starting:

```yaml
command: sh -c "rm -f /rails/tmp/pids/server*.pid && bin/rails server -b 0.0.0.0 -p 3000"
```

**Alternative Solutions:**
1. Use unique PID file per container (requires Puma configuration)
2. Don't mount code as volume (each container has its own filesystem)
3. Use tmpfs for PID directory (not persistent across restarts)

### Health Checks

Each service should have a health check:

```yaml
web:
  healthcheck:
    test: ["CMD-SHELL", "curl -f http://localhost:3000/up || exit 1"]
    interval: 10s
    timeout: 5s
    retries: 3
    start_period: 40s
```

The `start_period` gives Rails time to boot before health checks begin.

### Database Dependencies

Use `depends_on` with health check condition:

```yaml
web:
  depends_on:
    db:
      condition: service_healthy
```

This ensures the database is ready before web containers start.

## Troubleshooting

### Container Can't Connect to Database

**Check 1: Verify environment variables**

```bash
docker compose exec web env | grep DATABASE
```

Expected output:
```
DATABASE_HOST=db
DATABASE_PORT=5432
DATABASE_URL=postgresql://postgres:postgres@db:5432/microblog_development
```

**Check 2: Verify network connectivity**

```bash
docker compose exec web ping -c 2 db
```

Should return successful ping responses.

**Check 3: Check database logs**

```bash
docker compose logs db
```

Look for connection attempts and any authentication errors.

**Check 4: Test database connection from container**

```bash
docker compose exec web bin/rails runner "puts ActiveRecord::Base.connection.execute('SELECT 1').first"
```

Should return `[1]` without errors.

### Container Exits Immediately

**Check logs:**

```bash
docker compose logs web --tail 50
```

Common issues:
- **SECRET_KEY_BASE error**: Remove empty `SECRET_KEY_BASE` from environment
- **PID file conflict**: Add PID file cleanup to command
- **Database connection failure**: Verify `DATABASE_HOST=db` is set
- **Missing dependencies**: Check `depends_on` and health check conditions

### Only One Container Running When Scaled

**Problem:** When scaling with `--scale web=3`, only one container stays up.

**Common Causes:**
1. **PID file conflicts**: Containers sharing volume interfere with each other
2. **Port conflicts**: Multiple containers trying to bind to same port (shouldn't happen with port ranges)
3. **Resource limits**: Container may be hitting memory/CPU limits

**Solution:**
- Remove PID files before starting: `rm -f /rails/tmp/pids/server*.pid`
- Check container logs: `docker compose logs web`
- Verify port mapping: `docker compose ps`

### Traefik Not Routing to All Instances

**Check Traefik dashboard:**

```bash
# Open in browser
http://localhost:8080
```

**Verify labels:**

```yaml
web:
  labels:
    - "traefik.enable=true"
    - "traefik.http.routers.web.rule=Host(`localhost`)"
    - "traefik.http.routers.web.entrypoints=web"
    - "traefik.http.services.web.loadbalancer.server.port=3000"
```

**Check Traefik logs:**

```bash
docker compose logs traefik
```

Look for service discovery messages and routing configuration.

## Complete Configuration Example

Here's a complete working `docker-compose.yml` configuration:

```yaml
services:
  # PostgreSQL database (shared across all app instances)
  db:
    image: postgres:16
    environment:
      POSTGRES_USER: ${DATABASE_USERNAME:-postgres}
      POSTGRES_PASSWORD: ${DATABASE_PASSWORD:-postgres}
      POSTGRES_DB: microblog_development
    ports:
      - "5432:5432"
    volumes:
      - pg_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${DATABASE_USERNAME:-postgres}"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - microblog-network

  # Application instances (scale with: docker compose up --scale web=3)
  web:
    build:
      context: .
      dockerfile: Dockerfile
    command: sh -c "rm -f /rails/tmp/pids/server*.pid && bin/rails server -b 0.0.0.0 -p 3000"
    environment:
      RAILS_ENV: development
      # Use db service name (Docker Compose DNS) instead of localhost
      DATABASE_URL: postgresql://${DATABASE_USERNAME:-postgres}:${DATABASE_PASSWORD:-postgres}@db:5432/microblog_development
      DATABASE_HOST: db
      DATABASE_PORT: 5432
      DATABASE_USERNAME: ${DATABASE_USERNAME:-postgres}
      DATABASE_PASSWORD: ${DATABASE_PASSWORD:-postgres}
      # Replica configuration (in Docker, same as primary since we're not using real replicas)
      REPLICA_HOST: db
      REPLICA_PORT: 5432
      # Cache, queue, and cable use same PostgreSQL instance for horizontal scaling
      CACHE_DB_HOST: db
      CACHE_DB_PORT: 5432
      CACHE_DB_USERNAME: ${CACHE_DB_USERNAME:-microblog_cache}
      CACHE_DB_PASSWORD: ${CACHE_DB_PASSWORD:-cache_password}
      QUEUE_DB_HOST: db
      QUEUE_DB_PORT: 5432
      QUEUE_DB_USERNAME: ${QUEUE_DB_USERNAME:-microblog_queue}
      QUEUE_DB_PASSWORD: ${QUEUE_DB_PASSWORD:-queue_password}
      CABLE_DB_HOST: db
      CABLE_DB_PORT: 5432
      CABLE_DB_USERNAME: ${CABLE_DB_USERNAME:-microblog_cable}
      CABLE_DB_PASSWORD: ${CABLE_DB_PASSWORD:-cable_password}
      # Enable Solid Queue workers in Puma (recommended for horizontal scaling)
      SOLID_QUEUE_IN_PUMA: "true"
    ports:
      - "3000-3009:3000"  # Range for multiple instances
    depends_on:
      db:
        condition: service_healthy
    volumes:
      - .:/rails
    networks:
      - microblog-network
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:3000/up || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 3
      start_period: 40s
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.web.rule=Host(`localhost`)"
      - "traefik.http.routers.web.entrypoints=web"
      - "traefik.http.services.web.loadbalancer.server.port=3000"

  # Load balancer (Traefik with auto-discovery)
  traefik:
    image: traefik:v2.10
    command:
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--entrypoints.web.address=:80"
      - "--api.dashboard=true"
      - "--api.insecure=true"
    ports:
      - "80:80"
      - "8080:8080"  # Traefik dashboard
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    depends_on:
      - web
    networks:
      - microblog-network
    labels:
      - "traefik.enable=true"

volumes:
  pg_data:

networks:
  microblog-network:
    driver: bridge
```

## Quick Start

1. **Start services:**

   ```bash
   docker compose up -d
   ```

2. **Scale web instances:**

   ```bash
   docker compose up -d --scale web=3
   ```

3. **Check status:**

   ```bash
   docker compose ps
   ```

4. **View logs:**

   ```bash
   docker compose logs -f web
   ```

5. **Access application:**

   - Main app: http://localhost (via Traefik)
   - Direct access: http://localhost:3000, http://localhost:3001, etc.
   - Traefik dashboard: http://localhost:8080

## Summary

Key configuration requirements for Docker Compose horizontal scaling:

1. ✅ **Use service names for connections**: Always use `db` instead of `localhost`
2. ✅ **Configure explicit network**: Define `microblog-network` for all services
3. ✅ **Set replica host**: Set `REPLICA_HOST=db` even if not using real replicas
4. ✅ **Remove SECRET_KEY_BASE in dev**: Let Rails auto-generate it
5. ✅ **Clean PID files**: Remove PID files before starting to avoid conflicts
6. ✅ **Use health checks**: Ensure database is ready before starting web containers
7. ✅ **Configure all databases**: Set `*_DB_HOST=db` for cache, queue, and cable

Following these guidelines ensures reliable database connectivity and proper container communication when scaling horizontally.

