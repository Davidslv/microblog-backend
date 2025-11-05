# Admin Dashboard Architecture Proposal

## Executive Summary

This document proposes two architectural approaches for implementing the admin dashboard:
1. **Separate Admin Application** (Recommended)
2. **Namespaced Admin in Same Application**

After analysis, **Option 1 (Separate Admin Application)** is recommended for better security isolation, independent scaling, and cleaner separation of concerns.

---

## Table of Contents

- [Context](#context)
- [Architecture Options](#architecture-options)
- [Detailed Comparison](#detailed-comparison)
- [Implementation Details](#implementation-details)
- [Security Considerations](#security-considerations)
- [Performance Considerations](#performance-considerations)
- [Development Workflow](#development-workflow)
- [Deployment Strategy](#deployment-strategy)
- [Cost Analysis](#cost-analysis)
- [Recommendation](#recommendation)
- [Migration Path](#migration-path)

---

## Context

### Current Architecture

- **Main Application**: Rails 8.1 microblog application
- **Infrastructure**: Docker Compose with horizontal scaling (3+ web instances)
- **Database**: PostgreSQL (shared across instances)
- **Load Balancer**: Traefik
- **Cache/Queue**: Solid Cache & Solid Queue (PostgreSQL-backed)
- **Monitoring**: Mission Control (Solid Queue), Puma stats, pg_stat_statements

### Admin Dashboard Requirements

Based on `docs/040_IMPLEMENTATION_PLAN_AUTH_AND_ADMIN.md`, the admin dashboard needs:

1. **Dashboard Overview**: User stats, content stats, system health
2. **Application Metrics**: Puma stats, cache stats, queue stats, rate limiting
3. **Database Performance**: pg_stat_statements, slow queries, table sizes
4. **Mission Control Integration**: Solid Queue job monitoring
5. **User Management**: List, search, ban/unban, make admin
6. **Post Moderation**: Review posts, delete, hide, bulk actions
7. **Audit Trail**: Log all admin actions

---

## Architecture Options

### Option 1: Separate Admin Application ⭐ RECOMMENDED

**Structure:**
```
microblog/
├── app/                    # Main application
│   ├── controllers/
│   ├── models/
│   └── views/
├── admin/                  # Separate Rails application
│   ├── app/
│   │   ├── controllers/
│   │   ├── models/         # Shared models (duplicated or shared)
│   │   └── views/
│   ├── config/
│   ├── Gemfile
│   └── Dockerfile          # Optional: separate Dockerfile
├── shared/                 # Optional: shared models gem
│   └── lib/
├── docker-compose.yml      # Both services
└── ...
```

**Docker Compose:**
```yaml
services:
  web:
    # Main application (existing)
    ports: ["3000:3000"]
    scale: 3

  admin:
    # Separate admin application
    build:
      context: ./admin
    ports: ["3001:3000"]
    scale: 1  # Admin doesn't need scaling
    environment:
      ADMIN_ONLY: true
      DATABASE_URL: postgresql://postgres:postgres@db:5432/microblog_development
```

**Routing:**
- `app.example.com` → Main application (Traefik → web)
- `admin.example.com` → Admin application (Traefik → admin)

---

### Option 2: Namespaced Admin in Same Application

**Structure:**
```
microblog/
├── app/
│   ├── controllers/
│   │   ├── application_controller.rb
│   │   ├── posts_controller.rb
│   │   └── admin/
│   │       ├── admin_controller.rb
│   │       ├── users_controller.rb
│   │       └── moderation_controller.rb
│   ├── models/             # Shared models
│   └── views/
│       └── admin/
├── config/
│   └── routes.rb
└── ...
```

**Routes:**
```ruby
namespace :admin do
  root "admin#index"
  resources :users
  resources :moderation
  # ...
end
```

**Same Docker service:**
- All routes in one application
- Admin routes protected by `require_admin` before_action

---

## Detailed Comparison

### Option 1: Separate Admin Application

#### ✅ Advantages

1. **Security Isolation**
   - Admin routes completely separate from public-facing app
   - No risk of accidentally exposing admin endpoints
   - Can implement different security measures (IP whitelisting, 2FA, etc.)
   - Admin credentials never mixed with user credentials

2. **Independent Scaling**
   - Admin: 1 instance (low traffic, heavy queries)
   - Main app: 3+ instances (high traffic, optimized queries)
   - Different resource allocation

3. **Independent Deployment**
   - Deploy admin without affecting main app
   - Rollback admin changes independently
   - Different release cycles

4. **Performance Isolation**
   - Admin queries (pg_stat_statements, analytics) don't impact main app
   - Heavy admin reports don't slow down user-facing requests
   - Can optimize admin app for different query patterns

5. **Code Clarity**
   - Clear separation: "This is admin code"
   - No namespace confusion
   - Easier to understand what's public vs admin

6. **Technology Flexibility**
   - Could use different stack (React frontend, API-only, etc.)
   - Different dependencies (admin-specific gems)
   - Different Rails version if needed

7. **Simpler Authentication**
   - Admin-specific auth (separate session, different requirements)
   - No need to mix admin and user auth logic

#### ❌ Disadvantages

1. **Code Duplication**
   - Models need to be duplicated or shared via gem
   - Shared business logic needs to be extracted
   - More maintenance overhead

2. **Deployment Complexity**
   - Two applications to deploy
   - Two Docker services to manage
   - More complex CI/CD pipeline

3. **Shared Database Coordination**
   - Migrations need to be coordinated
   - Schema changes affect both apps
   - Need migration strategy

4. **More Infrastructure**
   - Additional container/service
   - More memory/CPU usage
   - More complex monitoring

5. **Development Overhead**
   - Need to run two Rails servers locally
   - More complex setup
   - Two codebases to maintain

---

### Option 2: Namespaced Admin in Same Application

#### ✅ Advantages

1. **Code Reuse**
   - Shared models, helpers, services
   - No duplication
   - Single source of truth

2. **Simpler Deployment**
   - One application to deploy
   - Single Docker service
   - Simpler CI/CD

3. **Unified Authentication**
   - Same session system
   - Shared `current_user`
   - Easier to implement "admin is also a user"

4. **Easier Development**
   - One Rails server
   - Simpler setup
   - One codebase

5. **Less Infrastructure**
   - One container/service
   - Lower resource usage
   - Simpler monitoring

6. **Shared Codebase**
   - Changes to models immediately available
   - No sync issues
   - Easier refactoring

#### ❌ Disadvantages

1. **Security Risk**
   - Admin routes exposed in same app
   - Risk of accidental exposure
   - Harder to implement IP whitelisting
   - Admin code mixed with public code

2. **Performance Impact**
   - Admin queries can affect main app
   - Heavy admin reports slow down main app
   - Shared database connection pool

3. **Scaling Challenges**
   - Can't scale admin independently
   - Admin queries run on all instances
   - Resource allocation is shared

4. **Code Bloat**
   - Admin code mixed with main app
   - Larger codebase
   - More routes/controllers to maintain

5. **Deployment Coupling**
   - Admin changes require main app deployment
   - Can't rollback admin independently
   - Same release cycle

---

## Implementation Details

### Option 1: Separate Admin Application

#### Step 1: Create Admin Application Structure

```bash
# In microblog directory
rails new admin --skip-action-cable --skip-action-mailbox --skip-test
cd admin

# Or use existing structure
mkdir -p admin/app/{controllers,models,views,helpers}
mkdir -p admin/config
```

#### Step 2: Configure Database Connection

**admin/config/database.yml:**
```yaml
development:
  <<: *default
  database: microblog_development
  host: <%= ENV.fetch("DATABASE_HOST") { "db" } %>
  username: <%= ENV.fetch("DATABASE_USERNAME") { "postgres" } %>
  password: <%= ENV.fetch("DATABASE_PASSWORD") { "postgres" } %>
```

#### Step 3: Shared Models

**Option A: Duplicate Models (Simple)**
```ruby
# admin/app/models/user.rb
class User < ApplicationRecord
  self.table_name = 'users'
  # Same validations, associations, etc.
end
```

**Option B: Shared Gem (Better)**
```ruby
# shared/lib/models/user.rb
# Both apps require this gem
gem 'microblog-shared', path: '../shared'
```

**Option C: Database-Only (Recommended for Start)**
- Just use ActiveRecord with same table names
- Duplicate model code initially
- Extract to gem later if needed

#### Step 4: Docker Compose Configuration

**docker-compose.yml:**
```yaml
services:
  # Existing web service
  web:
    # ... existing config

  # New admin service
  admin:
    build:
      context: ./admin
      dockerfile: Dockerfile
    environment:
      RAILS_ENV: development
      DATABASE_HOST: db
      DATABASE_USERNAME: ${DATABASE_USERNAME:-postgres}
      DATABASE_PASSWORD: ${DATABASE_PASSWORD:-postgres}
      DATABASE_URL: postgresql://${DATABASE_USERNAME:-postgres}:${DATABASE_PASSWORD:-postgres}@db:5432/microblog_development
    ports:
      - "3001:3000"
    networks:
      - microblog-network
    depends_on:
      - db
    volumes:
      - ./admin:/rails
      - admin_gems:/usr/local/bundle
```

#### Step 5: Traefik Routing

**docker-compose.yml (traefik labels):**
```yaml
admin:
  labels:
    - "traefik.http.routers.admin.rule=Host(`admin.localhost`)"
    - "traefik.http.services.admin.loadbalancer.server.port=3000"
```

#### Step 6: Authentication

**admin/app/controllers/application_controller.rb:**
```ruby
class ApplicationController < ActionController::Base
  before_action :require_admin_login

  private

  def require_admin_login
    # Check admin table
    unless admin_user
      redirect_to admin_login_path
    end
  end

  def admin_user
    @admin_user ||= Admin.find_by(user_id: session[:admin_user_id])&.user
  end
end
```

---

### Option 2: Namespaced Admin in Same Application

#### Step 1: Create Admin Namespace

**config/routes.rb:**
```ruby
namespace :admin do
  root "admin#index"
  get "metrics", to: "admin#metrics"
  get "database", to: "admin#database"
  resources :users
  resources :moderation
end
```

#### Step 2: Admin Controllers

**app/controllers/admin/admin_controller.rb:**
```ruby
module Admin
  class AdminController < ApplicationController
    before_action :require_admin

    def index
      @stats = {
        users: User.count,
        posts: Post.count,
        # ...
      }
    end
  end
end
```

#### Step 3: Admin Authentication

**app/controllers/application_controller.rb:**
```ruby
def require_admin
  unless current_user&.admin?
    redirect_to root_path, alert: "Access denied"
  end
end
```

#### Step 4: Admin Views

**app/views/admin/admin/index.html.erb:**
```erb
<h1>Admin Dashboard</h1>
<!-- Dashboard content -->
```

---

## Security Considerations

### Option 1: Separate Admin Application

**Security Benefits:**
- ✅ Admin routes not exposed to public
- ✅ Can implement IP whitelisting easily
- ✅ Separate authentication system
- ✅ Can use different SSL/TLS settings
- ✅ Admin credentials isolated
- ✅ Can disable admin app without affecting main app

**Security Implementation:**
```ruby
# admin/config/initializers/ip_whitelist.rb
if Rails.env.production?
  Rack::Attack.blocklist('block non-admin-ips') do |req|
    !ALLOWED_ADMIN_IPS.include?(req.ip)
  end
end
```

### Option 2: Namespaced Admin

**Security Risks:**
- ⚠️ Admin routes exposed in same app
- ⚠️ Risk of route conflicts
- ⚠️ Harder to implement IP whitelisting
- ⚠️ Admin code mixed with public code

**Security Mitigation:**
```ruby
# config/initializers/rack_attack.rb
Rack::Attack.blocklist('block admin access') do |req|
  req.path.start_with?('/admin') && !ALLOWED_ADMIN_IPS.include?(req.ip)
end
```

---

## Performance Considerations

### Option 1: Separate Admin Application

**Performance Benefits:**
- ✅ Admin queries don't affect main app
- ✅ Can optimize admin app for analytics queries
- ✅ Independent connection pools
- ✅ Can use read replicas for admin reports

**Performance Characteristics:**
- Admin: Heavy queries (pg_stat_statements, analytics)
- Main app: Optimized for user-facing requests
- Different query patterns = different optimizations

### Option 2: Namespaced Admin

**Performance Issues:**
- ⚠️ Admin queries affect main app performance
- ⚠️ Shared connection pool
- ⚠️ Heavy admin reports slow down user requests
- ⚠️ Can't optimize independently

**Performance Mitigation:**
- Use read replicas for admin queries
- Cache admin metrics
- Background jobs for heavy reports

---

## Development Workflow

### Option 1: Separate Admin Application

**Local Development:**
```bash
# Terminal 1: Main app
cd microblog
rails server

# Terminal 2: Admin app
cd microblog/admin
rails server -p 3001

# Or use Docker Compose
docker compose up web admin
```

**Pros:**
- Clear separation
- Can test admin independently
- Different ports (3000 vs 3001)

**Cons:**
- Need to run two servers
- More complex setup
- Models need to be synced

### Option 2: Namespaced Admin

**Local Development:**
```bash
rails server
# Access admin at http://localhost:3000/admin
```

**Pros:**
- Single server
- Simpler setup
- Shared models automatically

**Cons:**
- No clear separation
- Harder to test independently

---

## Deployment Strategy

### Option 1: Separate Admin Application

**Docker Compose:**
```yaml
services:
  web:
    deploy:
      replicas: 3
  admin:
    deploy:
      replicas: 1
```

**Kamal Deployment:**
```yaml
# config/deploy.yml
services:
  web:
    servers:
      - 192.168.0.1
      - 192.168.0.2
      - 192.168.0.3

  admin:
    servers:
      - 192.168.0.4  # Separate server
```

**Pros:**
- Independent scaling
- Can deploy to different servers
- Different resource allocation

### Option 2: Namespaced Admin

**Deployment:**
- Same deployment as main app
- Admin routes included automatically
- Same scaling strategy

**Pros:**
- Simpler deployment
- Single service

**Cons:**
- Can't scale independently
- Admin routes on all instances

---

## Cost Analysis

### Option 1: Separate Admin Application

**Infrastructure Costs:**
- Additional container: ~512MB RAM, ~0.5 CPU
- Admin instance: 1x (low traffic)
- Total: Minimal additional cost

**Development Costs:**
- Initial setup: +2-3 days
- Ongoing maintenance: +10% (model sync)

**Operational Costs:**
- Deployment: +1 service to manage
- Monitoring: +1 service to monitor

### Option 2: Namespaced Admin

**Infrastructure Costs:**
- No additional containers
- Shared resources

**Development Costs:**
- Initial setup: 0 days (uses existing)
- Ongoing maintenance: Shared codebase

**Operational Costs:**
- Deployment: Same as main app
- Monitoring: Same as main app

**Verdict:** Option 1 has minimal additional cost, but better security/performance trade-offs.

---

## Recommendation

### ⭐ **Option 1: Separate Admin Application** (RECOMMENDED)

**Rationale:**

1. **Security First**: Admin routes completely isolated from public app
2. **Independent Scaling**: Admin doesn't need horizontal scaling, main app does
3. **Performance Isolation**: Heavy admin queries won't impact user-facing requests
4. **Future Flexibility**: Can evolve admin independently (React frontend, API-only, etc.)
5. **Clear Separation**: "This is admin code" vs "This is public code"

**When to Choose Option 2:**
- Very small team (1-2 developers)
- Limited infrastructure resources
- Admin dashboard is very simple
- No performance concerns
- Rapid prototyping phase

---

## Migration Path

### If Starting with Option 2 (Namespaced)

**Future Migration to Option 1:**
1. Extract admin controllers to separate app
2. Duplicate models or create shared gem
3. Configure separate Docker service
4. Update routing
5. Test thoroughly
6. Deploy

**Migration Complexity:** Medium (2-3 days)

### If Starting with Option 1

**No migration needed** - already separated.

---

## Implementation Plan

### Phase 1: Setup (Option 1)

1. **Create Admin Application Structure**
   - Generate Rails app in `admin/` directory
   - Configure database connection
   - Set up basic authentication

2. **Docker Compose Integration**
   - Add `admin` service to docker-compose.yml
   - Configure networking
   - Set up Traefik routing

3. **Shared Models**
   - Duplicate models initially
   - Or create shared gem (future optimization)

4. **Basic Admin Dashboard**
   - Dashboard overview
   - User management
   - Post moderation

**Estimated Time:** 3-5 days

### Phase 2: Features

1. **Application Metrics**
   - Puma stats
   - Cache stats
   - Queue stats

2. **Database Performance**
   - pg_stat_statements integration
   - Slow query analysis
   - Table/index sizes

3. **Mission Control Integration**
   - Link to /jobs endpoint
   - Job summary on dashboard

**Estimated Time:** 5-7 days

### Phase 3: Advanced Features

1. **Audit Trail**
   - Log all admin actions
   - Action history

2. **Advanced Analytics**
   - User growth charts
   - Content analytics
   - Engagement metrics

3. **Bulk Actions**
   - Bulk ban users
   - Bulk hide posts

**Estimated Time:** 3-5 days

**Total Estimated Time:** 11-17 days

---

## Decision Matrix

| Criteria | Option 1 (Separate) | Option 2 (Namespaced) | Winner |
|----------|---------------------|-----------------------|--------|
| **Security** | ✅ Isolated | ⚠️ Shared | Option 1 |
| **Performance** | ✅ Independent | ⚠️ Shared | Option 1 |
| **Scaling** | ✅ Independent | ❌ Coupled | Option 1 |
| **Deployment** | ⚠️ More complex | ✅ Simpler | Option 2 |
| **Development** | ⚠️ More complex | ✅ Simpler | Option 2 |
| **Code Reuse** | ⚠️ Duplication | ✅ Shared | Option 2 |
| **Maintenance** | ⚠️ Two codebases | ✅ One codebase | Option 2 |
| **Flexibility** | ✅ High | ⚠️ Limited | Option 1 |
| **Cost** | ⚠️ Slightly higher | ✅ Lower | Option 2 |

**Overall Winner: Option 1** (wins in security, performance, scaling, flexibility)

---

## Conclusion

**Recommendation: Separate Admin Application (Option 1)**

While Option 2 is simpler initially, Option 1 provides:
- Better security isolation
- Independent scaling and performance
- Future flexibility
- Clear separation of concerns

The additional complexity (two services, model duplication) is outweighed by the benefits, especially for a production application that needs to scale.

**Next Steps:**
1. Review this proposal
2. Make decision
3. Proceed with implementation plan

---

## Questions to Consider

Before making a final decision, consider:

1. **Team Size**: How many developers will maintain this?
   - Small team (1-2): Option 2 might be simpler
   - Larger team: Option 1 provides better separation

2. **Traffic Expectations**: How much admin traffic vs main app?
   - Low admin traffic: Option 1 is better (isolated)
   - High admin traffic: Option 1 is better (independent scaling)

3. **Security Requirements**: How sensitive is admin access?
   - High security needs: Option 1 (isolation)
   - Basic security: Either option works

4. **Infrastructure**: Can you support two services?
   - Limited resources: Option 2
   - Adequate resources: Option 1

5. **Future Plans**: Will admin evolve independently?
   - Yes: Option 1
   - No: Either option

---

## References

- `docs/040_IMPLEMENTATION_PLAN_AUTH_AND_ADMIN.md` - Admin dashboard requirements
- `docs/038_DOCKER_COMPOSE_CONFIGURATION.md` - Docker setup
- `docs/036_HORIZONTAL_SCALING.md` - Scaling strategy
- `docs/016_PG_STAT_STATEMENTS.md` - Database monitoring

---

**Document Version:** 1.0
**Last Updated:** 2024-11-04
**Author:** Architecture Proposal

