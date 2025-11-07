# Deployment Command Cheat Sheet

> **Quick reference for all Kamal and Docker deployment commands**

---

## 🚀 Quick Start

```bash
# First time setup
kamal setup

# Standard deployment
kamal build && kamal push && kamal deploy

# View logs
kamal app logs -f
```

---

## 📋 Pre-Deployment

| Command | What It Does |
|---------|-------------|
| `kamal version` | Check Kamal version |
| `kamal config validate` | Validate deploy.yml configuration |
| `kamal app details` | Check server connection and status |
| `kamal deploy --dry-run` | See what would happen (no changes) |

---

## 🏗️ Build & Push

| Command | What It Does |
|---------|-------------|
| `kamal build` | Build Docker image locally |
| `kamal build --version v1.0.0` | Build with specific version tag |
| `kamal push` | Push image to Docker registry |
| `kamal build push` | Build and push in one command |

**What happens:**
1. `kamal build` → Reads Dockerfile → Builds image → Stores locally
2. `kamal push` → Authenticates with registry → Pushes image → Image available on registry

---

## 🚢 Deployment

| Command | What It Does |
|---------|-------------|
| `kamal deploy` | Deploy to production |
| `kamal deploy --version v1.0.0` | Deploy specific version |
| `kamal deploy --verbose` | Deploy with detailed output |
| `kamal deploy --skip-healthcheck` | Deploy without waiting for health check |
| `kamal rollback` | Rollback to previous version |
| `kamal rollback --version v0.9.0` | Rollback to specific version |

**What happens:**
1. Reads `config/deploy.yml`
2. Executes `.kamal/secrets` to get secrets
3. Connects to server via SSH
4. Pulls Docker image from registry
5. Stops old container (if exists)
6. Starts new container with ENV vars
7. Waits for health check
8. Removes old container if healthy

---

## 📦 Container Management

| Command | What It Does |
|---------|-------------|
| `kamal app details` | View running containers and status |
| `kamal app logs -f` | View logs (follow mode, like `tail -f`) |
| `kamal app logs --host 206.189.19.73` | View logs from specific server |
| `kamal app logs --since 1h` | View logs from last hour |
| `kamal app stop` | Stop application |
| `kamal app start` | Start application |
| `kamal app restart` | Restart application |

---

## 🗄️ Database Commands

| Command | What It Does |
|---------|-------------|
| `kamal app exec "bin/rails db:migrate"` | Run database migrations |
| `kamal app exec "bin/rails db:rollback"` | Rollback last migration |
| `kamal app exec "bin/rails dbconsole"` | Open database console |
| `kamal dbc` | Database console (if alias configured) |

---

## 💻 Rails Console

| Command | What It Does |
|---------|-------------|
| `kamal app exec "bin/rails console"` | Open Rails console |
| `kamal console` | Rails console (if alias configured) |
| `kamal app exec "bin/rails runner 'User.count'"` | Run one-off command |

---

## 🔐 Secrets Management

| Command | What It Does |
|---------|-------------|
| `kamal secrets show` | View secrets (⚠️ shows values!) |
| `kamal secrets remove` | Remove secrets from server |
| `kamal secrets copy` | Copy secrets to server |

**Note:** Secrets are managed in `.kamal/secrets` file locally.

---

## 🖥️ Server Setup

| Command | What It Does |
|---------|-------------|
| `kamal setup` | Initial server setup (installs Docker, etc.) |
| `kamal remove` | Remove everything from server |
| `kamal remove --confirmed` | Remove with confirmation |

---

## 📊 Monitoring

| Command | What It Does |
|---------|-------------|
| `kamal app details` | Check application status |
| `kamal app exec "docker stats"` | View container resource usage |
| `kamal app exec "df -h"` | Check disk usage |
| `kamal app exec "free -h"` | Check memory usage |
| `curl https://your-domain.com/up` | Check health endpoint |

---

## 🐛 Troubleshooting

| Command | What It Does |
|---------|-------------|
| `kamal app logs` | View all logs |
| `kamal app logs --timestamps` | View logs with timestamps |
| `kamal app exec "env"` | View all environment variables |
| `kamal app exec "env \| grep RAILS_MASTER_KEY"` | Check specific ENV var |
| `ssh root@206.189.19.73` | Test SSH connection manually |
| `kamal app exec "docker ps"` | Check Docker containers on server |
| `kamal app exec "docker images"` | View Docker images on server |
| `kamal app exec "docker logs microblog_web"` | View container logs directly |

---

## 🐳 Direct Docker Commands (on Server)

| Command | What It Does |
|---------|-------------|
| `kamal app exec "docker ps -a"` | List all containers |
| `kamal app exec "docker images"` | List all images |
| `kamal app exec "docker exec -it microblog_web bash"` | Enter running container |
| `kamal app exec "docker image prune -a"` | Remove unused images (cleanup) |
| `kamal app exec "docker system df"` | Check Docker disk usage |

---

## 📝 Common Workflows

### First Time Deployment

```bash
# 1. Set environment variables
export DOCKER_HUB_TOKEN=your_token
export BACKEND_HOST=206.189.19.73
export PRODUCTION_DATABASE_URL=postgresql://...

# 2. Source secrets (if using .env.deploy)
source .env.deploy

# 3. Setup server
kamal setup

# 4. Build, push, and deploy
kamal build
kamal push
kamal deploy

# 5. Run migrations
kamal app exec "bin/rails db:migrate"

# 6. Verify
kamal app details
curl http://206.189.19.73/up
```

### Regular Deployment

```bash
# Standard workflow
kamal build && kamal push && kamal deploy

# Or with migrations
kamal build && kamal push && kamal deploy && \
kamal app exec "bin/rails db:migrate"
```

### Debugging Deployment Issues

```bash
# 1. Check server connection
kamal app details

# 2. View logs
kamal app logs -f

# 3. Check environment variables
kamal app exec "env | grep -E 'RAILS|DATABASE|SECRET'"

# 4. Test database connection
kamal app exec "bin/rails runner 'ActiveRecord::Base.connection.execute(\"SELECT 1\")'"

# 5. Check container status
kamal app exec "docker ps"
```

### Rollback

```bash
# Rollback to previous version
kamal rollback

# Or specific version
kamal rollback --version v0.9.0

# Verify rollback
kamal app details
kamal app logs
```

---

## 🔍 Environment Variable Checklist

Before deploying, ensure these are set:

```bash
# Docker Registry
export DOCKER_HUB_TOKEN=your_docker_hub_token
export DOCKER_USERNAME=your_username
export DOCKER_REGISTRY=docker.io  # or registry.digitalocean.com

# Server Configuration
export BACKEND_HOST=206.189.19.73  # or your domain
export FRONTEND_URL=https://your-frontend.com

# Database
export PRODUCTION_DATABASE_URL=postgresql://user:pass@host:port/db

# Optional: Secret Key Base (if not using Rails credentials)
export SECRET_KEY_BASE=$(openssl rand -hex 64)
```

---

## 📁 Essential Files

| File | Purpose | Commit to Git? |
|------|---------|----------------|
| `config/deploy.yml` | Kamal deployment configuration | ✅ Yes |
| `.kamal/secrets` | Secrets file (shell script) | ❌ **NO** |
| `config/master.key` | Rails master key | ❌ **NO** |
| `.env.deploy` | Environment variables | ❌ **NO** |
| `Dockerfile` | Container definition | ✅ Yes |
| `.gitignore` | Should include secrets | ✅ Yes |

---

## 🎯 Quick Troubleshooting Guide

### "Missing RAILS_MASTER_KEY"
```bash
# Check if master.key exists
ls -la config/master.key

# Verify .kamal/secrets has it
cat .kamal/secrets | grep RAILS_MASTER_KEY

# Test secrets file
source .kamal/secrets && echo $RAILS_MASTER_KEY

# Check in container
kamal app exec "env | grep RAILS_MASTER_KEY"
```

### "Cannot connect to registry"
```bash
# Check token
echo $DOCKER_HUB_TOKEN

# Test login
docker login -u your_username -p $DOCKER_HUB_TOKEN

# Verify .kamal/secrets
cat .kamal/secrets | grep KAMAL_REGISTRY_PASSWORD
```

### "Database connection failed"
```bash
# Test DATABASE_URL
source .kamal/secrets && echo $DATABASE_URL

# Test from local
psql $DATABASE_URL

# Test from container
kamal app exec "bin/rails runner 'ActiveRecord::Base.connection.execute(\"SELECT 1\")'"
```

### "Container won't start"
```bash
# Check logs
kamal app logs

# Check status
kamal app details

# Check disk space
kamal app exec "df -h"

# Check ports
kamal app exec "netstat -tulpn | grep 80"
```

---

## 💡 Pro Tips

1. **Always test locally first:**
   ```bash
   docker build -t test-image .
   docker run --rm -e RAILS_ENV=production test-image
   ```

2. **Use version tags for rollbacks:**
   ```bash
   kamal build --version v1.0.0
   kamal deploy --version v1.0.0
   ```

3. **Monitor during deployment:**
   ```bash
   # Terminal 1: Deploy
   kamal deploy

   # Terminal 2: Watch logs
   kamal app logs -f
   ```

4. **Keep secrets secure:**
   - Never commit `.kamal/secrets`
   - Never commit `config/master.key`
   - Use password managers for production secrets
   - Rotate secrets regularly

5. **Use aliases in deploy.yml:**
   ```yaml
   aliases:
     console: app exec --interactive --reuse "bin/rails console"
     logs: app logs -f
   ```
   Then use: `kamal console` instead of the full command

---

## 📚 Related Documentation

- Full Guide: `docs/061_COMPLETE_DEPLOYMENT_SECRETS_GUIDE.md`
- Kamal Docs: https://kamal-deploy.org
- Docker Docs: https://docs.docker.com

---

**Print this and keep it handy! 📌**

