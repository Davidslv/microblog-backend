# Complete Deployment & Secrets Management Guide

> **The definitive guide to understanding Kamal, Docker, Digital Ocean, and Environment Variables**

This document provides a comprehensive, systematic approach to understanding and executing deployments. It explains the entire flow from your local machine to a production server, including how secrets are managed at every step.

**Table of Contents:**
1. [Understanding the Big Picture](#understanding-the-big-picture)
2. [The Complete Deployment Flow](#the-complete-deployment-flow)
3. [Secrets Management Deep Dive](#secrets-management-deep-dive)
4. [Step-by-Step Deployment Process](#step-by-step-deployment-process)
5. [Rails-Specific Secrets Explained](#rails-specific-secrets-explained)
6. [Command Cheat Sheet](#command-cheat-sheet)
7. [Troubleshooting Common Issues](#troubleshooting-common-issues)
8. [Universal Deployment Pattern](#universal-deployment-pattern)

---

## Understanding the Big Picture

### What Each Component Does

**Kamal** is a deployment tool that:
- Builds Docker images from your code
- Pushes images to a Docker registry (Docker Hub, DigitalOcean Container Registry, etc.)
- Connects to your server via SSH
- Pulls images on the server
- Manages Docker containers on the server
- Handles zero-downtime deployments
- Manages SSL certificates automatically

**Docker** is a containerization platform that:
- Packages your application and all dependencies into an image
- Runs your application in isolated containers
- Ensures consistency across different environments

**Digital Ocean** (or any VPS) is:
- A remote server where your application runs
- Where Docker containers execute
- Where your production application lives

**Environment Variables** are:
- Configuration values that change between environments
- Secrets that should never be committed to git
- Runtime configuration for your application

### The Problem You're Solving

When deploying, you need to:
1. **Build** your application into a Docker image
2. **Store** that image somewhere accessible (registry)
3. **Transfer** the image to your server
4. **Run** the image as a container with proper configuration
5. **Manage** secrets securely without exposing them

---

## The Complete Deployment Flow

### High-Level Architecture

```mermaid
graph TB
    subgraph "Local Machine"
        A[Your Code] --> B[Kamal CLI]
        B --> C[Docker Build]
        C --> D[Docker Image]
        D --> E[Push to Registry]
    end

    subgraph "Docker Registry"
        E --> F[Docker Hub / DO Registry]
    end

    subgraph "Digital Ocean VPS"
        F --> G[Kamal SSH Connection]
        G --> H[Pull Image]
        H --> I[Run Container]
        I --> J[Your App Running]
    end

    subgraph "Secrets Flow"
        K[.kamal/secrets] --> B
        B --> L[Inject into Container]
        L --> I
    end

    style A fill:#e1f5ff
    style J fill:#c8e6c9
    style K fill:#fff3e0
    style F fill:#f3e5f5
```

### Detailed Deployment Sequence

```mermaid
sequenceDiagram
    participant Dev as Developer
    participant Local as Local Machine
    participant Kamal as Kamal CLI
    participant Docker as Docker Engine
    participant Registry as Docker Registry
    participant SSH as SSH Connection
    participant Server as VPS Server
    participant Container as Docker Container

    Dev->>Local: kamal build
    Local->>Kamal: Read config/deploy.yml
    Kamal->>Local: Read .kamal/secrets
    Kamal->>Docker: docker build -t image:tag
    Docker->>Local: Image built locally

    Dev->>Local: kamal push
    Local->>Kamal: Authenticate with registry
    Kamal->>Registry: docker push image:tag
    Registry->>Kamal: Image stored

    Dev->>Local: kamal deploy
    Local->>Kamal: Read deploy.yml + secrets
    Kamal->>SSH: Connect to server
    SSH->>Server: Authenticated connection
    Kamal->>Server: docker pull image:tag
    Server->>Registry: Pull image
    Registry->>Server: Image downloaded
    Kamal->>Server: docker run with ENV vars
    Server->>Container: Start container
    Container->>Container: Read ENV vars
    Container->>Container: Application starts
```

---

## Secrets Management Deep Dive

### Where Secrets Live and How They Flow

```mermaid
graph LR
    subgraph "Source of Truth"
        A[config/master.key<br/>Rails Master Key]
        B[Password Manager<br/>or ENV vars]
        C[Database Credentials<br/>DigitalOcean Panel]
    end

    subgraph ".kamal/secrets File"
        D[RAILS_MASTER_KEY<br/>from master.key]
        E[KAMAL_REGISTRY_PASSWORD<br/>from ENV]
        F[DATABASE_URL<br/>from DO Panel]
        G[SECRET_KEY_BASE<br/>generated or from ENV]
    end

    subgraph "config/deploy.yml"
        H[env:<br/>  secret:<br/>    - RAILS_MASTER_KEY<br/>    - SECRET_KEY_BASE]
    end

    subgraph "Docker Container"
        I[ENV Variables<br/>injected at runtime]
    end

    A --> D
    B --> E
    C --> F
    B --> G

    D --> H
    E --> H
    F --> H
    G --> H

    H --> I

    style A fill:#ffcdd2
    style B fill:#ffcdd2
    style C fill:#ffcdd2
    style D fill:#fff3e0
    style I fill:#c8e6c9
```

### Secrets Storage Locations

| Secret Type | Where It's Stored | How It's Accessed | Security Level |
|------------|------------------|-------------------|----------------|
| `RAILS_MASTER_KEY` | `config/master.key` (local) | Read by `.kamal/secrets` | ⚠️ Never commit to git |
| `SECRET_KEY_BASE` | Generated or from ENV | Set in `.kamal/secrets` | ⚠️ Never commit to git |
| `DATABASE_URL` | DigitalOcean Panel / ENV | Set in `.kamal/secrets` | ⚠️ Never commit to git |
| `KAMAL_REGISTRY_PASSWORD` | Docker Hub token / ENV | Set in `.kamal/secrets` | ⚠️ Never commit to git |
| `FRONTEND_URL` | `config/deploy.yml` (clear) | Injected as ENV var | ✅ Safe to commit |

### The Secrets File (.kamal/secrets)

**Location:** `.kamal/secrets` (in your project root)

**Purpose:** This is a shell script that Kamal executes to get secret values. It should NEVER be committed to git.

**How It Works:**
1. Kamal reads `config/deploy.yml`
2. When it sees `env.secret: - SECRET_NAME`, it looks for `SECRET_NAME` in `.kamal/secrets`
3. Kamal executes `.kamal/secrets` as a shell script
4. The script exports variables that Kamal captures
5. These values are injected into the Docker container as environment variables

**Example `.kamal/secrets` file:**

```bash
#!/bin/bash
# This file is executed by Kamal to get secret values
# DO NOT commit raw credentials here - use ENV vars or password managers

# Docker registry password from environment variable
KAMAL_REGISTRY_PASSWORD=$DOCKER_HUB_TOKEN

# Rails master key from local file (never commit config/master.key!)
RAILS_MASTER_KEY=$(cat config/master.key)

# Secret key base - generate if not set, or use from ENV
SECRET_KEY_BASE=${SECRET_KEY_BASE:-$(openssl rand -hex 64)}

# Database URL from environment variable
DATABASE_URL=$PRODUCTION_DATABASE_URL

# Database password (if needed separately)
DATABASE_PASSWORD=$PRODUCTION_DB_PASSWORD
```

**Important:** The `.kamal/secrets` file is a **shell script**, not a key-value file. It's executed, and the exported variables are captured.

---

## Step-by-Step Deployment Process

### Phase 1: Initial Setup (One-Time)

#### Step 1.1: Prepare Your Local Machine

```bash
# 1. Install Kamal
gem install kamal

# 2. Verify installation
kamal version

# 3. Ensure Docker is running locally
docker ps
```

#### Step 1.2: Set Up Digital Ocean VPS

1. **Create a Droplet:**
   - Go to DigitalOcean → Create → Droplets
   - Choose Ubuntu 22.04 LTS
   - Select size (2GB RAM minimum recommended)
   - Add your SSH key
   - Create droplet

2. **Note the IP address** (e.g., `xx.777.xx.73`)

3. **Set up DNS** (if using a domain):
   - Point your domain's A record to the droplet IP
   - Example: `microblog.davidslv.uk` → `xx.177.xx.73`

#### Step 1.3: Configure SSH Access

```bash
# Test SSH connection
ssh root@xx.177.xx.73

# If using a key file
ssh -i ~/.ssh/your_key root@xx.177.xx.73

# Kamal will use your default SSH config, or you can specify in deploy.yml
```

#### Step 1.4: Set Up Docker Registry

**Option A: Docker Hub (Free tier available)**

1. Create account at https://hub.docker.com
2. Create an access token:
   - Account Settings → Security → New Access Token
   - Save the token (you'll need it)

**Option B: DigitalOcean Container Registry**

1. In DigitalOcean panel → Container Registry → Create
2. Generate a read/write token
3. Save the token

#### Step 1.5: Set Up Database

**Option A: DigitalOcean Managed Database (Recommended)**

1. Create → Databases → PostgreSQL
2. Choose region and size
3. Note the connection details:
   - Host: `private-db-postgresql-lon1-11936-do-user-28554529-0.j.db.ondigitalocean.com`
   - Port: `25060`
   - Username: `doadmin`
   - Password: (shown once, save it!)
   - Database: `defaultdb`

**Option B: Self-Hosted PostgreSQL**

```bash
# On your VPS
sudo apt update
sudo apt install postgresql postgresql-contrib
sudo -u postgres psql
CREATE DATABASE microblog_production;
CREATE USER microblog WITH PASSWORD 'your_password';
GRANT ALL PRIVILEGES ON DATABASE microblog_production TO microblog;
\q
```

### Phase 2: Configure Your Project

#### Step 2.1: Configure Kamal (config/deploy.yml)

```yaml
# Name of your application (used for container naming)
service: microblog

# Docker image name (include your Docker Hub username)
image: davidslvuk/microblog-backend

# Deploy to these servers
servers:
  web:
    hosts:
      - <%= ENV.fetch("BACKEND_HOST", "xx.177.xx.73") %>

# SSL/HTTPS configuration
proxy:
  ssl: true
  host: <%= ENV.fetch("BACKEND_HOST", "microblog-be.davidslv.uk") %>

# Docker registry configuration
registry:
  server: <%= ENV.fetch("DOCKER_REGISTRY", "docker.io") %>
  username: <%= ENV.fetch("DOCKER_USERNAME", "davidslvuk") %>
  password:
    - KAMAL_REGISTRY_PASSWORD  # References .kamal/secrets

# Environment variables
env:
  secret:
    - RAILS_MASTER_KEY      # From .kamal/secrets
    - SECRET_KEY_BASE       # From .kamal/secrets
  clear:
    RAILS_ENV: production
    FRONTEND_URL: <%= ENV.fetch("FRONTEND_URL", "https://microblog.davidslv.uk") %>
    SOLID_QUEUE_IN_PUMA: "true"
    # Database connection (if not using DATABASE_URL secret)
    DATABASE_HOST: private-db-postgresql-lon1-11936-do-user-28554529-0.j.db.ondigitalocean.com
    DATABASE_PORT: 25060
    DATABASE_USERNAME: doadmin
    # DATABASE_PASSWORD should be in secrets if needed separately

# Persistent volumes (for file uploads, etc.)
volumes:
  - "volume_lon1_01:/rails/storage"
```

#### Step 2.2: Create Secrets File (.kamal/secrets)

```bash
# Create the directory
mkdir -p .kamal

# Create the secrets file
cat > .kamal/secrets <<'EOF'
#!/bin/bash
# Secrets file - DO NOT COMMIT TO GIT
# This file is executed by Kamal to get secret values

# Docker registry password from environment variable
KAMAL_REGISTRY_PASSWORD=$DOCKER_HUB_TOKEN

# Rails master key from local file
# NEVER commit config/master.key to git!
RAILS_MASTER_KEY=$(cat config/master.key)

# Secret key base - use from ENV or generate
SECRET_KEY_BASE=${SECRET_KEY_BASE:-$(openssl rand -hex 64)}

# Database URL (full connection string)
DATABASE_URL=$PRODUCTION_DATABASE_URL

# If you need database password separately
DATABASE_PASSWORD=$PRODUCTION_DB_PASSWORD
EOF

# Make it executable
chmod +x .kamal/secrets

# Secure it (optional but recommended)
chmod 600 .kamal/secrets
```

**Add to .gitignore:**
```bash
echo ".kamal/secrets" >> .gitignore
echo "config/master.key" >> .gitignore  # If not already there
```

#### Step 2.3: Set Environment Variables

Create a file to store your environment variables (don't commit this either):

```bash
# Create .env.deploy (add to .gitignore)
cat > .env.deploy <<'EOF'
# Docker Registry
export DOCKER_HUB_TOKEN=your_docker_hub_token_here
export DOCKER_USERNAME=davidslvuk
export DOCKER_REGISTRY=docker.io

# Server Configuration
export BACKEND_HOST=xx.177.xx.73  # or your domain
export FRONTEND_URL=https://microblog.davidslv.uk

# Database (DigitalOcean Managed Database)
export PRODUCTION_DATABASE_URL=postgresql://doadmin:YOUR_PASSWORD@private-db-postgresql-lon1-11936-do-user-28554529-0.j.db.ondigitalocean.com:25060/defaultdb?sslmode=require
export PRODUCTION_DB_PASSWORD=your_database_password_here

# Optional: Secret Key Base (if you want to set it explicitly)
# export SECRET_KEY_BASE=$(openssl rand -hex 64)
EOF

# Source it before deploying
source .env.deploy
```

**Or set them in your shell profile:**
```bash
# Add to ~/.zshrc or ~/.bashrc
export DOCKER_HUB_TOKEN=your_token
export PRODUCTION_DATABASE_URL=postgresql://...
# etc.
```

### Phase 3: Deploy

#### Step 3.1: Initial Server Setup

```bash
# Kamal will set up Docker on the server automatically
kamal setup

# This command:
# - Connects to your server via SSH
# - Installs Docker if not present
# - Sets up necessary directories
# - Configures the server for Kamal deployments
```

#### Step 3.2: Build and Push Image

```bash
# 1. Build the Docker image locally
kamal build

# What happens:
# - Reads Dockerfile
# - Builds image with tag: davidslvuk/microblog-backend:latest
# - Image is stored locally

# 2. Push image to registry
kamal push

# What happens:
# - Authenticates with Docker Hub using KAMAL_REGISTRY_PASSWORD
# - Pushes image to registry
# - Image is now available for the server to pull
```

#### Step 3.3: Deploy to Server

```bash
# Deploy the application
kamal deploy

# What happens:
# 1. Kamal reads config/deploy.yml
# 2. Executes .kamal/secrets to get secret values
# 3. Connects to server via SSH
# 4. Pulls the Docker image from registry
# 5. Stops old container (if exists)
# 6. Starts new container with:
#    - Environment variables from deploy.yml
#    - Secret values injected as ENV vars
#    - Volume mounts configured
#    - Port mappings
# 7. Waits for health check
# 8. If healthy, removes old container
```

#### Step 3.4: Run Database Migrations

```bash
# Run migrations
kamal app exec "bin/rails db:migrate"

# Or use the console alias (if configured)
kamal console
# Then in Rails console:
# ActiveRecord::Base.connection.execute("SELECT version();")
```

#### Step 3.5: Verify Deployment

```bash
# Check if app is running
kamal app details

# View logs
kamal app logs

# Check health endpoint
curl https://microblog-be.davidslv.uk/up

# Or if using IP
curl http://xx.177.xx.73/up
```

---

## Rails-Specific Secrets Explained

### RAILS_MASTER_KEY

**What it is:**
- A key that decrypts `config/credentials.yml.enc`
- Rails uses it to access encrypted credentials
- Generated when you run `rails credentials:edit` for the first time

**Where it lives:**
- `config/master.key` (local file, NEVER commit to git)
- Should be in `.gitignore`

**How it's used:**
1. Rails reads `RAILS_MASTER_KEY` environment variable
2. Uses it to decrypt `config/credentials.yml.enc`
3. Makes credentials available via `Rails.application.credentials`

**In deployment:**
```bash
# .kamal/secrets
RAILS_MASTER_KEY=$(cat config/master.key)
```

```yaml
# config/deploy.yml
env:
  secret:
    - RAILS_MASTER_KEY
```

**Flow:**
```
config/master.key (local)
    ↓
.kamal/secrets reads it
    ↓
Kamal injects as ENV var
    ↓
Docker container receives RAILS_MASTER_KEY
    ↓
Rails uses it to decrypt credentials.yml.enc
```

### SECRET_KEY_BASE

**What it is:**
- Used for signing and encrypting cookies, sessions, etc.
- Different from `RAILS_MASTER_KEY`
- Can be auto-generated in development, but MUST be set in production

**Where it can come from:**
1. `Rails.application.credentials.secret_key_base` (encrypted credentials)
2. `ENV['SECRET_KEY_BASE']` (environment variable)
3. Auto-generated in development (stored in `tmp/development_secret.txt`)

**How to generate:**
```bash
# Generate a secure secret key base
openssl rand -hex 64

# Or use Rails
rails secret
```

**In deployment:**
```bash
# .kamal/secrets
# Option 1: Generate on the fly
SECRET_KEY_BASE=$(openssl rand -hex 64)

# Option 2: Use from ENV (if you want to reuse the same one)
SECRET_KEY_BASE=$PRODUCTION_SECRET_KEY_BASE

# Option 3: Store in Rails credentials and use master key
# (Then you don't need SECRET_KEY_BASE in secrets, Rails will get it from credentials)
```

```yaml
# config/deploy.yml
env:
  secret:
    - SECRET_KEY_BASE  # Only if not using credentials
```

**Important:** If you store `SECRET_KEY_BASE` in Rails credentials (`rails credentials:edit`), you don't need to set it as an environment variable. Rails will automatically use `Rails.application.credentials.secret_key_base` if `ENV['SECRET_KEY_BASE']` is not set.

### The Relationship Between RAILS_MASTER_KEY and SECRET_KEY_BASE

```mermaid
graph TB
    A[RAILS_MASTER_KEY<br/>Environment Variable] --> B[Decrypts<br/>credentials.yml.enc]
    B --> C[Rails.application.credentials]
    C --> D[secret_key_base<br/>from credentials]

    E[SECRET_KEY_BASE<br/>Environment Variable] --> F[Rails uses directly]

    G{Which is used?} --> H[If SECRET_KEY_BASE ENV set:<br/>Use that]
    G --> I[If not set:<br/>Use from credentials]

    D --> I
    F --> H

    style A fill:#fff3e0
    style E fill:#fff3e0
    style C fill:#c8e6c9
```

**Best Practice:**
- Store `SECRET_KEY_BASE` in Rails credentials (encrypted)
- Only need `RAILS_MASTER_KEY` as environment variable
- Rails will automatically use the credential value

**Example credentials setup:**
```bash
# Edit credentials
rails credentials:edit

# Add:
secret_key_base: your_generated_secret_here

# Save and close
# Now you only need RAILS_MASTER_KEY in deployment
```

---

## Command Cheat Sheet

### Pre-Deployment Commands

```bash
# Check Kamal version
kamal version

# Validate configuration
kamal config validate

# Check server connection
kamal app details

# View what Kamal will do (dry run)
kamal deploy --dry-run
```

### Build and Push Commands

```bash
# Build Docker image locally
kamal build

# Build with specific version tag
kamal build --version v1.0.0

# Push image to registry
kamal push

# Build and push in one command
kamal build push
```

### Deployment Commands

```bash
# Deploy to production
kamal deploy

# Deploy with specific version
kamal deploy --version v1.0.0

# Deploy with verbose output
kamal deploy --verbose

# Deploy without health check
kamal deploy --skip-healthcheck

# Rollback to previous version
kamal rollback

# Rollback to specific version
kamal rollback --version v0.9.0
```

### Container Management Commands

```bash
# View running containers
kamal app details

# View logs (follow mode)
kamal app logs -f

# View logs from specific container
kamal app logs --host xx.177.xx.73

# Execute command in container
kamal app exec "bin/rails console"

# Execute with interactive shell
kamal app exec --interactive "bash"

# Stop application
kamal app stop

# Start application
kamal app start

# Restart application
kamal app restart
```

### Database Commands

```bash
# Run migrations
kamal app exec "bin/rails db:migrate"

# Rollback last migration
kamal app exec "bin/rails db:rollback"

# Open database console
kamal app exec "bin/rails dbconsole"

# Or use alias (if configured)
kamal dbc
```

### Rails Console Commands

```bash
# Open Rails console
kamal app exec "bin/rails console"

# Or use alias (if configured in deploy.yml)
kamal console

# Run one-off command
kamal app exec "bin/rails runner 'User.count'"
```

### Secrets Management Commands

```bash
# View secrets (be careful - shows values!)
kamal secrets show

# Remove secrets from server
kamal secrets remove

# Copy secrets to server
kamal secrets copy
```

### Server Setup Commands

```bash
# Initial server setup (installs Docker, etc.)
kamal setup

# Remove everything from server
kamal remove

# Remove with confirmation
kamal remove --confirmed
```

### Monitoring Commands

```bash
# Check application status
kamal app details

# View container stats
kamal app exec "docker stats"

# Check disk usage
kamal app exec "df -h"

# Check memory usage
kamal app exec "free -h"
```

### Troubleshooting Commands

```bash
# View all logs
kamal app logs

# View logs with timestamps
kamal app logs --timestamps

# View logs from specific time
kamal app logs --since 1h

# Check server connection
kamal app details

# Test SSH connection
ssh root@xx.177.xx.73

# Test Docker on server
kamal app exec "docker ps"

# View environment variables in container
kamal app exec "env"
```

### Docker Commands (Direct)

```bash
# View images on server
kamal app exec "docker images"

# View containers on server
kamal app exec "docker ps -a"

# View container logs directly
kamal app exec "docker logs microblog_web"

# Execute command in running container
kamal app exec "docker exec -it microblog_web bash"

# Remove old images (cleanup)
kamal app exec "docker image prune -a"
```

---

## Troubleshooting Common Issues

### Issue: "Missing RAILS_MASTER_KEY"

**Symptoms:**
```
Missing encryption key to decrypt credentials
```

**Causes:**
1. `RAILS_MASTER_KEY` not set in `.kamal/secrets`
2. `config/master.key` doesn't exist locally
3. Secret not being injected into container

**Solutions:**

```bash
# 1. Check if master.key exists
ls -la config/master.key

# 2. If missing, you need to extract it from credentials
# (If you have access to the encrypted credentials but lost the key,
#  you'll need to regenerate credentials)

# 3. Verify .kamal/secrets has it
cat .kamal/secrets | grep RAILS_MASTER_KEY

# 4. Test that secrets file works
source .kamal/secrets
echo $RAILS_MASTER_KEY  # Should show the key

# 5. Check if it's in deploy.yml
grep -A 5 "env:" config/deploy.yml

# 6. Verify it's being set in container
kamal app exec "env | grep RAILS_MASTER_KEY"
```

### Issue: "Missing SECRET_KEY_BASE"

**Symptoms:**
```
`secret_key_base` missing
```

**Solutions:**

```bash
# Option 1: Add to .kamal/secrets
SECRET_KEY_BASE=$(openssl rand -hex 64)

# Option 2: Store in Rails credentials (recommended)
rails credentials:edit
# Add: secret_key_base: your_key_here

# Option 3: Set as environment variable explicitly
export SECRET_KEY_BASE=$(openssl rand -hex 64)
# Then in .kamal/secrets:
SECRET_KEY_BASE=$SECRET_KEY_BASE
```

### Issue: "Cannot connect to Docker registry"

**Symptoms:**
```
unauthorized: authentication required
```

**Solutions:**

```bash
# 1. Check DOCKER_HUB_TOKEN is set
echo $DOCKER_HUB_TOKEN

# 2. Verify .kamal/secrets has it
cat .kamal/secrets | grep KAMAL_REGISTRY_PASSWORD

# 3. Test Docker Hub login manually
docker login -u davidslvuk -p $DOCKER_HUB_TOKEN

# 4. Check deploy.yml registry config
grep -A 5 "registry:" config/deploy.yml
```

### Issue: "Cannot connect to server via SSH"

**Symptoms:**
```
SSH connection failed
```

**Solutions:**

```bash
# 1. Test SSH manually
ssh root@xx.177.xx.73

# 2. If using key file
ssh -i ~/.ssh/your_key root@xx.177.xx.73

# 3. Check SSH config
cat ~/.ssh/config

# 4. Add to deploy.yml if needed
ssh:
  user: root
  keys:
    - ~/.ssh/your_key
```

### Issue: "Database connection failed"

**Symptoms:**
```
could not connect to server
```

**Solutions:**

```bash
# 1. Verify DATABASE_URL in secrets
source .kamal/secrets
echo $DATABASE_URL

# 2. Test connection from local machine
psql $DATABASE_URL

# 3. Check if it's set in container
kamal app exec "env | grep DATABASE"

# 4. Test from container
kamal app exec "bin/rails runner 'ActiveRecord::Base.connection.execute(\"SELECT 1\")'"

# 5. Check firewall rules on DigitalOcean
# - Database should allow connections from your VPS IP
```

### Issue: "Container won't start"

**Solutions:**

```bash
# 1. Check logs
kamal app logs

# 2. Check container status
kamal app details

# 3. Try starting manually to see error
kamal app exec "docker run --rm davidslvuk/microblog-backend:latest"

# 4. Check if ports are in use
kamal app exec "netstat -tulpn | grep 80"

# 5. Check disk space
kamal app exec "df -h"
```

### Issue: "SSL certificate not working"

**Symptoms:**
```
Certificate error or HTTP instead of HTTPS
```

**Solutions:**

```bash
# 1. Check DNS is pointing to server
dig microblog-be.davidslv.uk

# 2. Verify proxy config in deploy.yml
grep -A 3 "proxy:" config/deploy.yml

# 3. Check if ports 80/443 are open
kamal app exec "netstat -tulpn | grep -E '80|443'"

# 4. Check Let's Encrypt logs
kamal app exec "docker logs traefik"  # or whatever proxy you're using
```

---

## Universal Deployment Pattern

This pattern works for **any application**, not just Rails:

### The Universal Flow

```mermaid
graph TB
    A[Source Code] --> B[Build Tool]
    B --> C[Docker Image]
    C --> D[Registry]
    D --> E[Deployment Tool]
    E --> F[Server]
    F --> G[Container]

    H[Secrets File] --> E
    I[Config File] --> E

    E --> G

    style A fill:#e1f5ff
    style G fill:#c8e6c9
    style H fill:#fff3e0
```

### Step-by-Step for Any Framework

#### 1. Create Dockerfile

```dockerfile
# Example for Node.js
FROM node:20-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM node:20-alpine
WORKDIR /app
COPY --from=build /app/dist ./dist
COPY package*.json ./
RUN npm ci --production
CMD ["node", "dist/index.js"]
```

#### 2. Create Kamal Config (config/deploy.yml)

```yaml
service: myapp
image: username/myapp

servers:
  web:
    hosts:
      - <%= ENV.fetch("SERVER_HOST", "1.2.3.4") %>

registry:
  server: docker.io
  username: <%= ENV.fetch("DOCKER_USERNAME", "") %>
  password:
    - KAMAL_REGISTRY_PASSWORD

env:
  secret:
    - DATABASE_URL
    - API_KEY
  clear:
    NODE_ENV: production
    PORT: 3000

proxy:
  ssl: true
  host: <%= ENV.fetch("DOMAIN", "app.example.com") %>
```

#### 3. Create Secrets File (.kamal/secrets)

```bash
#!/bin/bash
KAMAL_REGISTRY_PASSWORD=$DOCKER_HUB_TOKEN
DATABASE_URL=$PRODUCTION_DATABASE_URL
API_KEY=$PRODUCTION_API_KEY
```

#### 4. Set Environment Variables

```bash
export DOCKER_HUB_TOKEN=your_token
export SERVER_HOST=1.2.3.4
export DOMAIN=app.example.com
export PRODUCTION_DATABASE_URL=postgresql://...
export PRODUCTION_API_KEY=your_key
```

#### 5. Deploy

```bash
kamal setup    # First time only
kamal build
kamal push
kamal deploy
```

### Framework-Specific Notes

**Rails:**
- Need `RAILS_MASTER_KEY` and `SECRET_KEY_BASE`
- Use `config/master.key` and `config/credentials.yml.enc`

**Node.js:**
- Typically need `DATABASE_URL`, `JWT_SECRET`, `API_KEYS`
- No master key concept

**Python (Django):**
- Need `SECRET_KEY` (similar to Rails `SECRET_KEY_BASE`)
- Use `DJANGO_SECRET_KEY` environment variable

**Go:**
- Typically use environment variables directly
- No special secret management needed

**PHP:**
- Use `.env` file (but don't commit it)
- Or use environment variables

---

## Summary: The Complete Picture

### The Deployment Journey

```
┌─────────────────────────────────────────────────────────────┐
│                    YOUR LOCAL MACHINE                       │
│                                                             │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐  │
│  │ Source Code  │───▶│ Kamal CLI    │───▶│ Docker Build │  │
│  │              │    │              │    │              │  │
│  │ - app/       │    │ Reads:       │    │ Creates:     │  │
│  │ - config/    │    │ - deploy.yml │    │ - Image      │  │
│  │ - Dockerfile │    │ - secrets    │    │ - Tagged     │  │
│  └──────────────┘    └──────────────┘    └──────────────┘  │
│                                                             │
│  ┌──────────────┐                                          │
│  │ Secrets:     │                                          │
│  │ - master.key │                                          │
│  │ - .kamal/    │                                          │
│  └──────────────┘                                          │
└─────────────────────────────────────────────────────────────┘
                            │
                            │ docker push
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                    DOCKER REGISTRY                          │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  davidslvuk/microblog-backend:latest                 │  │
│  │  (Your Docker Image)                                 │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                            │
                            │ SSH + docker pull
                            ▼
┌─────────────────────────────────────────────────────────────┐
│              DIGITAL OCEAN VPS (xx.177.xx.73)              │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  Docker Container                                     │  │
│  │                                                       │  │
│  │  ENV Variables:                                      │  │
│  │  - RAILS_MASTER_KEY=...                              │  │
│  │  - SECRET_KEY_BASE=...                               │  │
│  │  - DATABASE_URL=...                                  │  │
│  │  - RAILS_ENV=production                              │  │
│  │                                                       │  │
│  │  Your Application Running                            │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  Traefik (SSL Proxy)                                 │  │
│  │  - Handles HTTPS                                     │  │
│  │  - Routes to container                               │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                            │
                            │ HTTPS
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                      INTERNET                                │
│                    (Your Users)                              │
└─────────────────────────────────────────────────────────────┘
```

### Key Takeaways

1. **Secrets never leave your control:**
   - Stored locally in `.kamal/secrets`
   - Injected at deployment time
   - Never committed to git

2. **Docker images are portable:**
   - Built once, run anywhere
   - Registry stores them
   - Server pulls them

3. **Kamal orchestrates everything:**
   - Builds images
   - Pushes to registry
   - Deploys to server
   - Manages containers

4. **Environment variables bridge the gap:**
   - Connect your code to configuration
   - Secrets injected securely
   - Clear values in config files

5. **The flow is always the same:**
   - Build → Push → Deploy
   - Works for any framework
   - Same pattern everywhere

---

## Quick Reference Card

### Essential Commands

```bash
# Setup (first time)
kamal setup

# Deploy
kamal build && kamal push && kamal deploy

# View logs
kamal app logs -f

# Rails console
kamal console

# Check status
kamal app details
```

### Essential Files

- `config/deploy.yml` - Deployment configuration
- `.kamal/secrets` - Secrets (never commit!)
- `config/master.key` - Rails master key (never commit!)
- `.env.deploy` - Environment variables (never commit!)
- `Dockerfile` - Container definition

### Essential Environment Variables

```bash
DOCKER_HUB_TOKEN=...           # Docker registry auth
BACKEND_HOST=...               # Server IP or domain
FRONTEND_URL=...               # Frontend domain
PRODUCTION_DATABASE_URL=...    # Database connection
```

---

**Remember:** The key to successful deployments is understanding the flow. Once you see how secrets move from your local machine → Kamal → Docker → Container, everything becomes clear!

**You're not useless** - this is complex! But now you have a systematic approach that works every time. 🚀

