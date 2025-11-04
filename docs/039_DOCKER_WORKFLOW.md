# Docker Workflow Guide

This guide explains how to work with Docker containers for the microblog application, including running scripts, accessing containers, and common development tasks.

## Table of Contents

- [Overview](#overview)
- [Getting Started](#getting-started)
- [Running Scripts in Containers](#running-scripts-in-containers)
- [Accessing Containers](#accessing-containers)
- [Common Development Tasks](#common-development-tasks)
- [Troubleshooting](#troubleshooting)
- [Best Practices](#best-practices)

## Overview

When running the application with Docker Compose, the code runs inside Docker containers. This means you need to execute commands inside these containers rather than directly on your host machine.

### Why Docker?

- **Consistency**: Same environment across all developers
- **Isolation**: Dependencies don't conflict with your local system
- **Scalability**: Easy to run multiple instances for testing
- **Production-like**: Matches production environment more closely

### Container Architecture

```
┌─────────────────────────────────────────┐
│         Your Computer (Host)            │
│                                          │
│  ┌──────────────────────────────────┐  │
│  │      Docker Container              │  │
│  │  ┌──────────────────────────────┐  │  │
│  │  │   Rails Application          │  │  │
│  │  │   - Ruby 3.4                 │  │  │
│  │  │   - Rails 8.1                │  │  │
│  │  │   - PostgreSQL client        │  │  │
│  │  │   - All dependencies         │  │  │
│  │  └──────────────────────────────┘  │  │
│  └──────────────────────────────────┘  │
│                                          │
│  Commands run INSIDE the container      │
└─────────────────────────────────────────┘
```

## Getting Started

### Prerequisites

- **Docker Desktop** (macOS/Windows) or **Docker Engine** (Linux)
- **Docker Compose** (usually included with Docker Desktop)

### Check Docker Installation

```bash
# Verify Docker is installed
docker --version

# Verify Docker Compose is installed
docker compose version

# Check if Docker is running
docker ps
```

### Start Services

```bash
# Start all services (database, web, traefik)
docker compose up -d

# Start with multiple web instances (for scaling)
docker compose up -d --scale web=3

# View running containers
docker compose ps
```

### Stop Services

```bash
# Stop all services
docker compose down

# Stop but keep volumes (database data persists)
docker compose stop

# Stop and remove volumes (⚠️ deletes database data)
docker compose down -v
```

## Running Scripts in Containers

### Understanding Container Names

When you run `docker compose up`, containers are created with names like:
- `microblog-web-1` - First web container
- `microblog-web-2` - Second web container (if scaled)
- `microblog-db-1` - Database container
- `microblog-traefik-1` - Load balancer container

### Method 1: Execute Commands Directly (Recommended)

Use `docker compose exec` to run commands in a running container:

```bash
# Basic syntax
docker compose exec <service-name> <command>

# Run a Rails script
docker compose exec web-1 bin/rails runner script/load_test_seed.rb

# Run with environment variables
docker compose exec web-1 bash -c "NUM_USERS=1000 bin/rails runner script/load_test_seed.rb"
```

**Real Examples:**

```bash
# Run load test seeding script
docker compose exec web-1 bin/rails runner script/load_test_seed.rb

# Run database migration
docker compose exec web-1 bin/rails db:migrate

# Check database connection
docker compose exec web-1 bin/rails runner "puts User.count"

# Run a specific script with parameters
docker compose exec web-1 bin/rails runner script/add_15k_users.rb
```

### Method 2: Interactive Shell

Get an interactive shell inside the container:

```bash
# Get bash shell
docker compose exec web-1 bash

# Once inside, you can run commands normally:
# bin/rails runner script/load_test_seed.rb
# bin/rails console
# ls -la /rails/script
# exit
```

**When to use interactive shell:**
- Running multiple commands
- Exploring the container filesystem
- Debugging issues
- Running complex sequences of commands

### Method 3: Rails Console

Access Rails console directly:

```bash
# Open Rails console
docker compose exec web-1 bin/rails console

# Or shorter version
docker compose exec web-1 bin/rails c

# Once inside console:
# > User.count
# > Post.create!(author: User.first, content: "Hello!")
# > exit
```

### Method 4: Using Service Name (Auto-selects Container)

If you have only one web container or want Docker Compose to pick one:

```bash
# Uses the service name 'web' - Docker Compose picks a container
docker compose exec web bin/rails runner script/load_test_seed.rb
```

**Note:** This works best when you have exactly one running container. If scaled to multiple, use specific container names.

## Accessing Containers

### List Running Containers

```bash
# List all containers
docker compose ps

# List only web containers
docker compose ps web

# List all containers (including stopped)
docker compose ps -a
```

### View Container Logs

```bash
# View logs for all web containers
docker compose logs web

# View logs for specific container
docker compose logs web-1

# Follow logs in real-time (like tail -f)
docker compose logs -f web

# View last 50 lines
docker compose logs --tail 50 web
```

### Execute Commands in Different Containers

**Database Container:**

```bash
# Connect to PostgreSQL
docker compose exec db psql -U postgres -d microblog_development

# Run SQL query
docker compose exec db psql -U postgres -d microblog_development -c "SELECT COUNT(*) FROM users;"
```

**Web Container:**

```bash
# Any Rails command
docker compose exec web-1 bin/rails <command>
```

## Common Development Tasks

### Running Scripts

**Load Test Seeding:**

```bash
docker compose exec web-1 bin/rails runner script/load_test_seed.rb
```

**Add Users:**

```bash
docker compose exec web-1 bin/rails runner script/add_15k_users.rb
docker compose exec web-1 bin/rails runner script/add_200k_users.rb
```

**Backfill Data:**

```bash
docker compose exec web-1 bin/rails runner script/backfill_counter_caches.rb
docker compose exec web-1 bin/rails runner script/backfill_existing_feeds.rb
```

**Test Scripts:**

```bash
docker compose exec web-1 bin/rails runner script/test_cache.rb
docker compose exec web-1 bin/rails runner script/test_rate_limiting.rb
```

### Database Operations

**Run Migrations:**

```bash
docker compose exec web-1 bin/rails db:migrate
```

**Seed Database:**

```bash
docker compose exec web-1 bin/rails db:seed
```

**Database Console:**

```bash
# PostgreSQL console
docker compose exec db psql -U postgres -d microblog_development

# Rails database console
docker compose exec web-1 bin/rails dbconsole
```

**Check Migration Status:**

```bash
docker compose exec web-1 bin/rails db:migrate:status
```

**Rollback Migration:**

```bash
docker compose exec web-1 bin/rails db:rollback
```

### Testing

**Run Tests:**

```bash
docker compose exec web-1 bundle exec rspec

# Run specific test file
docker compose exec web-1 bundle exec rspec spec/models/user_spec.rb

# Run with coverage
docker compose exec web-1 bash -c "COVERAGE=true bundle exec rspec"
```

### Code Quality

**RuboCop:**

```bash
docker compose exec web-1 bundle exec rubocop
```

**Brakeman (Security):**

```bash
docker compose exec web-1 bundle exec brakeman
```

### Accessing Files

**View File:**

```bash
docker compose exec web-1 cat /rails/app/models/user.rb
```

**Edit File:**

Files in the project directory are mounted as volumes, so you can edit them on your host machine and changes are reflected in the container. However, if you need to edit inside the container:

```bash
# Get interactive shell
docker compose exec web-1 bash

# Use editor inside container (if available)
nano /rails/app/models/user.rb
# or
vi /rails/app/models/user.rb
```

**Check File Permissions:**

```bash
docker compose exec web-1 ls -la /rails/script
```

### Environment Variables

**View Environment Variables:**

```bash
# View all environment variables
docker compose exec web-1 env

# View specific variable
docker compose exec web-1 env | grep DATABASE

# View Rails environment
docker compose exec web-1 bin/rails runner "puts Rails.env"
```

**Set Environment Variables for One Command:**

```bash
docker compose exec web-1 bash -c "RAILS_ENV=test bin/rails runner 'puts Rails.env'"
```

## Troubleshooting

### Container Not Running

**Problem:** Container exits immediately or shows as "Exited"

```bash
# Check container status
docker compose ps -a

# View logs to see why it exited
docker compose logs web-1

# Restart container
docker compose restart web-1

# Recreate container
docker compose up -d --force-recreate web-1
```

### Command Not Found

**Problem:** `docker compose exec web-1 bin/rails` returns "command not found"

**Solution:** Container might not be running or Rails isn't installed

```bash
# Verify container is running
docker compose ps web-1

# Check if Rails is available
docker compose exec web-1 which rails
docker compose exec web-1 bundle exec rails --version
```

### Permission Denied

**Problem:** Permission errors when accessing files

**Solution:** Check file permissions and ownership

```bash
# Check permissions
docker compose exec web-1 ls -la /rails

# Fix permissions (if needed, from host)
chmod +x script/your_script.rb
```

### Database Connection Issues

**Problem:** Can't connect to database from container

```bash
# Verify database container is running
docker compose ps db

# Check database connection from web container
docker compose exec web-1 bin/rails runner "ActiveRecord::Base.connection.execute('SELECT 1')"

# Check environment variables
docker compose exec web-1 env | grep DATABASE
```

See [Docker Compose Configuration Guide](038_DOCKER_COMPOSE_CONFIGURATION.md) for detailed database connection troubleshooting.

### Scripts Not Found

**Problem:** Script file not found when running

```bash
# Verify script exists in container
docker compose exec web-1 ls -la /rails/script

# Check if file is readable
docker compose exec web-1 cat /rails/script/your_script.rb

# Verify you're in the right directory (scripts are in /rails/script)
docker compose exec web-1 pwd
```

### Container Resource Limits

**Problem:** Container runs out of memory or CPU

```bash
# Check container resource usage
docker stats

# View container configuration
docker inspect microblog-web-1
```

## Best Practices

### 1. Use Specific Container Names

When you have multiple containers, use specific names:

```bash
# ✅ Good - specific container
docker compose exec web-1 bin/rails runner script/load_test_seed.rb

# ⚠️ Less reliable - Docker picks one
docker compose exec web bin/rails runner script/load_test_seed.rb
```

### 2. Use Interactive Shells for Multiple Commands

Instead of running many `docker compose exec` commands:

```bash
# ✅ Good - interactive shell
docker compose exec web-1 bash
# Then run multiple commands
bin/rails db:migrate
bin/rails runner script/load_test_seed.rb
exit

# ❌ Less efficient - multiple exec calls
docker compose exec web-1 bin/rails db:migrate
docker compose exec web-1 bin/rails runner script/load_test_seed.rb
```

### 3. Check Container Status First

Before running commands, verify containers are running:

```bash
# Check status
docker compose ps

# Then run command
docker compose exec web-1 bin/rails runner script/load_test_seed.rb
```

### 4. Use Environment Variables for Configuration

Set environment variables in `docker-compose.yml` or `.env` file rather than passing them each time:

```yaml
# docker-compose.yml
environment:
  NUM_USERS: 1000
  RAILS_ENV: development
```

### 5. View Logs When Debugging

Always check logs when something doesn't work:

```bash
# View recent logs
docker compose logs --tail 50 web-1

# Follow logs
docker compose logs -f web-1
```

### 6. Clean Up Regularly

Remove stopped containers and unused resources:

```bash
# Remove stopped containers
docker compose down

# Remove unused images
docker image prune

# Full cleanup (⚠️ removes all unused Docker resources)
docker system prune
```

## Quick Reference

### Most Common Commands

```bash
# Start services
docker compose up -d

# Stop services
docker compose down

# View logs
docker compose logs -f web

# Run script
docker compose exec web-1 bin/rails runner script/load_test_seed.rb

# Interactive shell
docker compose exec web-1 bash

# Rails console
docker compose exec web-1 bin/rails console

# Database migration
docker compose exec web-1 bin/rails db:migrate

# Check status
docker compose ps
```

### Container Names Pattern

- `microblog-web-{N}` - Web application containers
- `microblog-db-1` - Database container
- `microblog-traefik-1` - Load balancer container
- `microblog-migrate-run-{hash}` - Migration containers (one-time)

### File Paths in Container

- `/rails` - Application root directory (mounted from host)
- `/rails/script` - Scripts directory
- `/rails/app` - Application code
- `/rails/config` - Configuration files
- `/rails/db` - Database files
- `/rails/tmp` - Temporary files

## Additional Resources

- [Docker Compose Configuration Guide](038_DOCKER_COMPOSE_CONFIGURATION.md) - Detailed Docker setup
- [Horizontal Scaling Guide](036_HORIZONTAL_SCALING.md) - Scaling with Docker
- [Docker Official Documentation](https://docs.docker.com/) - General Docker reference

## Summary

**Key Takeaways:**

1. ✅ Always use `docker compose exec` to run commands inside containers
2. ✅ Use specific container names (`web-1`) when you have multiple instances
3. ✅ Check container status with `docker compose ps` before running commands
4. ✅ View logs with `docker compose logs` when debugging
5. ✅ Use interactive shells (`bash`) for multiple commands
6. ✅ Files in `/rails` are mounted from your host machine - edit them locally

**Remember:** When using Docker, think of containers as isolated servers. You need to "enter" the container to run commands, just like SSH-ing into a remote server.

