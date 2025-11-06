# Phase 1: Parallel Running - Monolith and API

> **Documentation on how the monolith and API run in parallel, sharing the same database**

## Overview

Phase 1 successfully implements the API foundation **alongside** the existing monolith. Both systems run simultaneously, sharing the same database, models, and business logic. This allows for gradual migration without breaking existing functionality.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Single Rails Application                  │
│                                                               │
│  ┌──────────────────────┐      ┌──────────────────────┐   │
│  │  Monolith Routes      │      │  API Routes           │   │
│  │  (HTML Responses)    │      │  (JSON Responses)     │   │
│  │                      │      │                      │   │
│  │  /posts              │      │  /api/v1/posts        │   │
│  │  /users/:id          │      │  /api/v1/users/:id    │   │
│  │  /login              │      │  /api/v1/login        │   │
│  └──────────┬───────────┘      └──────────┬───────────┘   │
│             │                              │               │
│             └──────────┬───────────────────┘               │
│                        │                                   │
│             ┌──────────▼───────────┐                      │
│             │  Shared Controllers   │                      │
│             │  - PostsController    │                      │
│             │  - UsersController   │                      │
│             │  - SessionsController│                      │
│             └──────────┬───────────┘                      │
│                        │                                   │
│             ┌──────────▼───────────┐                      │
│             │  Shared Models       │                      │
│             │  - User              │                      │
│             │  - Post              │                      │
│             │  - Follow            │                      │
│             └──────────┬───────────┘                      │
│                        │                                   │
│             ┌──────────▼───────────┐                      │
│             │  PostgreSQL Database  │                      │
│             │  (Single Source)      │                      │
│             └──────────────────────┘                      │
└─────────────────────────────────────────────────────────────┘
```

## Key Implementation Details

### 1. Route Separation

**Monolith Routes** (HTML responses):
```ruby
# config/routes.rb
root "posts#index"
resources :posts, only: [:index, :show, :create]
resources :users, only: [:show, :new, :create, :edit, :update, :destroy]
get "/login", to: "sessions#new"
post "/login", to: "sessions#create"
```

**API Routes** (JSON responses):
```ruby
# config/routes.rb
namespace :api do
  namespace :v1 do
    resources :posts, only: [:index, :show, :create]
    resources :users, only: [:show, :create, :update, :destroy]
    post "/login", to: "sessions#create"
    get "/me", to: "sessions#show"
  end
end
```

### 2. Controller Separation

**Monolith Controllers** (inherit from `ActionController::Base`):
- `PostsController` - Renders ERB views
- `UsersController` - Renders ERB views
- `SessionsController` - Renders ERB views

**API Controllers** (inherit from `ActionController::API`):
- `Api::V1::PostsController` - Returns JSON
- `Api::V1::UsersController` - Returns JSON
- `Api::V1::SessionsController` - Returns JSON

### 3. Shared Models and Business Logic

Both systems use the **exact same models**:
- `User` model
- `Post` model
- `Follow` model
- All business logic (fan-out on write, caching, etc.)

**This ensures:**
- Data consistency: Posts created via monolith are immediately visible via API
- Business logic consistency: Same validation rules, same callbacks
- No code duplication: Single source of truth for models

### 4. Session-Based Authentication (Parallel Support)

**Current Implementation:**
- Both monolith and API use **session-based authentication**
- Sessions are stored in cookies (shared across both systems)
- User logged in via monolith can access API (and vice versa)

**How it works:**
```ruby
# Api::V1::BaseController
def current_user
  @current_user ||= begin
    # Try JWT token first (for future)
    token = extract_jwt_token
    if token && defined?(JwtService)
      payload = JwtService.decode(token)
      return User.find_by(id: payload[:user_id]) if payload
    end

    # Fallback to session (for parallel running)
    if session[:user_id]
      return User.find_by(id: session[:user_id])
    end

    nil
  end
end
```

**Benefits:**
- Users can switch between monolith and API seamlessly
- No need to re-authenticate
- Same session cookie works for both

### 5. CORS Configuration

**File: `config/initializers/cors.rb`**
```ruby
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    if Rails.env.development?
      origins ['http://localhost:3001', 'http://localhost:5173', 'http://localhost:5174']
    else
      frontend_url = ENV.fetch('FRONTEND_URL', nil)
      origins frontend_url ? [frontend_url] : []
    end

    resource '/api/*',
      headers: :any,
      methods: [:get, :post, :put, :patch, :delete, :options, :head],
      credentials: true,
      expose: ['Authorization']
  end
end
```

**Why CORS is needed:**
- Frontend (React) will run on different port (3001) than API (3000)
- Browser enforces same-origin policy
- CORS allows cross-origin requests from frontend to API

## Data Flow Examples

### Example 1: Create Post via Monolith, Read via API

```
1. User logs in via monolith: POST /login
   → Session created: session[:user_id] = 123

2. User creates post via monolith: POST /posts
   → Post saved to database (id: 456)

3. User reads posts via API: GET /api/v1/posts
   → API reads session[:user_id] = 123
   → API queries database for user 123's feed
   → Returns post 456 in JSON response
```

### Example 2: Create Post via API, Read via Monolith

```
1. User logs in via API: POST /api/v1/login
   → Session created: session[:user_id] = 123

2. User creates post via API: POST /api/v1/posts
   → Post saved to database (id: 456)

3. User reads posts via monolith: GET /posts
   → Monolith reads session[:user_id] = 123
   → Monolith queries database for user 123's feed
   → Renders post 456 in HTML view
```

### Example 3: Follow User via Monolith, See in API Feed

```
1. User logs in via monolith: POST /login
   → Session created: session[:user_id] = 123

2. User follows another user via monolith: POST /follow/456
   → Follow record created
   → Fan-out job queues feed entries

3. User reads feed via API: GET /api/v1/posts?filter=timeline
   → API reads session[:user_id] = 123
   → API queries feed_entries for user 123
   → Returns posts from user 456 in JSON response
```

## Testing Strategy

### 1. Monolith Tests (Still Pass)

All existing monolith tests continue to work:
```bash
bundle exec rspec spec/requests/posts_spec.rb
bundle exec rspec spec/requests/users_spec.rb
bundle exec rspec spec/requests/sessions_spec.rb
```

### 2. API Tests (New)

New API tests verify JSON responses:
```bash
bundle exec rspec spec/requests/api/v1/
```

**Test Coverage:**
- ✅ Authentication (login, logout, current user)
- ✅ Posts (list, show, create, pagination)
- ✅ Users (show, create, update, delete)
- ✅ Follows (create, destroy)
- ✅ Error handling (unauthorized, not found, validation errors)

### 3. Integration Tests

Tests verify both systems work together:
```ruby
# User can login via monolith and access API
it "allows monolith login to access API" do
  # Login via monolith
  post "/login", params: { username: user.username, password: "password123" }
  
  # Access API with same session
  get "/api/v1/me"
  expect(response).to have_http_status(:success)
end
```

## Benefits of Parallel Running

1. **Zero Downtime Migration**
   - Monolith continues working during migration
   - Users don't experience any disruption
   - Can test API thoroughly before switching

2. **Gradual Rollout**
   - Can route some users to API, others to monolith
   - Feature flags can control which system users see
   - Easy rollback if issues arise

3. **Data Consistency**
   - Single database ensures consistency
   - No data synchronization needed
   - Same business logic in both systems

4. **Testing in Production**
   - Can test API with real data
   - Compare responses between monolith and API
   - Verify performance before full migration

## Current Status

✅ **Phase 1 Complete:**
- API routes and controllers implemented
- JSON responses for all endpoints
- CORS configured
- Session-based authentication (shared with monolith)
- Comprehensive test coverage
- Monolith continues working unchanged

**Next Steps:**
- Phase 2: JWT Authentication (replace session for API)
- Phase 3: Frontend Setup (React application)
- Phase 4: Integration and E2E Testing

## Verification

### Manual Testing

**1. Start Rails server:**
```bash
bin/rails server
```

**2. Test Monolith (HTML):**
- Visit: `http://localhost:3000/`
- Login, create post, view feed
- Verify everything works as before

**3. Test API (JSON):**
- Login: `POST http://localhost:3000/api/v1/login`
  ```json
  {
    "username": "testuser",
    "password": "password123"
  }
  ```
- Get posts: `GET http://localhost:3000/api/v1/posts`
- Create post: `POST http://localhost:3000/api/v1/posts`
  ```json
  {
    "post": {
      "content": "Hello from API!"
    }
  }
  ```

**4. Verify Data Consistency:**
- Create post via monolith
- Check it appears in API response
- Create post via API
- Check it appears in monolith view

### Automated Testing

```bash
# Run all tests
bundle exec rspec

# Run only monolith tests
bundle exec rspec spec/requests/posts_spec.rb spec/requests/users_spec.rb

# Run only API tests
bundle exec rspec spec/requests/api/v1/

# Run integration tests
bundle exec rspec spec/requests/api/v1/integration_spec.rb
```

## Common Issues and Solutions

### Issue 1: CORS Errors

**Problem:** Frontend can't call API due to CORS

**Solution:** Verify CORS configuration in `config/initializers/cors.rb` includes your frontend origin

### Issue 2: Session Not Persisting

**Problem:** API requests don't have session cookie

**Solution:** Ensure cookies are enabled in API requests (credentials: true in CORS config)

### Issue 3: Authentication Failing

**Problem:** User logged in via monolith can't access API

**Solution:** Verify `Api::V1::BaseController#current_user` checks session correctly

## Conclusion

Phase 1 successfully demonstrates that the monolith and API can run in parallel, sharing the same database and business logic. This provides a solid foundation for gradual migration to the three-layer architecture.

**Key Achievement:** Zero breaking changes to existing monolith functionality while adding full API support.

---

**Document Version:** 1.0  
**Last Updated:** 2024  
**Status:** Phase 1 Complete ✅

