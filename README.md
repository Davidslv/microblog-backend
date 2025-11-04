# Microblog

A high-performance microblogging platform built with Ruby on Rails, designed to handle millions of users and posts. Think Twitter/X but optimized for scale.

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

### System Overview

```
┌─────────────────────────────────────────────────┐
│              Rails Application                   │
│  ┌──────────────┐  ┌──────────────┐            │
│  │   Puma       │  │  Solid Queue │            │
│  │  (Web Server)│  │ (Background) │            │
│  │  25 threads  │  │   Jobs       │            │
│  └──────┬───────┘  └──────┬───────┘            │
└─────────┼──────────────────┼────────────────────┘
          │                  │
          │ (25 connections) │
          │                  │
┌─────────▼──────────────────▼────────────────────┐
│              PostgreSQL                          │
│         (Primary Database)                       │
│  - Users, Posts, Follows                         │
│  - Counter caches                                │
└──────────────────────────────────────────────────┘
```

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

```
User Request
    ↓
Puma (25 threads)
    ↓
Rails Controller
    ↓
ActiveRecord Query (optimized)
    ↓
PostgreSQL
    ↓
Response (JSON/HTML)
```

---

## Tech Stack

### Backend
- **Ruby**: 3.x
- **Rails**: 8.1.1
- **Database**: PostgreSQL (primary), SQLite (cache/queue/cable)
- **Web Server**: Puma (25 threads)
- **Background Jobs**: Solid Queue (Rails 8 built-in)

### Frontend
- **CSS Framework**: Tailwind CSS
- **JavaScript**: Hotwire (Turbo + Stimulus)
- **Asset Pipeline**: Propshaft

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

Before you begin, ensure you have the following installed:

- **Ruby** 3.x (check with `ruby --version`)
- **PostgreSQL** 14+ (check with `psql --version`)
- **Node.js** 18+ (for Tailwind CSS, check with `node --version`)
- **Bundler** (install with `gem install bundler`)

### macOS Setup

```bash
# Install Ruby (using rbenv or rvm)
brew install rbenv
rbenv install 3.3.0
rbenv global 3.3.0

# Install PostgreSQL
brew install postgresql@16
brew services start postgresql@16

# Install Node.js
brew install node
```

### Environment Variables Setup

The application uses `dotenv-rails` to load environment variables from a `.env` file in development and test environments.

1. **Copy the example file:**
   ```bash
   cp .env.example .env
   ```

2. **Update the `.env` file** with your local database credentials:
   ```bash
   # Edit .env file
   # Update DATABASE_USERNAME, DATABASE_PASSWORD, etc.
   ```

3. **For production**, set environment variables directly in your deployment platform (Heroku, AWS, etc.) - do not use `.env` files in production.

See [Solid Databases Setup Guide](docs/037_SOLID_DATABASES_SETUP.md) for detailed database configuration.

### Linux Setup

```bash
# Install Ruby (using rbenv)
sudo apt-get update
sudo apt-get install rbenv ruby-build
rbenv install 3.3.0
rbenv global 3.3.0

# Install PostgreSQL
sudo apt-get install postgresql postgresql-contrib

# Install Node.js
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs
```

---

## Installation

### 1. Clone the Repository

```bash
git clone <repository-url>
cd microblog
```

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
# Copy the example file
cp .env.example .env

# Edit .env with your local database credentials
# Update DATABASE_USERNAME, DATABASE_PASSWORD, etc. as needed
```

The `.env.example` file includes all necessary variables with sensible defaults for local development. See [Solid Databases Setup Guide](docs/037_SOLID_DATABASES_SETUP.md) for detailed configuration.

### 4. Database Setup

```bash
# Create PostgreSQL databases
createdb microblog_development
createdb microblog_test

# Set up Solid databases (cache, queue, cable) with dedicated users
RAILS_ENV=development ./script/setup_solid_databases.sh

# Run migrations (primary database)
rails db:migrate

# (Optional) Load seed data
rails db:seed
```

**Note**: The application is configured for read replicas. In development, the same database is used for both primary and replica. See [Read Replicas Setup](docs/034_READ_REPLICAS_SETUP.md) for production configuration.

---

## Running the Application

### Development Mode

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

For development, use the temporary login route:

```bash
# Visit: http://localhost:3000/dev/login/:user_id
# Example: http://localhost:3000/dev/login/1
```

This sets the session to log you in as that user.

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
- [Database Diagram](docs/001_DATABASE_DIAGRAM.md) - Schema and relationships

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

```bash
# Check PostgreSQL is running
brew services list  # macOS
sudo systemctl status postgresql  # Linux

# Test connection
psql -h localhost -U $USER -d microblog_development
```

### Asset Compilation Issues

```bash
# Clear cache
rails tmp:clear

# Rebuild Tailwind
bin/rails tailwindcss:build
```

### Background Jobs Not Running

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
```

---

## License

[Add your license here]

---

## Support

For questions or issues:
- Check [Documentation](docs/README.md)
- Review [Performance Guides](docs/004_PERFORMANCE_ANALYSIS.md)
- Contact the team

---

**Happy coding! 🚀**
