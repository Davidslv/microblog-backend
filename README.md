# Microblog

A high-performance microblogging platform built with Ruby on Rails, designed to handle millions of users and posts. Think Twitter/X but optimized for scale.

**Repository**: [https://github.com/Davidslv/microblog](https://github.com/Davidslv/microblog)

**Frontend Application**: [https://github.com/Davidslv/microblog-frontend](https://github.com/Davidslv/microblog-frontend)

## 📋 Table of Contents

- [About](#about)
- [Features](#features)
- [Architecture](#architecture)
- [Tech Stack](#tech-stack)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Running the Application](#running-the-application)
- [Testing](#testing)
- [Documentation](#documentation)
- [Development Workflow](#development-workflow)
- [Performance](#performance)
- [Contributing](#contributing)
- [Troubleshooting](#troubleshooting)
- [License](#license)
- [Environment Variables Reference](#environment-variables-reference)
- [API Endpoints](#api-endpoints)
- [Support](#support)
- [Quick Reference](#quick-reference)

---

## About

Microblog is a social media platform where users can:
- **Post** short messages (up to 200 characters)
- **Reply** to posts to create conversations
- **Follow** other users to see their posts in your timeline
- **View** personalized feeds (timeline, following, or all posts)

The application is optimized for large-scale performance, with proven capabilities handling 1M+ users, 50M+ follow relationships, and high-concurrency load.

---

## Features

### Core Functionality
- ✅ User authentication (password-based)
- ✅ Post creation and replies
- ✅ User following system
- ✅ Personalized timeline feeds
- ✅ User profiles with stats (posts, followers, following)
- ✅ Account settings and management

### Performance Optimizations
- ✅ Cursor-based pagination (no OFFSET)
- ✅ Composite database indexes
- ✅ Optimized feed queries (JOIN instead of large IN clauses)
- ✅ Counter caches for follower/following counts
- ✅ PostgreSQL for primary database
- ✅ Background job processing (Solid Queue)

### User Experience
- ✅ Modern, responsive UI (Tailwind CSS)
- ✅ Real-time updates (Hotwire/Turbo)
- ✅ Character counter for posts
- ✅ Smooth pagination with "Load More"

---

## Architecture

### Three-Layer Architecture

This application follows a **three-layer architecture** with independent frontend, backend, and database layers:

```
┌─────────────────────────────────────────────────────────────┐
│              PRESENTATION LAYER                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  React SPA (Frontend)                                  │  │
│  │  Repository: github.com/Davidslv/microblog-frontend    │  │
│  │  - React Components                                    │  │
│  │  - JWT Authentication                                  │  │
│  │  - API Client (Axios)                                  │  │
│  └──────────────────────────────────────────────────────┘  │
└───────────────────────────────────────┼──────────────────────┘
                                        │ HTTP/REST
                                        │ JWT Token
┌───────────────────────────────────────┼──────────────────────┐
│         APPLICATION LAYER (This App)  │                      │
│  ┌───────────────────────────────────▼──────────────────┐  │
│  │  Rails API (Port 3000)                               │  │
│  │  ┌──────────────┐  ┌──────────────┐                  │  │
│  │  │   Puma       │  │  Solid Queue │                  │  │
│  │  │  (Web Server)│  │ (Background) │                  │  │
│  │  │  25 threads  │  │   Jobs       │                  │  │
│  │  └──────┬───────┘  └──────┬───────┘                  │  │
│  │  - /api/v1/* endpoints                                │  │
│  │  - JWT Authentication                                  │  │
│  │  - JSON responses                                      │  │
│  └─────────┼──────────────────┼──────────────────────────┘  │
└────────────┼──────────────────┼────────────────────────────┘
             │                  │
             │ (25 connections) │
             │                  │
┌────────────▼──────────────────▼────────────────────────────┐
│              DATA LAYER                                     │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  PostgreSQL (Primary Database)                      │  │
│  │  - Users, Posts, Follows                             │  │
│  │  - Counter caches                                    │  │
│  │  - Feed entries (fan-out)                            │  │
│  └──────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  Solid Cache/Queue/Cable (PostgreSQL)                 │  │
│  │  - Background jobs                                    │  │
│  │  - Cache storage                                      │  │
│  │  - WebSocket connections                              │  │
│  │  - Separate databases with dedicated credentials      │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

**Key Benefits:**
- **Independent Scaling**: Scale frontend (CDN) and backend (API servers) independently
- **Technology Evolution**: Frontend and backend can evolve independently
- **Team Autonomy**: Frontend and backend teams work independently with clear API contracts
- **Faster Iteration**: Frontend changes don't require backend deploys
- **Cost Optimization**: Scale expensive components (backend) separately from cheap ones (static frontend)

**📚 See [Three-Layer Architecture Implementation](docs/048_THREE_LAYER_ARCHITECTURE_IMPLEMENTATION.md) for detailed documentation.**

### Data Model

**Core Entities:**
- **Users**: Authentication, profiles, settings
- **Posts**: Content (200 chars), replies (via parent_id)
- **Follows**: Many-to-many follow relationships

**Key Relationships:**
- Users → Posts (one-to-many, author)
- Users → Follows (many-to-many, self-referential)
- Posts → Posts (self-referential, replies)

See [Database Diagram](docs/001_DATABASE_DIAGRAM.md) for detailed schema.

### Request Flow

**API Request (from React Frontend):**
```
React Frontend
    ↓ HTTP/REST + JWT Token
Rails API Controller (/api/v1/*)
    ↓
JWT Authentication Middleware
    ↓
ActiveRecord Query (optimized)
    ↓
PostgreSQL
    ↓
JSON Response
    ↓
React Frontend (renders UI)
```

**HTML Request (legacy/development):**
```
Browser
    ↓ HTTP
Puma (25 threads)
    ↓
Rails Controller
    ↓
ActiveRecord Query (optimized)
    ↓
PostgreSQL
    ↓
HTML Response (ERB templates)
```

---

## Tech Stack

### Backend
- **Ruby**: 3.4.7 (see `.ruby-version`)
- **Rails**: 8.1.1
- **Database**: PostgreSQL (primary), PostgreSQL (cache/queue/cable for horizontal scaling)
- **Web Server**: Puma (25 threads)
- **Background Jobs**: Solid Queue (Rails 8 built-in)

### Frontend (Separate Repository)
- **Framework**: React 18+ with Vite
- **Routing**: React Router DOM
- **HTTP Client**: Axios
- **Styling**: Tailwind CSS
- **Testing**: Vitest (unit), Playwright (E2E)
- **Repository**: [https://github.com/Davidslv/microblog-frontend](https://github.com/Davidslv/microblog-frontend)

### Legacy Frontend (This Repository)
- **CSS Framework**: Tailwind CSS
- **JavaScript**: Hotwire (Turbo + Stimulus)
- **Asset Pipeline**: Propshaft
- **Note**: Legacy HTML views are still available but the primary frontend is the React SPA

### Testing
- **Framework**: RSpec
- **Matchers**: Shoulda Matchers
- **Factories**: FactoryBot
- **Browser Testing**: Capybara + Selenium

### Development Tools
- **Code Quality**: RuboCop (Omakase)
- **Security**: Brakeman, Bundler Audit
- **Debugging**: Rails debug gem

---

## Prerequisites

You can run the application in two ways:

### Option 1: Docker (Recommended for Newcomers)

**Docker Setup** (easiest - no local dependencies needed):
- **Docker Desktop** (macOS/Windows) or **Docker Engine** (Linux)
- **Docker Compose** (usually included with Docker Desktop)

**Benefits:**
- ✅ No need to install Ruby, PostgreSQL, or Node.js locally
- ✅ Consistent environment across all developers
- ✅ Easy to scale with multiple instances
- ✅ Production-like setup

See [Docker Workflow Guide](docs/039_DOCKER_WORKFLOW.md) for detailed instructions.

### Option 2: Local Development

**Local Setup** (requires local dependencies):
- **Ruby** 3.4.7 (check with `ruby --version` - see `.ruby-version` file)
- **PostgreSQL** 14+ (check with `psql --version`)
- **Node.js** 18+ (for Tailwind CSS, check with `node --version`)
- **Bundler** (install with `gem install bundler`)

### macOS Setup

```bash
# Install Ruby (using rbenv - recommended)
brew install rbenv ruby-build
rbenv install 3.4.7
rbenv global 3.4.7

# Verify installation
ruby --version  # Should show 3.4.7

# Install PostgreSQL
brew install postgresql@16
brew services start postgresql@16

# Verify PostgreSQL
psql --version  # Should show PostgreSQL 14+

# Install Node.js
brew install node

# Verify Node.js
node --version  # Should show v18 or higher
```

### Environment Variables Setup

The application uses `dotenv-rails` to load environment variables from a `.env` file in development and test environments.

1. **Create the `.env` file:**
   ```bash
   # If .env.example exists, copy it
   cp .env.example .env

   # Otherwise, create .env manually with these variables:
   ```

2. **Required environment variables** (minimum for local development):
   ```bash
   # Primary Database
   DATABASE_HOST=localhost
   DATABASE_PORT=5432
   DATABASE_USERNAME=postgres
   DATABASE_PASSWORD=postgres

   # Solid Databases (Cache, Queue, Cable)
   CACHE_DB_USERNAME=microblog_cache
   CACHE_DB_PASSWORD=cache_password
   QUEUE_DB_USERNAME=microblog_queue
   QUEUE_DB_PASSWORD=queue_password
   CABLE_DB_USERNAME=microblog_cable
   CABLE_DB_PASSWORD=cable_password
   ```

3. **Optional environment variables:**
   ```bash
   # Rails secrets (auto-generated in development if not set)
   # RAILS_MASTER_KEY=your_master_key
   # SECRET_KEY_BASE=your_secret_key_base

   # Frontend URL (required for CORS in production)
   # FRONTEND_URL=https://your-frontend-domain.com

   # Run jobs in Puma (recommended)
   SOLID_QUEUE_IN_PUMA=true

   # Disable rate limiting (development only)
   # DISABLE_RACK_ATTACK=false
   ```

4. **For production**, set environment variables directly in your deployment platform (Heroku, AWS, Kamal, etc.) - do not use `.env` files in production.

**📚 See:**
- [Solid Databases Setup Guide](docs/037_SOLID_DATABASES_SETUP.md) for detailed database configuration
- [Deployment Guide](docs/055_DEPLOYMENT_GUIDE.md) for production environment variables

### Linux Setup

```bash
# Install Ruby (using rbenv)
sudo apt-get update
sudo apt-get install -y git curl libssl-dev libreadline-dev zlib1g-dev \
  autoconf bison build-essential libyaml-dev libreadline-dev libncurses5-dev \
  libffi-dev libgdbm-dev

# Install rbenv
curl -fsSL https://github.com/rbenv/rbenv-installer/raw/HEAD/bin/rbenv-installer | bash
echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> ~/.bashrc
echo 'eval "$(rbenv init -)"' >> ~/.bashrc
source ~/.bashrc

# Install Ruby
rbenv install 3.4.7
rbenv global 3.4.7

# Verify installation
ruby --version  # Should show 3.4.7

# Install PostgreSQL
sudo apt-get install -y postgresql postgresql-contrib libpq-dev
sudo systemctl start postgresql
sudo systemctl enable postgresql

# Verify PostgreSQL
psql --version  # Should show PostgreSQL 14+

# Install Node.js
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs

# Verify Node.js
node --version  # Should show v18 or higher
```

### Windows Setup

**Option 1: Use WSL2 (Windows Subsystem for Linux) - Recommended**

1. Install WSL2: Follow [Microsoft's WSL2 installation guide](https://docs.microsoft.com/en-us/windows/wsl/install)
2. Install Ubuntu from Microsoft Store
3. Follow the Linux Setup instructions above within WSL2

**Option 2: Native Windows Setup**

```powershell
# Install Ruby using RubyInstaller
# Download from: https://rubyinstaller.org/downloads/
# Install Ruby+Devkit 3.4.7

# Install PostgreSQL
# Download from: https://www.postgresql.org/download/windows/
# Install PostgreSQL 14 or higher

# Install Node.js
# Download from: https://nodejs.org/
# Install Node.js 18 or higher

# Install Bundler
gem install bundler
```

**Note:** Docker is recommended for Windows users as it provides a consistent environment.

---

## Installation

### 1. Clone the Repository

```bash
git clone https://github.com/Davidslv/microblog.git
cd microblog
```

**Note:** For the frontend application, see the [frontend repository](https://github.com/Davidslv/microblog-frontend).

### Choose Your Installation Method

---

## 🐳 Docker Installation (Recommended)

**Best for:** Newcomers, consistent environments, easy scaling

### Quick Start with Docker

```bash
# 1. Start all services (database, web server, load balancer)
docker compose up -d

# 2. Run database migrations (one-time setup)
docker compose run --rm migrate

# 3. Access the application
# Main app: http://localhost (via Traefik load balancer)
# Direct: http://localhost:3000
# Traefik dashboard: http://localhost:8080
```

### Running Scripts in Docker

```bash
# Run a script (e.g., load test seeding)
docker compose exec web-1 bin/rails runner script/load_test_seed.rb

# Get interactive shell
docker compose exec web-1 bash

# Rails console
docker compose exec web-1 bin/rails console

# Run migrations
docker compose exec web-1 bin/rails db:migrate
```

### Scaling with Docker

```bash
# Run multiple web instances (for load testing)
docker compose up -d --scale web=3

# Check status
docker compose ps
```

**📚 Need more Docker help?** See:
- [Docker Workflow Guide](docs/039_DOCKER_WORKFLOW.md) - Complete Docker guide
- [Docker Compose Configuration](docs/038_DOCKER_COMPOSE_CONFIGURATION.md) - Configuration details

---

## 💻 Local Installation

**Best for:** Developers who prefer local development, faster iteration

### 2. Install Dependencies

```bash
# Install Ruby gems
bundle install

# Install JavaScript dependencies (if needed)
npm install
```

### 3. Set Up Environment Variables

The application uses `dotenv-rails` to load environment variables from a `.env` file.

```bash
# Create .env file (copy from example if it exists)
if [ -f .env.example ]; then
  cp .env.example .env
else
  # Create .env manually with required variables
  cat > .env << EOF
DATABASE_HOST=localhost
DATABASE_PORT=5432
DATABASE_USERNAME=postgres
DATABASE_PASSWORD=postgres
CACHE_DB_USERNAME=microblog_cache
CACHE_DB_PASSWORD=cache_password
QUEUE_DB_USERNAME=microblog_queue
QUEUE_DB_PASSWORD=queue_password
CABLE_DB_USERNAME=microblog_cable
CABLE_DB_PASSWORD=cable_password
SOLID_QUEUE_IN_PUMA=true
EOF
fi

# Edit .env with your local database credentials
# Update DATABASE_USERNAME, DATABASE_PASSWORD, etc. as needed
```

**Important:** The `.env` file is gitignored and should never be committed. Update the values to match your local PostgreSQL setup.

See [Solid Databases Setup Guide](docs/037_SOLID_DATABASES_SETUP.md) for detailed configuration.

### 4. Database Setup

```bash
# Step 1: Create primary PostgreSQL databases
createdb microblog_development
createdb microblog_test

# Step 2: Set up Solid databases (cache, queue, cable) with dedicated users
# This script creates PostgreSQL users and databases for Solid Cache, Queue, and Cable
RAILS_ENV=development ./script/setup_solid_databases.sh

# Step 3: Run migrations for primary database
rails db:migrate

# Step 4: Install Solid adapters (creates tables in their databases)
# These commands will prompt to overwrite files - answer 'yes' or use 'yes |' prefix
yes | bin/rails solid_cache:install
yes | bin/rails solid_queue:install
yes | bin/rails solid_cable:install

# (Optional) Load seed data
rails db:seed
```

**What this does:**
- Creates the main application database (`microblog_development`)
- Creates separate PostgreSQL databases for Solid Cache, Queue, and Cable
- Sets up dedicated PostgreSQL users with appropriate permissions
- Runs database migrations to create tables

**Note**: The application is configured for read replicas. In development, the same database is used for both primary and replica. See [Read Replicas Setup](docs/034_READ_REPLICAS_SETUP.md) for production configuration.

---

## Running the Application

### 🐳 Docker (Recommended)

**Start all services:**

```bash
# Start database, web server, and load balancer
docker compose up -d

# View logs
docker compose logs -f web

# Access application
# Main: http://localhost (via Traefik)
# Direct: http://localhost:3000
```

**Common Docker commands:**

```bash
# Stop services
docker compose down

# Restart services
docker compose restart

# Scale to multiple instances
docker compose up -d --scale web=3

# View status
docker compose ps
```

**Running scripts in Docker:**

```bash
# Run a script
docker compose exec web-1 bin/rails runner script/load_test_seed.rb

# Rails console
docker compose exec web-1 bin/rails console

# Interactive shell
docker compose exec web-1 bash
```

See [Docker Workflow Guide](docs/039_DOCKER_WORKFLOW.md) for complete Docker instructions.

### 💻 Local Development

**Start the server and Tailwind CSS watcher:**

```bash
bin/dev
```

This runs:
- Rails server (http://localhost:3000)
- Tailwind CSS watcher (for CSS compilation)

**Or start separately:**

```bash
# Terminal 1: Rails server
rails server

# Terminal 2: Tailwind CSS (if needed)
bin/rails tailwindcss:watch
```

**Start background jobs (optional):**

```bash
# Terminal 3: Background job processor
bin/jobs
```

Or set `SOLID_QUEUE_IN_PUMA=true` to run jobs in the Puma process.

### Create Test Users

```bash
# Open Rails console
rails console

# Create users
user1 = User.create!(username: "alice", password: "password123", description: "Hello!")
user2 = User.create!(username: "bob", password: "password123", description: "Bob here!")

# Create posts
user1.posts.create!(content: "My first post!")
user2.posts.create!(content: "Just joined!")

# Follow relationships
user1.follow(user2)
```

### Quick Login (Development Only)

**For HTML Views (Legacy):**
For development, use the temporary login route:

**With Docker:**
```bash
# Visit: http://localhost/dev/login/:user_id
# Example: http://localhost/dev/login/1
```

**With Local Development:**
```bash
# Visit: http://localhost:3000/dev/login/:user_id
# Example: http://localhost:3000/dev/login/1
```

This sets the session to log you in as that user.

**For React Frontend:**
Use the login page at `http://localhost:5173/login` (or your frontend URL). The frontend uses JWT token-based authentication via the `/api/v1/login` endpoint.

### Production Mode

```bash
# Precompile assets
rails assets:precompile

# Start server
rails server -e production

# Or use Kamal for deployment
kamal deploy
```

---

## Testing

### Run Tests

```bash
# Run all tests
bundle exec rspec

# Run specific test file
bundle exec rspec spec/models/user_spec.rb

# Run with coverage
COVERAGE=true bundle exec rspec
```

### Test Structure

```
spec/
├── models/          # Model specs
├── features/        # End-to-end feature specs
├── requests/        # API/controller specs
├── factories/       # FactoryBot factories
└── support/         # Test helpers
```

### Load Testing

See [Load Testing Guide](docs/005_LOAD_TESTING.md) for details.

**Quick load test:**

```bash
# Using k6
k6 run load_test/k6_baseline.js

# Using wrk
wrk -t8 -c150 -d30s http://localhost:3000/
```

---

## Documentation

All documentation is located in the `docs/` directory, organized chronologically and by topic.

### Quick Start Guide
- [Development Guide](docs/002_DEVELOPMENT.md) - Setup and development workflow
- [Docker Workflow Guide](docs/039_DOCKER_WORKFLOW.md) - Complete Docker guide for newcomers
- [Docker Compose Configuration](docs/038_DOCKER_COMPOSE_CONFIGURATION.md) - Docker setup details
- [Database Diagram](docs/001_DATABASE_DIAGRAM.md) - Schema and relationships
- [Deployment Guide](docs/055_DEPLOYMENT_GUIDE.md) - Production deployment with Kamal

### Architecture & Design
- [Three-Layer Architecture](docs/048_THREE_LAYER_ARCHITECTURE_IMPLEMENTATION.md) - **IMPORTANT** Architecture overview
- [JWT Authentication](docs/053_PHASE_2_JWT_AUTHENTICATION.md) - JWT implementation details
- [Frontend Setup](docs/054_PHASE_3_FRONTEND_SETUP.md) - React frontend integration

### Performance & Optimization
- [Performance Analysis](docs/004_PERFORMANCE_ANALYSIS.md) - Initial analysis
- [Performance at Scale](docs/022_PERFORMANCE_AT_SCALE.md) - 1M user scale
- [Load Testing Guide](docs/005_LOAD_TESTING.md) - How to load test
- [Monitoring Guide](docs/006_MONITORING_GUIDE.md) - Monitor performance

### Architecture & Design
- [Architecture Proposals](docs/017_ARCHITECTURE_AND_FEED_PROPOSALS.md) - Feed optimization proposals
- [Query Plan Analysis](docs/018_QUERY_PLAN_EXPLANATION.md) - Database query performance

### Database
- [PostgreSQL Setup](docs/014_POSTGRESQL_SETUP.md) - Database configuration
- [Database Optimization](docs/010_DATABASE_OPTIMIZATION.md) - Indexes and optimization
- [Counter Cache Guide](docs/023_COUNTER_CACHE_INCREMENT_LOGIC.md) - Counter cache logic

### See [docs/README.md](docs/README.md) for complete documentation index.

---

## Development Workflow

### 1. Create a Feature Branch

```bash
git checkout -b feature/your-feature-name
```

### 2. Make Changes

- Write code following Rails conventions
- Add tests for new features
- Update documentation if needed

### 3. Run Tests

```bash
bundle exec rspec
```

### 4. Check Code Quality

```bash
# RuboCop
bundle exec rubocop

# Security audit
bundle exec brakeman
bundle exec bundler-audit
```

### 5. Commit Changes

```bash
git add .
git commit -m "Add feature: description"
```

Follow conventional commit messages:
- `feat: Add user search`
- `fix: Fix pagination bug`
- `docs: Update README`
- `perf: Optimize feed query`

### 6. Push and Create Pull Request

```bash
git push origin feature/your-feature-name
```

---

## Performance

### Current Performance Metrics

**At 1M User Scale:**
- Users: 1,091,000
- Posts: 73,817
- Follows: 50,368,293
- User profile page: <100ms (with counter cache)
- Feed queries: 200-500ms (depends on follow count)

**Load Testing Results:**
- Baseline: 30-50 RPS
- With optimizations: 50-100 RPS
- Target: 200+ RPS (requires feed optimization)

### Performance Optimizations

1. **Counter Caches**: `followers_count`, `following_count`, `posts_count`
2. **Composite Indexes**: `(author_id, created_at DESC)` for posts
3. **Cursor Pagination**: SQL-based, no OFFSET
4. **Optimized Queries**: JOIN instead of large IN clauses
5. **Connection Pooling**: 25 connections (tuned for PostgreSQL)

### Monitoring

```bash
# Health check
curl http://localhost:3000/health

# Puma stats (development)
curl http://localhost:3000/puma/stats

# PostgreSQL query stats
rake db:stats:slow_queries
```

See [Monitoring Guide](docs/006_MONITORING_GUIDE.md) for details.

---

## Contributing

### Code Style

- Follow [Rails Omakase](https://github.com/rails/rubocop-rails-omakase) style guide
- Run `bundle exec rubocop` before committing
- Use meaningful variable and method names
- Add comments for complex logic

### Testing

- Write tests for all new features
- Aim for >80% code coverage
- Test edge cases and error conditions
- Use FactoryBot for test data

### Documentation

- Update README if adding features
- Add docs to `docs/` for complex features
- Document API changes
- Keep code comments up to date

### Pull Request Process

1. Create feature branch from `main`
2. Write tests and implementation
3. Ensure all tests pass
4. Update documentation
5. Create PR with clear description
6. Request review from team

---

## Troubleshooting

### Database Connection Issues

**With Docker:**

```bash
# Check database container is running
docker compose ps db

# Check database logs
docker compose logs db

# Test connection from web container
docker compose exec web-1 bin/rails runner "ActiveRecord::Base.connection.execute('SELECT 1')"

# Connect to database
docker compose exec db psql -U postgres -d microblog_development
```

**With Local Development:**

```bash
# Check PostgreSQL is running
brew services list  # macOS
sudo systemctl status postgresql  # Linux

# Test connection
psql -h localhost -U $USER -d microblog_development
```

See [Docker Compose Configuration](docs/038_DOCKER_COMPOSE_CONFIGURATION.md) for Docker-specific troubleshooting.

### Asset Compilation Issues

```bash
# Clear cache
rails tmp:clear

# Rebuild Tailwind
bin/rails tailwindcss:build
```

### Background Jobs Not Running

**With Docker:**

```bash
# Jobs run automatically if SOLID_QUEUE_IN_PUMA=true (default)
# Check logs
docker compose logs web | grep -i "solid"

# Or run jobs in separate container (if configured)
docker compose up jobs
```

**With Local Development:**

```bash
# Check if job processor is running
ps aux | grep "bin/jobs"

# Start job processor
bin/jobs

# Or set SOLID_QUEUE_IN_PUMA=true
```

### Migration Issues

```bash
# Rollback migration
rails db:rollback

# Check migration status
rails db:migrate:status

# Reset database (WARNING: deletes all data)
rails db:reset

# Drop and recreate databases
rails db:drop db:create db:migrate
```

### Solid Databases Setup Issues

**Problem:** Solid databases not created or connection errors

```bash
# Re-run the setup script
RAILS_ENV=development ./script/setup_solid_databases.sh

# Check if databases exist
psql -l | grep microblog

# Check if users exist
psql -U postgres -c "\du" | grep microblog

# Reinstall Solid adapters
yes | bin/rails solid_cache:install
yes | bin/rails solid_queue:install
yes | bin/rails solid_cable:install
```

### CORS Issues

**Problem:** Frontend can't make API requests (CORS errors)

**Development:**
- Ensure frontend is running on `http://localhost:3001`, `http://localhost:5173`, or `http://localhost:5174`
- Check browser console for specific CORS error messages

**Production:**
- Set `FRONTEND_URL` environment variable to your frontend domain
- Ensure `FRONTEND_URL` matches exactly (including protocol: `https://`)
- Check `config/initializers/cors.rb` for configuration

**See:** [CORS Troubleshooting Guide](https://github.com/Davidslv/microblog-frontend/blob/main/docs/004_CORS_TROUBLESHOOTING.md)

### Port Already in Use

```bash
# Find process using port 3000
lsof -i :3000  # macOS/Linux
netstat -ano | findstr :3000  # Windows

# Kill the process
kill -9 <PID>  # macOS/Linux
taskkill /PID <PID> /F  # Windows

# Or use a different port
rails server -p 3001
```

### Gem Installation Issues

```bash
# Clear bundler cache
bundle clean --force

# Reinstall gems
bundle install

# Update bundler
gem update bundler
```

---

## License

This project is open source. Please check the repository for the specific license file.

---

## Environment Variables Reference

### Required for Production

| Variable | Description | Example |
|----------|-------------|---------|
| `RAILS_MASTER_KEY` | Rails master key (from `config/master.key`) | `abc123...` |
| `SECRET_KEY_BASE` | Rails secret key base | `xyz789...` |
| `DATABASE_URL` | PostgreSQL connection string | `postgresql://user:pass@host:5432/db` |
| `FRONTEND_URL` | Frontend domain (required for CORS) | `https://microblog.example.com` |

### Optional Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `RAILS_ENV` | Rails environment | `development` |
| `SOLID_QUEUE_IN_PUMA` | Run jobs in Puma process | `true` |
| `DISABLE_RACK_ATTACK` | Disable rate limiting | `false` |
| `DATABASE_HOST` | Database host | `localhost` |
| `DATABASE_PORT` | Database port | `5432` |
| `DATABASE_USERNAME` | Database username | `postgres` |
| `DATABASE_PASSWORD` | Database password | (empty) |
| `CACHE_DB_USERNAME` | Solid Cache database user | `microblog_cache` |
| `CACHE_DB_PASSWORD` | Solid Cache database password | (empty) |
| `QUEUE_DB_USERNAME` | Solid Queue database user | `microblog_queue` |
| `QUEUE_DB_PASSWORD` | Solid Queue database password | (empty) |
| `CABLE_DB_USERNAME` | Solid Cable database user | `microblog_cable` |
| `CABLE_DB_PASSWORD` | Solid Cable database password | (empty) |

**📚 See [Deployment Guide](docs/055_DEPLOYMENT_GUIDE.md) for production environment setup.**

---

## API Endpoints

The backend provides RESTful JSON API endpoints under `/api/v1/*`. All endpoints return JSON and require JWT authentication (except login and signup).

### Authentication
- `POST /api/v1/login` - User login (returns JWT token)
- `POST /api/v1/refresh` - Refresh JWT token
- `DELETE /api/v1/logout` - User logout
- `GET /api/v1/me` - Get current authenticated user

### Users
- `POST /api/v1/signup` - Create new user account (public)
- `GET /api/v1/users/:id` - Get user profile
- `POST /api/v1/users` - Create user (alternative to signup)
- `PATCH /api/v1/users/:id` - Update user (description, password) - requires authentication
- `DELETE /api/v1/users/:id` - Delete user account - requires authentication

### Posts
- `GET /api/v1/posts` - Get posts feed (query params: `filter`, `cursor`)
  - `filter`: `all`, `following`, `timeline` (default: `all`)
  - `cursor`: Pagination cursor (from previous response)
- `POST /api/v1/posts` - Create post (requires authentication)
- `GET /api/v1/posts/:id` - Get post detail with replies
- `GET /api/v1/posts/:id/replies` - Get replies to a post
- `POST /api/v1/posts/:id/report` - Report a post (requires authentication)

### Follows
- `POST /api/v1/users/:user_id/follow` - Follow user (requires authentication)
- `DELETE /api/v1/users/:user_id/follow` - Unfollow user (requires authentication)

### Admin (requires admin authentication)
- `POST /api/v1/admin/posts/:id/redact` - Redact a post
- `POST /api/v1/admin/posts/:id/unredact` - Unredact a post
- `GET /api/v1/admin/posts/:id/reports` - Get reports for a post

### CORS Configuration

The API supports CORS for cross-origin requests from the frontend:

- **Development**: Automatically allows `http://localhost:3001`, `http://localhost:5173`, `http://localhost:5174`
- **Production**: Requires `FRONTEND_URL` environment variable to be set

**Example production setup:**
```bash
export FRONTEND_URL=https://your-frontend-domain.com
```

**📚 See:**
- [Frontend Repository](https://github.com/Davidslv/microblog-frontend) for API client implementation
- [CORS Troubleshooting](https://github.com/Davidslv/microblog-frontend/blob/main/docs/004_CORS_TROUBLESHOOTING.md) for frontend CORS issues

---

## Support

For questions or issues:
- Check [Documentation](docs/README.md) - Comprehensive documentation index
- Review [Performance Guides](docs/004_PERFORMANCE_ANALYSIS.md) - Performance optimization
- Check [Frontend Repository](https://github.com/Davidslv/microblog-frontend) - Frontend-specific issues
- Review [Troubleshooting](#troubleshooting) section above
- Check [GitHub Issues](https://github.com/Davidslv/microblog/issues) - Known issues and solutions

---

## Quick Reference

### Common Commands

```bash
# Start development server
bin/dev

# Run tests
bundle exec rspec

# Rails console
rails console

# Database console
rails dbconsole

# Check routes
rails routes | grep api

# View logs
tail -f log/development.log
```

### Docker Quick Commands

```bash
# Start all services
docker compose up -d

# View logs
docker compose logs -f web

# Run migrations
docker compose run --rm migrate

# Rails console
docker compose exec web-1 bin/rails console

# Stop services
docker compose down
```

---

**Happy coding! 🚀**
