# Deployment Guide

> **Complete guide for deploying the Microblog three-layer architecture to production**

This document provides comprehensive instructions for deploying both the backend API and frontend React application independently using Kamal and Docker.

**Repositories:**
- **Backend**: [https://github.com/Davidslv/microblog](https://github.com/Davidslv/microblog)
- **Frontend**: [https://github.com/Davidslv/microblog-frontend](https://github.com/Davidslv/microblog-frontend)

---

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Architecture Overview](#architecture-overview)
4. [Backend Deployment](#backend-deployment)
5. [Frontend Deployment](#frontend-deployment)
6. [Docker Configuration](#docker-configuration)
7. [Environment Variables](#environment-variables)
8. [Database Setup](#database-setup)
9. [SSL/TLS Configuration](#ssltls-configuration)
10. [Monitoring and Maintenance](#monitoring-and-maintenance)
11. [Troubleshooting](#troubleshooting)

---

## Overview

The Microblog application follows a **three-layer architecture** that allows independent deployment of each layer:

1. **Presentation Layer** (Frontend) - React SPA, deployed as static assets
2. **Application Layer** (Backend) - Rails API, deployed as containerized application
3. **Data Layer** (Database) - PostgreSQL, deployed separately or as managed service

### Deployment Options

**Option 1: Kamal (Recommended)**
- Deploys both services independently
- Zero-downtime deployments
- Automatic SSL via Let's Encrypt
- Rollback support

**Option 2: Docker Compose**
- Single-command deployment
- Good for single-server setups
- Manual SSL configuration

**Option 3: Platform-as-a-Service**
- Backend: Heroku, Railway, Render
- Frontend: Vercel, Netlify, CloudFront
- Managed databases

This guide focuses on **Kamal deployment** for production use.

---

## Prerequisites

### Required Software

- **Docker** 20.10+ installed on deployment server
- **Kamal** 2.0+ installed locally
- **SSH access** to deployment server(s)
- **Domain name(s)** configured with DNS
- **Git** for cloning repositories

### Server Requirements

**Backend Server:**
- CPU: 2+ cores
- RAM: 4GB+ (8GB recommended)
- Disk: 20GB+ SSD
- OS: Ubuntu 22.04 LTS or similar

**Frontend Server (Optional):**
- Can be same server as backend
- Or use CDN/static hosting (Vercel, Netlify)

### Install Kamal

```bash
# Install Kamal gem
gem install kamal

# Or add to Gemfile
gem "kamal", require: false

# Verify installation
kamal version
```

---

## Architecture Overview

### Production Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    INTERNET                                  │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        │ HTTPS
                        │
        ┌───────────────┴───────────────┐
        │                                │
        ▼                                ▼
┌───────────────┐              ┌───────────────┐
│   Frontend    │              │    Backend     │
│   (Nginx)     │              │   (Puma)       │
│   Port 80/443 │              │   Port 3000    │
│               │              │                │
│  Static Files │              │  Rails API     │
│  React SPA    │              │  /api/v1/*     │
└───────────────┘              └────────┬───────┘
                                        │
                                        │ PostgreSQL
                                        │
                                ┌───────▼───────┐
                                │   Database    │
                                │  PostgreSQL   │
                                │  (Port 5432)  │
                                └───────────────┘
```

### Deployment Flow

1. **Build Docker images** from source code
2. **Push images** to Docker registry (Docker Hub, private registry)
3. **Pull images** on deployment server
4. **Start containers** with proper configuration
5. **Health checks** verify services are running
6. **Zero-downtime** deployment with rolling updates

---

## Backend Deployment

### Step 1: Configure Kamal

**File: `config/deploy.yml`**

```yaml
# Name of your application
service: microblog

# Docker image name
image: microblog

# Deploy to these servers
servers:
  web:
    hosts:
      - <%= ENV.fetch("BACKEND_HOST", "api.yourdomain.com") %>
    options:
      "add-host": host.docker_hostname + ":host-gateway"

# Docker registry
registry:
  username: <%= ENV.fetch("DOCKER_USERNAME", "") %>
  password: <%= ENV.fetch("DOCKER_PASSWORD", "") %>
  server: <%= ENV.fetch("DOCKER_REGISTRY", "docker.io") %>

# SSL configuration
proxy:
  ssl: true
  host: <%= ENV.fetch("BACKEND_HOST", "api.yourdomain.com") %>

# Environment variables
env:
  secret:
    - RAILS_MASTER_KEY
    - DATABASE_URL
    - SECRET_KEY_BASE
  clear:
    RAILS_ENV: production
    SOLID_QUEUE_IN_PUMA: "true"
    DATABASE_HOST: <%= ENV.fetch("DB_HOST", "localhost") %>
    DATABASE_PORT: 5432
    DATABASE_USERNAME: <%= ENV.fetch("DB_USERNAME", "postgres") %>
    DATABASE_PASSWORD: <%= ENV.fetch("DB_PASSWORD", "") %>

# Health check
healthcheck:
  path: /up
  port: 80
  max_attempts: 10
  interval: 10s

# Resource limits
limits:
  memory: 2g
  cpus: 2

# Persistent volumes
volumes:
  - "microblog_storage:/rails/storage"
```

### Step 2: Set Environment Variables

**Create `.kamal/secrets` file:**

```bash
# Create secrets directory
mkdir -p .kamal

# Create secrets file (DO NOT COMMIT THIS)
cat > .kamal/secrets <<EOF
RAILS_MASTER_KEY=your_rails_master_key_here
DATABASE_URL=postgresql://user:password@db_host:5432/microblog_production
SECRET_KEY_BASE=your_secret_key_base_here
EOF

# Secure the file
chmod 600 .kamal/secrets
```

**Set environment variables:**

```bash
# Docker registry credentials
export DOCKER_USERNAME=your-docker-username
export DOCKER_PASSWORD=your-docker-password
export DOCKER_REGISTRY=docker.io  # or your private registry

# Backend domain
export BACKEND_HOST=api.yourdomain.com

# Frontend domain (required for CORS)
export FRONTEND_URL=https://yourdomain.com

# Database configuration
export DB_HOST=your-db-host
export DB_USERNAME=postgres
export DB_PASSWORD=your-db-password
```

### Step 3: Build and Deploy

```bash
# Build Docker image
kamal build

# Push image to registry
kamal push

# Deploy to server
kamal deploy

# Check deployment status
kamal app details
```

### Step 4: Run Database Migrations

```bash
# Run migrations
kamal app exec "bin/rails db:migrate"

# Or use the console alias
kamal console
# Then in Rails console:
# ActiveRecord::Base.connection.execute("SELECT version();")
```

### Step 5: Verify Deployment

```bash
# Check health endpoint
curl https://api.yourdomain.com/up

# Check logs
kamal app logs

# Check container status
kamal app details
```

---

## Frontend Deployment

### Option 1: Kamal Deployment (Same Server)

**File: `config/deploy.yml` (in frontend repository)**

```yaml
service: microblog-frontend

image: microblog-frontend

servers:
  web:
    hosts:
      - <%= ENV.fetch("FRONTEND_HOST", "yourdomain.com") %>
    options:
      "add-host": host.docker_hostname + ":host-gateway"

registry:
  username: <%= ENV.fetch("DOCKER_USERNAME", "") %>
  password: <%= ENV.fetch("DOCKER_PASSWORD", "") %>
  server: <%= ENV.fetch("DOCKER_REGISTRY", "docker.io") %>

proxy:
  ssl: true
  host: <%= ENV.fetch("FRONTEND_HOST", "yourdomain.com") %>

env:
  clear:
    VITE_API_URL: <%= ENV.fetch("VITE_API_URL", "https://api.yourdomain.com/api/v1") %>

healthcheck:
  path: /
  port: 80
  max_attempts: 10
  interval: 10s

limits:
  memory: 256m
  cpus: 0.5
```

**Deploy:**

```bash
# Set environment variables
export FRONTEND_HOST=yourdomain.com
export VITE_API_URL=https://api.yourdomain.com/api/v1
export DOCKER_USERNAME=your-docker-username
export DOCKER_PASSWORD=your-docker-password

# Build and deploy
kamal build
kamal push
kamal deploy
```

### Option 2: Static Hosting (Vercel/Netlify)

**Build locally:**

```bash
# Set production API URL
export VITE_API_URL=https://api.yourdomain.com/api/v1

# Build
npm run build

# Deploy dist/ directory to your hosting provider
```

**Vercel:**

```bash
# Install Vercel CLI
npm i -g vercel

# Deploy
vercel --prod
```

**Netlify:**

```bash
# Install Netlify CLI
npm i -g netlify-cli

# Deploy
netlify deploy --prod --dir=dist
```

**Configure environment variables** in your hosting provider's dashboard:
- `VITE_API_URL`: `https://api.yourdomain.com/api/v1`

---

## Docker Configuration

### Backend Dockerfile

The backend includes a production-ready Dockerfile:

```dockerfile
# Multi-stage build
FROM ruby:3.4.7-slim AS base
# ... (see Dockerfile in repository)
```

**Key features:**
- Multi-stage build for smaller image size
- Non-root user for security
- jemalloc for memory optimization
- Precompiled assets

### Frontend Dockerfile

The frontend uses a multi-stage build:

```dockerfile
# Build stage
FROM node:20-alpine AS builder
# ... build React app

# Production stage
FROM nginx:alpine
# ... serve static files
```

**Key features:**
- Nginx for serving static files
- Optimized production build
- Small image size (~50MB)

### Docker Compose (Development)

For local development, use `docker-compose.yml`:

```bash
# Start all services
docker compose up -d

# View logs
docker compose logs -f

# Stop services
docker compose down
```

**Note:** Production deployments should use Kamal for better control and zero-downtime deployments.

---

## Environment Variables

### Backend Environment Variables

**Required:**
- `RAILS_MASTER_KEY` - Rails master key (from `config/master.key`)
- `DATABASE_URL` - PostgreSQL connection string
- `SECRET_KEY_BASE` - Rails secret key base

**Optional:**
- `RAILS_ENV` - Environment (default: `production`)
- `SOLID_QUEUE_IN_PUMA` - Run jobs in Puma (default: `true`)
- `DISABLE_RACK_ATTACK` - Disable rate limiting (default: `false`)
- `FRONTEND_URL` - **Required for CORS**: Frontend domain URL (e.g., `https://microblog.davidslv.uk`)

**⚠️ Important: CORS Configuration**

The backend's CORS configuration requires `FRONTEND_URL` to be set in production. Without it, all API requests from the frontend will be blocked by the browser's CORS policy.

**Add to `config/deploy.yml`:**
```yaml
env:
  clear:
    FRONTEND_URL: <%= ENV.fetch("FRONTEND_URL", "https://microblog.davidslv.uk") %>
```

**See:** `microblog-frontend/docs/004_CORS_TROUBLESHOOTING.md` for detailed troubleshooting.

### Frontend Environment Variables

**Required:**
- `VITE_API_URL` - Backend API URL (e.g., `https://api.yourdomain.com/api/v1`)

**Note:** Vite environment variables must be prefixed with `VITE_` and are embedded at build time.

---

## Database Setup

### PostgreSQL Setup

**Option 1: Managed Database (Recommended)**

Use a managed PostgreSQL service:
- AWS RDS
- Google Cloud SQL
- DigitalOcean Managed Databases
- Heroku Postgres

**Connection string:**
```
postgresql://username:password@host:5432/database_name
```

**Option 2: Self-Hosted PostgreSQL**

```bash
# Install PostgreSQL
sudo apt-get update
sudo apt-get install postgresql postgresql-contrib

# Create database
sudo -u postgres psql
CREATE DATABASE microblog_production;
CREATE USER microblog WITH PASSWORD 'your_password';
GRANT ALL PRIVILEGES ON DATABASE microblog_production TO microblog;
\q
```

### Run Migrations

```bash
# Via Kamal
kamal app exec "bin/rails db:migrate"

# Or via Rails console
kamal console
# Then: ActiveRecord::Base.connection.execute("SELECT version();")
```

### Database Backups

```bash
# Create backup
pg_dump -h db_host -U username microblog_production > backup.sql

# Restore backup
psql -h db_host -U username microblog_production < backup.sql
```

**Automated backups:** Use cron or a backup service (e.g., AWS Backup, pgBackRest).

---

## SSL/TLS Configuration

### Automatic SSL with Kamal

Kamal automatically configures SSL via Let's Encrypt:

```yaml
# config/deploy.yml
proxy:
  ssl: true
  host: yourdomain.com
```

**Requirements:**
- Domain name pointing to server IP
- Port 80 and 443 open in firewall
- DNS A record configured

### Manual SSL Configuration

If using a reverse proxy (Nginx, Traefik):

```nginx
# Nginx configuration
server {
    listen 443 ssl;
    server_name yourdomain.com;

    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;

    location / {
        proxy_pass http://localhost:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

---

## Monitoring and Maintenance

### Health Checks

**Backend:**
```bash
# Health endpoint
curl https://api.yourdomain.com/up

# Expected: {"status":"ok"}
```

**Frontend:**
```bash
# Check if frontend loads
curl https://yourdomain.com
```

### Logs

**View logs:**
```bash
# Backend logs
kamal app logs

# Frontend logs (if using Kamal)
kamal app logs -r frontend

# Docker logs
docker logs microblog_web
```

### Monitoring Tools

**Recommended:**
- **Application Monitoring**: New Relic, Datadog, Sentry
- **Server Monitoring**: Prometheus, Grafana
- **Uptime Monitoring**: UptimeRobot, Pingdom
- **Error Tracking**: Sentry, Rollbar

### Maintenance Tasks

**Regular tasks:**
- Database backups (daily)
- Log rotation (weekly)
- Security updates (monthly)
- Dependency updates (quarterly)

**Commands:**
```bash
# Update dependencies
bundle update  # Backend
npm update    # Frontend

# Security audit
bundle exec bundler-audit
npm audit

# Database maintenance
kamal app exec "bin/rails db:maintenance"
```

---

## Troubleshooting

### Deployment Fails

**Check:**
1. Docker is running on server
2. SSH access is configured
3. Environment variables are set
4. Docker registry credentials are correct
5. Domain DNS is configured

**Debug:**
```bash
# Verbose output
kamal deploy --verbose

# Check server connection
kamal app details

# View build logs
kamal build --verbose
```

### Service Won't Start

**Check logs:**
```bash
kamal app logs

# Or directly on server
docker logs microblog_web
```

**Common issues:**
- Database connection failed
- Missing environment variables
- Port conflicts
- Insufficient resources

### Database Connection Issues

**Verify connection:**
```bash
# From server
psql -h db_host -U username -d database_name

# From Rails console
kamal console
ActiveRecord::Base.connection.execute("SELECT 1")
```

**Check:**
- Database is running
- Firewall allows connections
- Credentials are correct
- Database exists

### SSL Certificate Issues

**Check certificate:**
```bash
# View certificate
openssl s_client -connect yourdomain.com:443

# Check expiration
echo | openssl s_client -connect yourdomain.com:443 2>/dev/null | openssl x509 -noout -dates
```

**Common issues:**
- DNS not configured
- Port 80/443 blocked
- Certificate expired
- Domain mismatch

### Performance Issues

**Check resources:**
```bash
# Server resources
kamal app exec "free -h"
kamal app exec "df -h"

# Container stats
docker stats
```

**Optimize:**
- Increase container limits
- Add more servers (horizontal scaling)
- Optimize database queries
- Enable caching

---

## Deployment Checklist

### Pre-Deployment

- [ ] Server provisioned and accessible
- [ ] Docker installed on server
- [ ] Kamal installed locally
- [ ] Domain names configured
- [ ] DNS records pointing to server
- [ ] Database provisioned
- [ ] Environment variables documented
- [ ] Secrets stored securely
- [ ] SSL certificates configured
- [ ] Firewall rules configured

### Backend Deployment

- [ ] `config/deploy.yml` configured
- [ ] `.kamal/secrets` file created
- [ ] Environment variables set
- [ ] Docker image builds successfully
- [ ] Image pushed to registry
- [ ] Deployment successful
- [ ] Health check passes
- [ ] Database migrations run
- [ ] API endpoints accessible

### Frontend Deployment

- [ ] `config/deploy.yml` configured (if using Kamal)
- [ ] `VITE_API_URL` set to production API
- [ ] Build succeeds
- [ ] Static files deployed
- [ ] Frontend loads correctly
- [ ] API calls work
- [ ] Authentication works
- [ ] All features functional

### Post-Deployment

- [ ] Monitor logs for errors
- [ ] Test all features
- [ ] Verify SSL certificates
- [ ] Set up monitoring
- [ ] Configure backups
- [ ] Document deployment process
- [ ] Update team on deployment

---

## Additional Resources

- **Kamal Documentation**: [https://kamal-deploy.org](https://kamal-deploy.org)
- **Docker Documentation**: [https://docs.docker.com](https://docs.docker.com)
- **Rails Deployment Guide**: [https://guides.rubyonrails.org/deployment.html](https://guides.rubyonrails.org/deployment.html)
- **Backend Repository**: [https://github.com/Davidslv/microblog](https://github.com/Davidslv/microblog)
- **Frontend Repository**: [https://github.com/Davidslv/microblog-frontend](https://github.com/Davidslv/microblog-frontend)

---

## Support

For deployment issues:
1. Check logs: `kamal app logs`
2. Review this guide
3. Check [Kamal documentation](https://kamal-deploy.org)
4. Review server logs
5. Contact the team

---

**Happy deploying! 🚀**

