# Three-Layer Architecture Implementation Plan

> **Migrating from Rails Monolith to Presentation-Application-Data Architecture**

This document provides a detailed, step-by-step implementation plan for migrating the microblog application from a monolithic Rails MVC architecture to a three-layer architecture with independent frontend, API backend, and database layers.

---

## Table of Contents

1. [Overview](#overview)
2. [Current State Analysis](#current-state-analysis)
3. [Target Architecture](#target-architecture)
4. [Implementation Phases](#implementation-phases)
5. [Data Flow](#data-flow)
6. [Challenges & Solutions](#challenges--solutions)
7. [Docker Configuration](#docker-configuration)
8. [Testing Strategy](#testing-strategy)
9. [Migration Strategy](#migration-strategy)
10. [Rollback Plan](#rollback-plan)

---

## Overview

### Goals

Transform the current Rails monolith into a three-layer architecture:

1. **Presentation Layer** (Frontend)
   - React-based single-page application
   - Served via CDN or static hosting
   - Communicates with API via REST/JSON

2. **Application Layer** (Rails API)
   - Rails API-only application
   - Stateless, JWT-based authentication
   - RESTful JSON endpoints
   - Horizontal scaling support

3. **Data Layer** (Database)
   - PostgreSQL (unchanged)
   - Solid Cache, Solid Queue, Solid Cable
   - Read replicas support

### Key Benefits

1. **Independent Scaling**: Scale frontend (CDN) and backend (API servers) independently
2. **Technology Evolution**: Frontend and backend can evolve independently
3. **Team Autonomy**: Frontend and backend teams work independently with clear API contracts
4. **Faster Iteration**: Frontend changes don't require backend deploys
5. **Cost Optimization**: Scale expensive components (backend) separately from cheap ones (static frontend)
6. **Performance Optimization**: Frontend cached at edge, backend optimized for API performance
7. **Multi-Platform Support**: Same API can serve web, mobile, desktop apps

---

## Current State Analysis

### Current Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Rails Monolith                       │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐ │
│  │ Controllers   │  │    Views     │  │    Models    │ │
│  │ (MVC Logic)   │→ │  (ERB/HTML)  │  │  (Business   │ │
│  │              │  │              │  │   Logic)     │ │
│  └──────────────┘  └──────────────┘  └──────────────┘ │
│         ↓                   ↓                  ↓        │
│  ┌──────────────────────────────────────────────────┐   │
│  │         Session-based Authentication            │   │
│  └──────────────────────────────────────────────────┘   │
│         ↓                   ↓                  ↓        │
│  ┌──────────────────────────────────────────────────┐   │
│  │            PostgreSQL Database                    │   │
│  └──────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

### Current Components

**Controllers:**
- `PostsController` - Handles posts CRUD, feed queries
- `UsersController` - User management, profiles
- `SessionsController` - Login/logout (session-based)
- `FollowsController` - Follow/unfollow actions

**Models:**
- `User` - Authentication, follows relationships
- `Post` - Posts and replies with fan-out on write
- `Follow` - Follow relationships
- `FeedEntry` - Pre-computed feed entries (fan-out)

**Views:**
- ERB templates with Turbo/Stimulus
- Server-side rendering
- Session-based authentication

**Infrastructure:**
- Docker Compose with Traefik load balancer
- PostgreSQL database
- Solid Cache/Queue/Cable
- Horizontal scaling support

### Current Data Flow

**Feed Request:**
```
User Browser → Rails Controller → Database Query → ERB Template → HTML Response
```

**Post Creation:**
```
User Browser → Rails Controller → Post Model → Database Insert → FanOutFeedJob → Redirect
```

---

## Target Architecture

### Three-Layer Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                   PRESENTATION LAYER                        │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  React SPA (Static Assets)                           │  │
│  │  - Components (Posts, Users, Feed)                    │  │
│  │  - State Management (Redux/Zustand)                   │  │
│  │  - API Client (Axios/Fetch)                           │  │
│  │  - Authentication (JWT Storage)                       │  │
│  └──────────────────────────────────────────────────────┘  │
│                          ↓ HTTP/HTTPS                       │
│                          ↓ JSON API                         │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│                   APPLICATION LAYER                          │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  Rails API (Stateless)                                │  │
│  │  - API Controllers (JSON only)                        │  │
│  │  - JWT Authentication                                  │  │
│  │  - Business Logic (Models)                            │  │
│  │  - Background Jobs (Solid Queue)                      │  │
│  └──────────────────────────────────────────────────────┘  │
│                          ↓                                  │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  Load Balancer (Traefik)                              │  │
│  └──────────────────────────────────────────────────────┘  │
│                          ↓                                  │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│                     DATA LAYER                               │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  PostgreSQL (Primary)                                 │  │
│  │  - Users, Posts, Follows, FeedEntries                │  │
│  └──────────────────────────────────────────────────────┘  │
│                          ↓                                  │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  PostgreSQL (Read Replicas) - Optional                │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  Solid Cache (PostgreSQL)                             │  │
│  └──────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  Solid Queue (PostgreSQL)                             │  │
│  └──────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  Solid Cable (PostgreSQL)                             │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### Key Architectural Changes

1. **Session → JWT Authentication**
   - Stateless authentication
   - Token stored in frontend (localStorage/httpOnly cookie)
   - No server-side session storage

2. **ERB Views → React Components**
   - Client-side rendering
   - API-driven data fetching
   - Client-side routing

3. **HTML Responses → JSON Responses**
   - All endpoints return JSON
   - Frontend handles UI rendering
   - Consistent error handling

4. **Server-Side Redirects → Client-Side Navigation**
   - React Router for navigation
   - API returns data, not redirects
   - Frontend handles routing

---

## Implementation Phases

### Phase 1: Rails API Foundation (Week 1-2)

**Goal:** Convert Rails app to API-only mode, maintain all existing functionality

#### 1.1 Configure Rails API Mode

**File: `config/application.rb`**
```ruby
module Microblog
  class Application < Rails::Application
    config.load_defaults 8.1

    # Enable API mode
    config.api_only = true

    # Keep middleware needed for API
    config.middleware.use ActionDispatch::Cookies
    config.middleware.use ActionDispatch::Session::CookieStore
    config.middleware.use ActionDispatch::Flash

    # CORS configuration for frontend
    config.middleware.insert_before 0, Rack::Cors do
      allow do
        origins Rails.env.development? ? 'http://localhost:3001' : ENV['FRONTEND_URL']
        resource '*',
          headers: :any,
          methods: [:get, :post, :put, :patch, :delete, :options, :head],
          credentials: true
      end
    end

    # Configure read replicas (unchanged)
    config.active_record.database_selector = { delay: 2.seconds }
    config.active_record.database_resolver = ActiveRecord::Middleware::DatabaseSelector::Resolver
    config.active_record.database_resolver_context = ActiveRecord::Middleware::DatabaseSelector::Resolver::Session
  end
end
```

**Add CORS gem:**
```ruby
# Gemfile
gem 'rack-cors'
```

#### 1.2 Create API Base Controller

**File: `app/controllers/api/v1/base_controller.rb`**
```ruby
module Api
  module V1
    class BaseController < ActionController::API
      include ActionController::Cookies

      # Error handling
      rescue_from ActiveRecord::RecordNotFound, with: :not_found
      rescue_from ActiveRecord::RecordInvalid, with: :unprocessable_entity
      rescue_from ActionController::ParameterMissing, with: :bad_request

      # Authentication (temporary - will be replaced with JWT in Phase 2)
      before_action :authenticate_user

      private

      def current_user
        @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id]
      end

      def authenticate_user
        unless current_user
          render json: { error: 'Unauthorized' }, status: :unauthorized
        end
      end

      def not_found(error)
        render json: { error: error.message }, status: :not_found
      end

      def unprocessable_entity(error)
        render json: { errors: error.record.errors.full_messages }, status: :unprocessable_entity
      end

      def bad_request(error)
        render json: { error: error.message }, status: :bad_request
      end
    end
  end
end
```

#### 1.3 Create API Namespace Routes

**File: `config/routes.rb`**
```ruby
Rails.application.routes.draw do
  # Health check
  get "up" => "rails/health#show", as: :rails_health_check

  # API namespace
  namespace :api do
    namespace :v1 do
      # Authentication (temporary session-based)
      post "/login", to: "sessions#create"
      delete "/logout", to: "sessions#destroy"
      get "/me", to: "sessions#show"

      # Users
      resources :users, only: [:show, :create, :update, :destroy]
      post "/signup", to: "users#create", as: "signup"

      # Posts
      resources :posts, only: [:index, :show, :create] do
        member do
          get :replies
        end
      end

      # Follows
      post "/users/:user_id/follow", to: "follows#create"
      delete "/users/:user_id/follow", to: "follows#destroy"
    end
  end

  # Keep existing routes for backward compatibility during migration
  # (Remove in Phase 6)
  root "posts#index"
  resources :posts, only: [:index, :show, :create]
  get "/login", to: "sessions#new", as: "login"
  post "/login", to: "sessions#create"
  delete "/logout", to: "sessions#destroy", as: "logout"
  resources :users, only: [:show, :new, :create, :edit, :update, :destroy]
  get "/signup", to: "users#new", as: "signup"
  post "/follow/:user_id", to: "follows#create", as: "follow"
  delete "/follow/:user_id", to: "follows#destroy"
end
```

#### 1.4 Create API Controllers

**File: `app/controllers/api/v1/posts_controller.rb`**
```ruby
module Api
  module V1
    class PostsController < BaseController
      skip_before_action :authenticate_user, only: [:index, :show]

      def index
        filter = params[:filter] || "timeline"
        per_page = 20

        if current_user
          case filter
          when "mine"
            posts_relation = current_user.posts.timeline
          when "following"
            user_id = Post.connection.quote(current_user.id)
            posts_relation = Post.joins(
              "INNER JOIN follows ON posts.author_id = follows.followed_id AND follows.follower_id = #{user_id}"
            ).timeline.distinct
          else
            cache_key = "user_feed:#{current_user.id}:#{params[:cursor]}"
            cached_result = Rails.cache.read(cache_key)

            if cached_result
              posts, next_cursor, has_next = cached_result
              render json: {
                posts: posts.map { |p| post_json(p) },
                pagination: {
                  cursor: next_cursor,
                  has_next: has_next
                }
              }
              return
            end

            posts_relation = current_user.feed_posts.timeline
          end
        else
          @filter = "all"
          cache_key = "public_posts:#{params[:cursor]}"
          cached_result = Rails.cache.read(cache_key)

          if cached_result
            posts, next_cursor, has_next = cached_result
          else
            posts_relation = Post.top_level.timeline
            posts, next_cursor, has_next = cursor_paginate(posts_relation, per_page: per_page)
            Rails.cache.write(cache_key, [posts, next_cursor, has_next], expires_in: 1.minute)
          end

          render json: {
            posts: posts.map { |p| post_json(p) },
            pagination: {
              cursor: next_cursor,
              has_next: has_next
            }
          }
          return
        end

        posts, next_cursor, has_next = cursor_paginate(posts_relation, per_page: per_page)

        if filter == "timeline" && current_user
          cache_key = "user_feed:#{current_user.id}:#{params[:cursor]}"
          Rails.cache.write(cache_key, [posts, next_cursor, has_next], expires_in: 5.minutes)
        end

        render json: {
          posts: posts.map { |p| post_json(p) },
          pagination: {
            cursor: next_cursor,
            has_next: has_next
          }
        }
      end

      def show
        post = Post.find(params[:id])
        replies_cursor = params[:replies_cursor] || params[:cursor]
        replies, replies_next_cursor, replies_has_next = cursor_paginate(
          post.replies.order(created_at: :asc),
          per_page: 20,
          cursor: replies_cursor,
          order: :asc
        )

        render json: {
          post: post_json(post),
          replies: replies.map { |r| post_json(r) },
          pagination: {
            cursor: replies_next_cursor,
            has_next: replies_has_next
          }
        }
      end

      def create
        post = Post.new(post_params)
        post.author = current_user

        if post.save
          render json: { post: post_json(post) }, status: :created
        else
          render json: { errors: post.errors.full_messages }, status: :unprocessable_entity
        end
      end

      private

      def post_params
        params.require(:post).permit(:content, :parent_id)
      end

      def post_json(post)
        {
          id: post.id,
          content: post.content,
          author: {
            id: post.author_id,
            username: post.author_name
          },
          created_at: post.created_at.iso8601,
          parent_id: post.parent_id,
          replies_count: post.replies.count
        }
      end

      def cursor_paginate(relation, per_page: 20, cursor: nil, order: :desc)
        cursor_id = cursor || params[:cursor]&.to_i

        if cursor_id.present? && cursor_id > 0
          if order == :asc
            relation = relation.where("posts.id > ?", cursor_id)
          else
            relation = relation.where("posts.id < ?", cursor_id)
          end
        end

        posts = relation.limit(per_page + 1).to_a
        has_next = posts.length > per_page
        posts = posts.take(per_page) if has_next
        next_cursor = posts.last&.id

        [posts, next_cursor, has_next]
      end
    end
  end
end
```

**File: `app/controllers/api/v1/sessions_controller.rb`**
```ruby
module Api
  module V1
    class SessionsController < BaseController
      skip_before_action :authenticate_user, only: [:create]

      def create
        user = User.find_by(username: params[:username])

        if user&.authenticate(params[:password])
          session[:user_id] = user.id
          render json: {
            user: user_json(user),
            message: "Login successful"
          }
        else
          render json: { error: "Invalid username or password" }, status: :unauthorized
        end
      end

      def show
        render json: { user: user_json(current_user) }
      end

      def destroy
        session[:user_id] = nil
        render json: { message: "Logged out successfully" }
      end

      private

      def user_json(user)
        {
          id: user.id,
          username: user.username,
          description: user.description,
          followers_count: user.followers_count,
          following_count: user.following_count,
          posts_count: user.posts_count
        }
      end
    end
  end
end
```

**File: `app/controllers/api/v1/users_controller.rb`**
```ruby
module Api
  module V1
    class UsersController < BaseController
      skip_before_action :authenticate_user, only: [:show, :create]

      def show
        user = User.find(params[:id])
        posts = user.posts.timeline.limit(20)

        render json: {
          user: user_json(user),
          posts: posts.map { |p| post_json(p) }
        }
      end

      def create
        user = User.new(user_params)

        if user.save
          session[:user_id] = user.id
          render json: { user: user_json(user) }, status: :created
        else
          render json: { errors: user.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def update
        if current_user.update(user_params)
          render json: { user: user_json(current_user) }
        else
          render json: { errors: current_user.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def destroy
        current_user.destroy
        session[:user_id] = nil
        render json: { message: "Account deleted successfully" }
      end

      private

      def user_params
        params.require(:user).permit(:username, :password, :password_confirmation, :description)
      end

      def user_json(user)
        {
          id: user.id,
          username: user.username,
          description: user.description,
          followers_count: user.followers_count,
          following_count: user.following_count,
          posts_count: user.posts_count,
          created_at: user.created_at.iso8601
        }
      end

      def post_json(post)
        {
          id: post.id,
          content: post.content,
          created_at: post.created_at.iso8601
        }
      end
    end
  end
end
```

**File: `app/controllers/api/v1/follows_controller.rb`**
```ruby
module Api
  module V1
    class FollowsController < BaseController
      def create
        user_to_follow = User.find(params[:user_id])

        if current_user.follow(user_to_follow)
          render json: { message: "Now following #{user_to_follow.username}" }
        else
          render json: { error: "Unable to follow user" }, status: :unprocessable_entity
        end
      end

      def destroy
        user_to_unfollow = User.find(params[:user_id])

        if current_user.unfollow(user_to_unfollow)
          render json: { message: "Unfollowed #{user_to_unfollow.username}" }
        else
          render json: { error: "Unable to unfollow user" }, status: :unprocessable_entity
        end
      end
    end
  end
end
```

#### 1.5 Testing API Endpoints

**File: `spec/requests/api/v1/posts_spec.rb`**
```ruby
require 'rails_helper'

RSpec.describe "Api::V1::Posts", type: :request do
  let(:user) { create(:user) }
  let(:other_user) { create(:user) }

  describe "GET /api/v1/posts" do
    context "when authenticated" do
      before do
        post "/api/v1/login", params: { username: user.username, password: "password" }
      end

      it "returns posts" do
        create(:post, author: user)
        get "/api/v1/posts"
        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json["posts"]).to be_an(Array)
      end
    end

    context "when not authenticated" do
      it "returns public posts" do
        create(:post)
        get "/api/v1/posts"
        expect(response).to have_http_status(:success)
      end
    end
  end
end
```

**Deliverables:**
- ✅ Rails API mode configured
- ✅ API namespace with v1
- ✅ All endpoints return JSON
- ✅ CORS configured
- ✅ Request specs passing
- ✅ Backward compatibility maintained (old routes still work)

---

### Phase 2: JWT Authentication (Week 2-3)

**Goal:** Replace session-based auth with JWT tokens

#### 2.1 Add JWT Gem

**File: `Gemfile`**
```ruby
gem 'jwt'
```

#### 2.2 Create JWT Service

**File: `app/services/jwt_service.rb`**
```ruby
class JwtService
  SECRET_KEY = Rails.application.credentials.secret_key_base || 'development-secret-key'
  ALGORITHM = 'HS256'
  EXPIRATION_TIME = 24.hours

  def self.encode(payload)
    payload[:exp] = EXPIRATION_TIME.from_now.to_i
    JWT.encode(payload, SECRET_KEY, ALGORITHM)
  end

  def self.decode(token)
    decoded = JWT.decode(token, SECRET_KEY, true, { algorithm: ALGORITHM })[0]
    HashWithIndifferentAccess.new(decoded)
  rescue JWT::DecodeError, JWT::ExpiredSignature
    nil
  end
end
```

#### 2.3 Update Base Controller for JWT

**File: `app/controllers/api/v1/base_controller.rb`**
```ruby
module Api
  module V1
    class BaseController < ActionController::API
      include ActionController::Cookies

      before_action :authenticate_user

      private

      def current_user
        @current_user ||= begin
          token = extract_token
          return nil unless token

          payload = JwtService.decode(token)
          return nil unless payload

          User.find_by(id: payload[:user_id])
        end
      end

      def authenticate_user
        unless current_user
          render json: { error: 'Unauthorized' }, status: :unauthorized
        end
      end

      def extract_token
        # Check Authorization header first
        auth_header = request.headers['Authorization']
        if auth_header && auth_header.start_with?('Bearer ')
          return auth_header.split(' ').last
        end

        # Fallback to cookie (for backward compatibility)
        cookies[:jwt_token]
      end

      # ... error handling methods ...
    end
  end
end
```

#### 2.4 Update Sessions Controller

**File: `app/controllers/api/v1/sessions_controller.rb`**
```ruby
module Api
  module V1
    class SessionsController < BaseController
      skip_before_action :authenticate_user, only: [:create]

      def create
        user = User.find_by(username: params[:username])

        if user&.authenticate(params[:password])
          token = JwtService.encode({ user_id: user.id })

          # Set cookie for backward compatibility
          cookies[:jwt_token] = {
            value: token,
            httponly: true,
            secure: Rails.env.production?,
            same_site: :lax
          }

          render json: {
            user: user_json(user),
            token: token,
            message: "Login successful"
          }
        else
          render json: { error: "Invalid username or password" }, status: :unauthorized
        end
      end

      def show
        render json: { user: user_json(current_user) }
      end

      def destroy
        cookies.delete(:jwt_token)
        render json: { message: "Logged out successfully" }
      end

      private

      def user_json(user)
        {
          id: user.id,
          username: user.username,
          description: user.description,
          followers_count: user.followers_count,
          following_count: user.following_count,
          posts_count: user.posts_count
        }
      end
    end
  end
end
```

#### 2.5 Token Refresh Endpoint

**File: `config/routes.rb`**
```ruby
namespace :api do
  namespace :v1 do
    post "/refresh", to: "sessions#refresh"
  end
end
```

**File: `app/controllers/api/v1/sessions_controller.rb`**
```ruby
def refresh
  if current_user
    token = JwtService.encode({ user_id: current_user.id })
    cookies[:jwt_token] = {
      value: token,
      httponly: true,
      secure: Rails.env.production?,
      same_site: :lax
    }
    render json: { token: token }
  else
    render json: { error: "Unauthorized" }, status: :unauthorized
  end
end
```

**Deliverables:**
- ✅ JWT service implemented
- ✅ Token-based authentication
- ✅ Token refresh endpoint
- ✅ Backward compatibility (cookie support)
- ✅ Tests passing

---

### Phase 3: Frontend Setup (Week 3-4)

**Goal:** Create React frontend application

#### 3.1 Initialize React App

```bash
# Create frontend directory
mkdir -p frontend
cd frontend

# Create React app with Vite (faster than create-react-app)
npm create vite@latest . -- --template react

# Install dependencies
npm install axios react-router-dom
```

#### 3.2 Project Structure

```
frontend/
├── public/
├── src/
│   ├── components/
│   │   ├── Post.jsx
│   │   ├── PostList.jsx
│   │   ├── PostForm.jsx
│   │   ├── UserProfile.jsx
│   │   └── Navigation.jsx
│   ├── services/
│   │   ├── api.js
│   │   └── auth.js
│   ├── context/
│   │   └── AuthContext.jsx
│   ├── pages/
│   │   ├── Home.jsx
│   │   ├── Login.jsx
│   │   ├── Signup.jsx
│   │   ├── PostDetail.jsx
│   │   └── UserProfile.jsx
│   ├── App.jsx
│   ├── main.jsx
│   └── index.css
├── package.json
└── vite.config.js
```

#### 3.3 API Client Service

**File: `frontend/src/services/api.js`**
```javascript
import axios from 'axios';

const API_BASE_URL = import.meta.env.VITE_API_URL || 'http://localhost:3000/api/v1';

const api = axios.create({
  baseURL: API_BASE_URL,
  headers: {
    'Content-Type': 'application/json',
  },
});

// Request interceptor to add JWT token
api.interceptors.request.use(
  (config) => {
    const token = localStorage.getItem('jwt_token');
    if (token) {
      config.headers.Authorization = `Bearer ${token}`;
    }
    return config;
  },
  (error) => {
    return Promise.reject(error);
  }
);

// Response interceptor to handle errors
api.interceptors.response.use(
  (response) => response,
  (error) => {
    if (error.response?.status === 401) {
      // Token expired or invalid
      localStorage.removeItem('jwt_token');
      window.location.href = '/login';
    }
    return Promise.reject(error);
  }
);

export default api;
```

#### 3.4 Authentication Service

**File: `frontend/src/services/auth.js`**
```javascript
import api from './api';

export const authService = {
  async login(username, password) {
    const response = await api.post('/login', { username, password });
    if (response.data.token) {
      localStorage.setItem('jwt_token', response.data.token);
    }
    return response.data;
  },

  async signup(userData) {
    const response = await api.post('/users', { user: userData });
    if (response.data.token) {
      localStorage.setItem('jwt_token', response.data.token);
    }
    return response.data;
  },

  async logout() {
    localStorage.removeItem('jwt_token');
    await api.delete('/logout');
  },

  async getCurrentUser() {
    const response = await api.get('/me');
    return response.data.user;
  },

  isAuthenticated() {
    return !!localStorage.getItem('jwt_token');
  }
};
```

#### 3.5 Auth Context

**File: `frontend/src/context/AuthContext.jsx`**
```javascript
import { createContext, useContext, useState, useEffect } from 'react';
import { authService } from '../services/auth';

const AuthContext = createContext();

export const useAuth = () => {
  const context = useContext(AuthContext);
  if (!context) {
    throw new Error('useAuth must be used within AuthProvider');
  }
  return context;
};

export const AuthProvider = ({ children }) => {
  const [user, setUser] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (authService.isAuthenticated()) {
      authService.getCurrentUser()
        .then(setUser)
        .catch(() => {
          localStorage.removeItem('jwt_token');
        })
        .finally(() => setLoading(false));
    } else {
      setLoading(false);
    }
  }, []);

  const login = async (username, password) => {
    const data = await authService.login(username, password);
    setUser(data.user);
    return data;
  };

  const signup = async (userData) => {
    const data = await authService.signup(userData);
    setUser(data.user);
    return data;
  };

  const logout = async () => {
    await authService.logout();
    setUser(null);
  };

  return (
    <AuthContext.Provider value={{ user, login, signup, logout, loading }}>
      {children}
    </AuthContext.Provider>
  );
};
```

#### 3.6 Main App Component

**File: `frontend/src/App.jsx`**
```javascript
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { AuthProvider, useAuth } from './context/AuthContext';
import Home from './pages/Home';
import Login from './pages/Login';
import Signup from './pages/Signup';
import PostDetail from './pages/PostDetail';
import UserProfile from './pages/UserProfile';
import Navigation from './components/Navigation';

const PrivateRoute = ({ children }) => {
  const { user, loading } = useAuth();

  if (loading) {
    return <div>Loading...</div>;
  }

  return user ? children : <Navigate to="/login" />;
};

function AppRoutes() {
  return (
    <Routes>
      <Route path="/" element={<Home />} />
      <Route path="/login" element={<Login />} />
      <Route path="/signup" element={<Signup />} />
      <Route path="/posts/:id" element={<PostDetail />} />
      <Route path="/users/:id" element={<UserProfile />} />
      <Route path="*" element={<Navigate to="/" />} />
    </Routes>
  );
}

function App() {
  return (
    <AuthProvider>
      <BrowserRouter>
        <Navigation />
        <AppRoutes />
      </BrowserRouter>
    </AuthProvider>
  );
}

export default App;
```

#### 3.7 Example Page Component

**File: `frontend/src/pages/Home.jsx`**
```javascript
import { useState, useEffect } from 'react';
import { useAuth } from '../context/AuthContext';
import api from '../services/api';
import PostList from '../components/PostList';
import PostForm from '../components/PostForm';

export default function Home() {
  const { user } = useAuth();
  const [posts, setPosts] = useState([]);
  const [loading, setLoading] = useState(true);
  const [cursor, setCursor] = useState(null);
  const [hasNext, setHasNext] = useState(false);

  useEffect(() => {
    loadPosts();
  }, []);

  const loadPosts = async (nextCursor = null) => {
    try {
      setLoading(true);
      const params = nextCursor ? { cursor: nextCursor } : {};
      const response = await api.get('/posts', { params });
      const data = response.data;

      if (nextCursor) {
        setPosts(prev => [...prev, ...data.posts]);
      } else {
        setPosts(data.posts);
      }

      setCursor(data.pagination.cursor);
      setHasNext(data.pagination.has_next);
    } catch (error) {
      console.error('Failed to load posts:', error);
    } finally {
      setLoading(false);
    }
  };

  const handleLoadMore = () => {
    if (hasNext && cursor) {
      loadPosts(cursor);
    }
  };

  return (
    <div className="container mx-auto px-4 py-8">
      <h1 className="text-3xl font-bold mb-6">Feed</h1>

      {user && <PostForm onPostCreated={loadPosts} />}

      <PostList
        posts={posts}
        loading={loading}
        hasNext={hasNext}
        onLoadMore={handleLoadMore}
      />
    </div>
  );
}
```

**Deliverables:**
- ✅ React app initialized
- ✅ API client configured
- ✅ Authentication context
- ✅ Basic routing
- ✅ Component structure
- ✅ Frontend can communicate with API

---

### Phase 4: Data Flow Integration (Week 4-5)

**Goal:** Ensure seamless data flow between frontend and backend

#### 4.1 API Response Standardization

Create a concern for consistent API responses:

**File: `app/controllers/concerns/api_response.rb`**
```ruby
module ApiResponse
  extend ActiveSupport::Concern

  included do
    def render_success(data, status: :ok)
      render json: { data: data }, status: status
    end

    def render_error(message, status: :unprocessable_entity, errors: nil)
      json = { error: message }
      json[:errors] = errors if errors
      render json: json, status: status
    end

    def render_paginated(collection, serializer: nil)
      render json: {
        data: collection.map { |item| serializer ? serializer.call(item) : item },
        pagination: {
          cursor: collection.last&.id,
          has_next: collection.size > params[:per_page].to_i
        }
      }
    end
  end
end
```

#### 4.2 Error Handling Middleware

**File: `app/middleware/api_error_handler.rb`**
```ruby
class ApiErrorHandler
  def initialize(app)
    @app = app
  end

  def call(env)
    @app.call(env)
  rescue StandardError => e
    Rails.logger.error("API Error: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))

    [
      500,
      { 'Content-Type' => 'application/json' },
      [{ error: 'Internal server error' }.to_json]
    ]
  end
end
```

#### 4.3 Real-time Updates (Optional)

If you want real-time updates, use Action Cable:

**File: `app/channels/posts_channel.rb`**
```ruby
class PostsChannel < ApplicationCable::Channel
  def subscribed
    stream_from "posts"
  end

  def unsubscribed
    # Any cleanup needed when channel is unsubscribed
  end
end
```

**Frontend:**
```javascript
import { createConsumer } from '@rails/actioncable';

const cable = createConsumer('ws://localhost:3000/cable');

cable.subscriptions.create('PostsChannel', {
  received(data) {
    // Handle new post
    console.log('New post:', data);
  }
});
```

**Deliverables:**
- ✅ Consistent API responses
- ✅ Error handling standardized
- ✅ Data flow tested end-to-end
- ✅ Real-time updates (optional)

---

### Phase 5: Docker Configuration (Week 5)

**Goal:** Configure Docker for three-layer architecture

#### 5.1 Update Docker Compose

**File: `docker-compose.yml`**
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

  # Rails API (backend)
  api:
    build:
      context: .
      dockerfile: Dockerfile
    command: sh -c "rm -f /rails/tmp/pids/server*.pid && bin/rails server -b 0.0.0.0 -p 3000"
    environment:
      RAILS_ENV: development
      DATABASE_URL: postgresql://${DATABASE_USERNAME:-postgres}:${DATABASE_PASSWORD:-postgres}@db:5432/microblog_development
      DATABASE_HOST: db
      DATABASE_PORT: 5432
      DATABASE_USERNAME: ${DATABASE_USERNAME:-postgres}
      DATABASE_PASSWORD: ${DATABASE_PASSWORD:-postgres}
      REPLICA_HOST: db
      REPLICA_PORT: 5432
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
      SOLID_QUEUE_IN_PUMA: "true"
      FRONTEND_URL: http://localhost:3001
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
      - "traefik.http.routers.api.rule=Host(`api.localhost`) || Host(`localhost`) && PathPrefix(`/api`)"
      - "traefik.http.routers.api.entrypoints=web"
      - "traefik.http.services.api.loadbalancer.server.port=3000"

  # React Frontend (development server)
  frontend:
    build:
      context: ./frontend
      dockerfile: Dockerfile.dev
    command: npm run dev -- --host 0.0.0.0
    environment:
      VITE_API_URL: http://localhost/api/v1
    ports:
      - "3001:5173"
    volumes:
      - ./frontend:/app
      - /app/node_modules
    networks:
      - microblog-network
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.frontend.rule=Host(`localhost`) && !PathPrefix(`/api`)"
      - "traefik.http.routers.frontend.entrypoints=web"
      - "traefik.http.services.frontend.loadbalancer.server.port=5173"

  # Load balancer (Traefik)
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
      - api
      - frontend
    networks:
      - microblog-network
    labels:
        - "traefik.enable=true"

  # Database migrations (run once)
  migrate:
    build:
      context: .
      dockerfile: Dockerfile
    command: >
      sh -c "
        bin/rails runner script/docker_setup_solid_databases.rb &&
        bin/rails db:create db:migrate &&
        yes | bin/rails solid_cache:install &&
        yes | bin/rails solid_queue:install &&
        yes | bin/rails solid_cable:install
      "
    environment:
      RAILS_ENV: development
      DATABASE_URL: postgresql://${DATABASE_USERNAME:-postgres}:${DATABASE_PASSWORD:-postgres}@db:5432/microblog_development
      DATABASE_HOST: db
      DATABASE_PORT: 5432
      DATABASE_USERNAME: ${DATABASE_USERNAME:-postgres}
      DATABASE_PASSWORD: ${DATABASE_PASSWORD:-postgres}
      REPLICA_HOST: db
      REPLICA_PORT: 5432
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
      CABLE_DB_USERNAME: ${CACHE_DB_USERNAME:-microblog_cable}
      CABLE_DB_PASSWORD: ${CACHE_DB_PASSWORD:-cable_password}
      RAILS_MASTER_KEY: ${RAILS_MASTER_KEY:-}
      SECRET_KEY_BASE: ${SECRET_KEY_BASE:-}
    depends_on:
      db:
        condition: service_healthy
    volumes:
      - .:/rails
    networks:
      - microblog-network
    profiles:
      - tools

volumes:
  pg_data:

networks:
  microblog-network:
    driver: bridge
```

#### 5.2 Frontend Dockerfile (Development)

**File: `frontend/Dockerfile.dev`**
```dockerfile
FROM node:20-alpine

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm install

# Copy application code
COPY . .

# Expose Vite dev server port
EXPOSE 5173

# Start dev server
CMD ["npm", "run", "dev", "--", "--host", "0.0.0.0"]
```

#### 5.3 Frontend Dockerfile (Production)

**File: `frontend/Dockerfile`**
```dockerfile
# Build stage
FROM node:20-alpine AS builder

WORKDIR /app

COPY package*.json ./
RUN npm ci

COPY . .
RUN npm run build

# Production stage
FROM nginx:alpine

# Copy built assets
COPY --from=builder /app/dist /usr/share/nginx/html

# Copy nginx configuration
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
```

#### 5.4 Nginx Configuration for Frontend

**File: `frontend/nginx.conf`**
```nginx
server {
    listen 80;
    server_name localhost;
    root /usr/share/nginx/html;
    index index.html;

    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/xml text/javascript application/x-javascript application/xml+rss application/json;

    # Serve static files
    location / {
        try_files $uri $uri/ /index.html;
    }

    # Cache static assets
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    # API proxy (for production)
    location /api {
        proxy_pass http://api:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }
}
```

**Deliverables:**
- ✅ Docker Compose updated for three services
- ✅ Frontend development Dockerfile
- ✅ Frontend production Dockerfile
- Traefik routing configured for both frontend and API
- ✅ All services communicate via Docker network

---

### Phase 6: Testing & Migration (Week 6)

**Goal:** Test thoroughly and migrate from old to new architecture

#### 6.1 Integration Tests

**File: `spec/requests/api/v1/integration_spec.rb`**
```ruby
require 'rails_helper'

RSpec.describe "API Integration", type: :request do
  describe "Full user flow" do
    it "allows user to sign up, login, create post, and view feed" do
      # Sign up
      post "/api/v1/users", params: {
        user: {
          username: "testuser",
          password: "password123",
          password_confirmation: "password123"
        }
      }
      expect(response).to have_http_status(:created)

      token = JSON.parse(response.body)["token"]

      # Create post
      post "/api/v1/posts", params: {
        post: { content: "Hello world" }
      }, headers: { "Authorization" => "Bearer #{token}" }
      expect(response).to have_http_status(:created)

      # View feed
      get "/api/v1/posts", headers: { "Authorization" => "Bearer #{token}" }
      expect(response).to have_http_status(:success)
      posts = JSON.parse(response.body)["posts"]
      expect(posts.length).to be > 0
    end
  end
end
```

#### 6.2 Frontend E2E Tests

**File: `frontend/src/__tests__/App.test.jsx`**
```javascript
import { render, screen, waitFor } from '@testing-library/react';
import { BrowserRouter } from 'react-router-dom';
import App from '../App';
import * as authService from '../services/auth';

jest.mock('../services/auth');

describe('App', () => {
  it('renders login page when not authenticated', () => {
    authService.isAuthenticated.mockReturnValue(false);
    render(
      <BrowserRouter>
        <App />
      </BrowserRouter>
    );
    expect(screen.getByText(/login/i)).toBeInTheDocument();
  });
});
```

#### 6.3 Migration Checklist

- [ ] **Week 1-2: API Foundation**
  - [ ] Rails API mode configured
  - [ ] All endpoints return JSON
  - [ ] CORS configured
  - [ ] All API endpoints tested
  - [ ] Backward compatibility maintained

- [ ] **Week 2-3: JWT Authentication**
  - [ ] JWT service implemented
  - [ ] Token-based auth working
  - [ ] Token refresh implemented
  - [ ] Backward compatibility (cookie support)
  - [ ] Tests passing

- [ ] **Week 3-4: Frontend Setup**
  - [ ] React app initialized
  - [ ] API client configured
  - [ ] Authentication context
  - [ ] Basic routing
  - [ ] All pages implemented
  - [ ] Frontend can communicate with API

- [ ] **Week 4-5: Data Flow Integration**
  - [ ] API responses standardized
  - [ ] Error handling implemented
  - [ ] Data flow tested end-to-end
  - [ ] Real-time updates (optional)

- [ ] **Week 5: Docker Configuration**
  - [ ] Docker Compose updated
  - [ ] Frontend Dockerfile created
  - [ ] All services communicate
  - [ ] Traefik routing configured

- [ ] **Week 6: Testing & Migration**
  - [ ] Integration tests passing
  - [ ] Frontend E2E tests passing
  - [ ] Load testing completed
  - [ ] Migration plan executed
  - [ ] Old routes removed
  - [ ] Documentation updated

#### 6.4 Gradual Migration Strategy

**Option 1: Feature Flags**
```ruby
# config/application.rb
config.feature_flags = {
  api_only: ENV['API_ONLY'] == 'true'
}
```

**Option 2: Subdomain Routing**
- `app.microblog.com` → Old Rails app
- `api.microblog.com` → New API
- `microblog.com` → New React frontend

**Option 3: Path-Based Routing**
- `/api/v1/*` → New API
- `/*` → New React frontend (production)
- Keep old routes for backward compatibility during transition

**Deliverables:**
- ✅ All tests passing
- ✅ Load testing completed
- ✅ Migration executed
- ✅ Old routes removed
- ✅ Documentation updated

---

## Data Flow

### Authentication Flow

```
┌─────────┐                    ┌─────────┐                    ┌─────────┐
│ Frontend│                    │   API   │                    │Database │
│ (React) │                    │ (Rails) │                    │(Postgres)│
└────┬────┘                    └────┬────┘                    └────┬────┘
     │                              │                              │
     │ 1. POST /api/v1/login        │                              │
     │    {username, password}       │                              │
     │─────────────────────────────>│                              │
     │                              │ 2. Find user & authenticate  │
     │                              │─────────────────────────────>│
     │                              │<─────────────────────────────│
     │                              │ 3. Generate JWT token        │
     │ 4. Return {token, user}      │                              │
     │<─────────────────────────────│                              │
     │ 5. Store token in localStorage│                              │
     │                              │                              │
     │ 6. GET /api/v1/posts         │                              │
     │    Authorization: Bearer {token}│                          │
     │─────────────────────────────>│                              │
     │                              │ 7. Decode JWT & get user_id │
     │                              │ 8. Query posts              │
     │                              │─────────────────────────────>│
     │                              │<─────────────────────────────│
     │ 9. Return {posts}            │                              │
     │<─────────────────────────────│                              │
```

### Post Creation Flow

```
┌─────────┐                    ┌─────────┐                    ┌─────────┐
│ Frontend│                    │   API   │                    │Database │
│ (React) │                    │ (Rails) │                    │(Postgres)│
└────┬────┘                    └────┬────┘                    └────┬────┘
     │                              │                              │
     │ 1. POST /api/v1/posts         │                              │
     │    {content, parent_id}       │                              │
     │    Authorization: Bearer {token}│                          │
     │─────────────────────────────>│                              │
     │                              │ 2. Authenticate user         │
     │                              │ 3. Create post               │
     │                              │─────────────────────────────>│
     │                              │<─────────────────────────────│
     │                              │ 4. Trigger after_create      │
     │                              │ 5. Queue FanOutFeedJob       │
     │                              │─────────────────────────────>│
     │ 6. Return {post}             │                              │
     │<─────────────────────────────│                              │
     │                              │                              │
     │                              │ 7. Background job processes  │
     │                              │    fan-out to followers      │
     │                              │─────────────────────────────>│
     │                              │<─────────────────────────────│
```

### Feed Query Flow

```
┌─────────┐                    ┌─────────┐                    ┌─────────┐
│ Frontend│                    │   API   │                    │Database │
│ (React) │                    │ (Rails) │                    │(Postgres)│
└────┬────┘                    └────┬────┘                    └────┬────┘
     │                              │                              │
     │ 1. GET /api/v1/posts?filter=timeline│                       │
     │    Authorization: Bearer {token}│                          │
     │─────────────────────────────>│                              │
     │                              │ 2. Authenticate user         │
     │                              │ 3. Check cache               │
     │                              │─────────────────────────────>│
     │                              │<─────────────────────────────│
     │                              │ 4. If cache miss:            │
     │                              │    Query feed_entries        │
     │                              │─────────────────────────────>│
     │                              │<─────────────────────────────│
     │                              │ 5. Cache result              │
     │                              │─────────────────────────────>│
     │ 6. Return {posts, pagination}│                              │
     │<─────────────────────────────│                              │
```

---

## Challenges & Solutions

### Challenge 1: CORS Configuration

**Problem:** Frontend and API on different origins need CORS configuration.

**Solution:**
- Configure `rack-cors` in Rails API
- Set appropriate origins (development vs production)
- Handle credentials (cookies, authorization headers)

**Implementation:**
```ruby
# config/initializers/cors.rb
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins Rails.env.development? ? ['http://localhost:3001', 'http://localhost:5173'] : ENV['FRONTEND_URL']
    resource '*',
      headers: :any,
      methods: [:get, :post, :put, :patch, :delete, :options, :head],
      credentials: true
  end
end
```

### Challenge 2: Session vs JWT Transition

**Problem:** Need to support both session-based and JWT authentication during migration.

**Solution:**
- Implement dual authentication in BaseController
- Check for JWT token first, fall back to session
- Gradually migrate users to JWT

**Implementation:**
```ruby
def current_user
  @current_user ||= begin
    # Try JWT first
    token = extract_token
    if token
      payload = JwtService.decode(token)
      return User.find_by(id: payload[:user_id]) if payload
    end

    # Fallback to session
    User.find_by(id: session[:user_id]) if session[:user_id]
  end
end
```

### Challenge 3: State Management

**Problem:** Frontend needs to manage complex state (posts, users, authentication).

**Solution:**
- Use React Context for authentication
- Consider Redux/Zustand for complex state
- Use React Query for server state management

**Recommendation:**
- Start with Context API + React Query
- Migrate to Redux/Zustand if needed

### Challenge 4: Error Handling

**Problem:** Need consistent error handling across frontend and backend.

**Solution:**
- Standardize API error responses
- Create error handling utilities in frontend
- Use axios interceptors for global error handling

**Implementation:**
```javascript
// Frontend error handling
api.interceptors.response.use(
  response => response,
  error => {
    if (error.response?.status === 401) {
      // Handle unauthorized
    } else if (error.response?.status >= 500) {
      // Handle server errors
    }
    return Promise.reject(error);
  }
);
```

### Challenge 5: Real-time Updates

**Problem:** Need real-time updates for new posts, notifications.

**Solution:**
- Use Action Cable (WebSockets) for real-time updates
- Frontend connects to WebSocket endpoint
- Broadcast events from backend

**Implementation:**
```ruby
# Backend
ActionCable.server.broadcast("posts", {
  type: "new_post",
  post: post_json(post)
})

# Frontend
const cable = createConsumer('ws://localhost:3000/cable');
cable.subscriptions.create('PostsChannel', {
  received(data) {
    // Update UI
  }
});
```

### Challenge 6: File Uploads

**Problem:** Handle image/file uploads in API-only architecture.

**Solution:**
- Use Active Storage for file handling
- Return signed URLs from API
- Frontend uploads directly to storage (or through API)

**Implementation:**
```ruby
# API returns signed URL
def post_json(post)
  {
    id: post.id,
    content: post.content,
    image_url: post.image.attached? ? post.image.url : nil
  }
end
```

### Challenge 7: SEO

**Problem:** Client-side rendered React app has poor SEO.

**Solution:**
- Use Next.js for SSR (future migration)
- Implement server-side rendering for public pages
- Use meta tags and Open Graph

**Short-term:**
- Ensure all public routes are accessible
- Add meta tags dynamically
- Use React Helmet for meta management

---

## Docker Configuration

### Development Setup

**Starting Services:**
```bash
# Start all services
docker compose up -d

# Start with specific services
docker compose up -d db api frontend traefik

# Scale API instances
docker compose up -d --scale api=3

# View logs
docker compose logs -f api
docker compose logs -f frontend
```

### Production Setup

**File: `docker-compose.prod.yml`**
```yaml
services:
  api:
    build:
      context: .
      dockerfile: Dockerfile.prod
    environment:
      RAILS_ENV: production
      DATABASE_URL: ${DATABASE_URL}
      SECRET_KEY_BASE: ${SECRET_KEY_BASE}
      FRONTEND_URL: ${FRONTEND_URL}
    deploy:
      replicas: 3
      resources:
        limits:
          cpus: '2'
          memory: 2G

  frontend:
    build:
      context: ./frontend
      dockerfile: Dockerfile
    deploy:
      replicas: 2

  db:
    image: postgres:16
    deploy:
      resources:
        limits:
          cpus: '4'
          memory: 4G
    volumes:
      - pg_data:/var/lib/postgresql/data
```

### Environment Variables

**File: `.env.example`**
```bash
# Database
DATABASE_USERNAME=postgres
DATABASE_PASSWORD=postgres

# Rails
SECRET_KEY_BASE=your-secret-key-base
RAILS_MASTER_KEY=your-master-key

# Frontend
FRONTEND_URL=http://localhost:3001
VITE_API_URL=http://localhost/api/v1

# Solid databases
CACHE_DB_USERNAME=microblog_cache
CACHE_DB_PASSWORD=cache_password
QUEUE_DB_USERNAME=microblog_queue
QUEUE_DB_PASSWORD=queue_password
CABLE_DB_USERNAME=microblog_cable
CABLE_DB_PASSWORD=cable_password
```

---

## Testing Strategy

### Backend Tests

**Unit Tests:**
- Model tests (User, Post, Follow)
- Service tests (JwtService)
- Controller tests (API endpoints)

**Integration Tests:**
- Full request/response cycles
- Authentication flows
- Error handling

**Performance Tests:**
- Load testing with k6
- Query performance
- Caching effectiveness

### Frontend Tests

**Unit Tests:**
- Component tests
- Service tests
- Utility function tests

**Integration Tests:**
- API integration
- Authentication flow
- User interactions

**E2E Tests:**
- Full user flows
- Critical paths
- Error scenarios

### Test Coverage Goals

- Backend: 80%+ coverage
- Frontend: 70%+ coverage
- Critical paths: 100% coverage

---

## Migration Strategy

This section explains **how to run both the old monolith (ERB views) and new architecture (React + API) in parallel** during migration.

### Architecture Overview: Parallel Run

During migration, you run **three separate services** that all share the same database:

```
┌─────────────────────────────────────────────────────────────┐
│                    Load Balancer (Traefik)                   │
│                    Routes traffic based on:                  │
│                    - Path (/api/* → API, /* → old or new)   │
│                    - Subdomain (app.example.com vs new.example.com) │
│                    - Feature flag (cookie/header)            │
└─────────────────────────────────────────────────────────────┘
                          ↓
        ┌─────────────────┴─────────────────┐
        ↓                                   ↓
┌───────────────────┐              ┌──────────────────┐
│  Old Monolith     │              │  New Architecture│
│  (Rails MVC)      │              │                  │
│  - ERB Views      │              │  ┌────────────┐ │
│  - Session Auth   │              │  │ React SPA  │ │
│  Port: 3000       │              │  │ Port: 3001 │ │
└───────────────────┘              │  └──────┬───────┘ │
        ↓                          │         ↓         │
┌───────────────────┐              │  ┌────────────┐ │
│  Same Database     │              │  │ Rails API  │ │
│  (PostgreSQL)      │◄─────────────┤  │ Port: 3002 │ │
│                    │              │  └────────────┘ │
│  - Users           │              │                │
│  - Posts           │              └────────────────┘
│  - Follows         │
│  - FeedEntries     │
└───────────────────┘
```

### Phase 1: Parallel Run (Week 1-4)

**Goal:** Run both old and new systems simultaneously, sharing the same database

#### Strategy 1: Path-Based Routing (Recommended)

Route traffic based on URL path:
- `/api/v1/*` → New Rails API
- `/*` → Old Rails monolith (or new React app based on feature flag)

**Docker Compose Configuration:**

**File: `docker-compose.parallel.yml`**
```yaml
services:
  # Shared database (both systems use this)
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
    networks:
      - microblog-network

  # OLD SYSTEM: Rails Monolith (ERB views, session auth)
  web_old:
    build:
      context: .
      dockerfile: Dockerfile
    command: sh -c "rm -f /rails/tmp/pids/server*.pid && bin/rails server -b 0.0.0.0 -p 3000"
    environment:
      RAILS_ENV: development
      DATABASE_URL: postgresql://${DATABASE_USERNAME:-postgres}:${DATABASE_PASSWORD:-postgres}@db:5432/microblog_development
      # Disable API-only mode for old system
      API_ONLY: "false"
    ports:
      - "3000:3000"
    depends_on:
      db:
        condition: service_healthy
    volumes:
      - .:/rails
    networks:
      - microblog-network
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.web_old.rule=Host(`localhost`) && !PathPrefix(`/api`) && !PathPrefix(`/app`)"
      - "traefik.http.routers.web_old.entrypoints=web"
      - "traefik.http.services.web_old.loadbalancer.server.port=3000"

  # NEW SYSTEM: Rails API (JSON only, JWT auth)
  api:
    build:
      context: .
      dockerfile: Dockerfile
    command: sh -c "rm -f /rails/tmp/pids/server*.pid && bin/rails server -b 0.0.0.0 -p 3002"
    environment:
      RAILS_ENV: development
      DATABASE_URL: postgresql://${DATABASE_USERNAME:-postgres}:${DATABASE_PASSWORD:-postgres}@db:5432/microblog_development
      # Enable API-only mode
      API_ONLY: "true"
      FRONTEND_URL: http://localhost:3001
    ports:
      - "3002:3002"
    depends_on:
      db:
        condition: service_healthy
    volumes:
      - .:/rails
    networks:
      - microblog-network
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.api.rule=Host(`localhost`) && PathPrefix(`/api`)"
      - "traefik.http.routers.api.entrypoints=web"
      - "traefik.http.services.api.loadbalancer.server.port=3002"

  # NEW SYSTEM: React Frontend
  frontend:
    build:
      context: ./frontend
      dockerfile: Dockerfile.dev
    command: npm run dev -- --host 0.0.0.0 --port 5173
    environment:
      VITE_API_URL: http://localhost/api/v1
    ports:
      - "3001:5173"
    volumes:
      - ./frontend:/app
      - /app/node_modules
    networks:
      - microblog-network
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.frontend.rule=Host(`localhost`) && PathPrefix(`/app`)"
      - "traefik.http.routers.frontend.entrypoints=web"
      - "traefik.http.services.frontend.loadbalancer.server.port=5173"

  # Load balancer
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
      - "8080:8080"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    depends_on:
      - web_old
      - api
      - frontend
    networks:
      - microblog-network

volumes:
  pg_data:

networks:
  microblog-network:
    driver: bridge
```

**Routing Rules:**
- `http://localhost/` → Old monolith (ERB views)
- `http://localhost/api/v1/*` → New API (JSON)
- `http://localhost/app/*` → New React frontend

**Rails Application Configuration:**

**File: `config/application.rb`**
```ruby
module Microblog
  class Application < Rails::Application
    config.load_defaults 8.1

    # Enable API mode ONLY if API_ONLY env var is set
    if ENV['API_ONLY'] == 'true'
      config.api_only = true
      # Add CORS for API
      config.middleware.insert_before 0, Rack::Cors do
        allow do
          origins Rails.env.development? ? ['http://localhost:3001', 'http://localhost:5173'] : ENV['FRONTEND_URL']
          resource '*',
            headers: :any,
            methods: [:get, :post, :put, :patch, :delete, :options, :head],
            credentials: true
        end
      end
    else
      # Keep full Rails stack for old system
      config.api_only = false
    end

    # Database configuration (shared)
    config.active_record.database_selector = { delay: 2.seconds }
    config.active_record.database_resolver = ActiveRecord::Middleware::DatabaseSelector::Resolver
    config.active_record.database_resolver_context = ActiveRecord::Middleware::DatabaseSelector::Resolver::Session
  end
end
```

#### Strategy 2: Feature Flag Routing (Gradual Rollout)

Route users to new system based on feature flag (cookie or user ID hash):

**File: `app/controllers/application_controller.rb`**
```ruby
class ApplicationController < ActionController::Base
  # Check if user should use new frontend
  def use_new_frontend?
    return false unless current_user

    # Option 1: Cookie-based flag (manual opt-in for testing)
    return true if cookies[:use_new_frontend] == 'true'

    # Option 2: Percentage-based rollout (10% of users)
    user_hash = Digest::MD5.hexdigest(current_user.id.to_s).to_i(16)
    percentage = user_hash % 100
    percentage < 10  # 10% of users

    # Option 3: User list (specific users for beta testing)
    # return true if current_user.id.in?([1, 2, 3, 4, 5])
  end

  before_action :redirect_to_new_frontend, if: :use_new_frontend?

  private

  def redirect_to_new_frontend
    # Redirect to new React app if accessing old routes
    if request.path.start_with?('/') && !request.path.start_with?('/api')
      redirect_to "http://localhost:3001/app#{request.path}", allow_other_host: true
    end
  end
end
```

**Traefik Configuration with Feature Flag:**

**File: `docker-compose.yml` (updated)**
```yaml
services:
  traefik:
    image: traefik:v2.10
    command:
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--entrypoints.web.address=:80"
      - "--api.dashboard=true"
      - "--api.insecure=true"
    # Add middleware for feature flag routing
    labels:
      - "traefik.http.middlewares.redirect-new.redirectregex.regex=^http://localhost/(?!api|app).*"
      - "traefik.http.middlewares.redirect-new.redirectregex.replacement=http://localhost/app$${1}"
      - "traefik.http.middlewares.redirect-new.redirectregex.permanent=false"
```

#### Strategy 3: Subdomain Routing

Use different subdomains for old and new systems:

- `app.microblog.local` → Old monolith
- `api.microblog.local` → New API
- `microblog.local` → New React frontend

**File: `docker-compose.yml`**
```yaml
services:
  web_old:
    labels:
      - "traefik.http.routers.web_old.rule=Host(`app.localhost`)"
      - "traefik.http.routers.web_old.entrypoints=web"

  api:
    labels:
      - "traefik.http.routers.api.rule=Host(`api.localhost`) || Host(`localhost`) && PathPrefix(`/api`)"

  frontend:
    labels:
      - "traefik.http.routers.frontend.rule=Host(`localhost`)"
```

#### How Both Systems Share the Database

**Key Point:** Both systems use the **same PostgreSQL database**, so:

1. **Data Consistency:** Posts created in old system are immediately visible in new system
2. **User Sessions:**
   - Old system: Uses `session[:user_id]` (cookie-based)
   - New system: Uses JWT tokens
   - **Solution:** Implement dual authentication (see below)

**Dual Authentication Support:**

**File: `app/controllers/api/v1/base_controller.rb`**
```ruby
module Api
  module V1
    class BaseController < ActionController::API
      before_action :authenticate_user

      private

      def current_user
        @current_user ||= begin
          # Try JWT token first (new system)
          token = extract_jwt_token
          if token
            payload = JwtService.decode(token)
            return User.find_by(id: payload[:user_id]) if payload
          end

          # Fallback to session (old system compatibility)
          # This allows users logged in via old system to access API
          if session[:user_id]
            return User.find_by(id: session[:user_id])
          end

          nil
        end
      end

      def extract_jwt_token
        auth_header = request.headers['Authorization']
        if auth_header && auth_header.start_with?('Bearer ')
          return auth_header.split(' ').last
        end
        cookies[:jwt_token]
      end
    end
  end
end
```

#### Running Both Systems

**Start both systems:**
```bash
# Start all services
docker compose -f docker-compose.parallel.yml up -d

# Or start individually
docker compose -f docker-compose.parallel.yml up -d db
docker compose -f docker-compose.parallel.yml up -d web_old
docker compose -f docker-compose.parallel.yml up -d api
docker compose -f docker-compose.parallel.yml up -d frontend
docker compose -f docker-compose.parallel.yml up -d traefik
```

**Access points:**
- Old system: `http://localhost/` (ERB views)
- New API: `http://localhost/api/v1/posts`
- New frontend: `http://localhost:3001/app` (direct) or `http://localhost/app` (via Traefik)

#### Monitoring Both Systems

**1. Health Checks:**

```bash
# Old system health
curl http://localhost/up

# New API health
curl http://localhost/api/v1/up

# Frontend (check if server responds)
curl http://localhost:3001
```

**2. Logs:**

```bash
# Old system logs
docker compose -f docker-compose.parallel.yml logs -f web_old

# New API logs
docker compose -f docker-compose.parallel.yml logs -f api

# Frontend logs
docker compose -f docker-compose.parallel.yml logs -f frontend
```

**3. Database Monitoring:**

Both systems write to the same database, so monitor:
- Total connections (both systems combined)
- Query performance
- Lock contention (if any)

```bash
# Connect to database
docker compose -f docker-compose.parallel.yml exec db psql -U postgres -d microblog_development

# Check active connections
SELECT count(*) FROM pg_stat_activity WHERE datname = 'microblog_development';
```

#### Testing Parallel Run

**1. Create post in old system:**
```bash
# Login via old system
curl -X POST http://localhost/login \
  -d "username=alice&password=password" \
  -c cookies.txt

# Create post
curl -X POST http://localhost/posts \
  -b cookies.txt \
  -d "post[content]=Hello from old system"
```

**2. Verify in new API:**
```bash
# Get posts via new API
curl http://localhost/api/v1/posts \
  -H "Authorization: Bearer YOUR_JWT_TOKEN"
```

**3. Verify in new frontend:**
- Open `http://localhost:3001/app`
- Check if post appears

#### Common Issues and Solutions

**Issue 1: CORS Errors**
- **Problem:** Frontend can't call API due to CORS
- **Solution:** Ensure CORS is configured in API (see `config/application.rb` above)

**Issue 2: Session Conflicts**
- **Problem:** Old system uses cookies, new system uses JWT
- **Solution:** Use different cookie names or implement dual auth (see above)

**Issue 3: Port Conflicts**
- **Problem:** Both systems try to use port 3000
- **Solution:** Use different ports (old: 3000, API: 3002, frontend: 3001)

**Issue 4: Database Locking**
- **Problem:** Both systems writing simultaneously
- **Solution:** PostgreSQL handles concurrent writes well; monitor for deadlocks

---

### Phase 2: Gradual Migration (Week 5-6)

**Goal:** Gradually migrate users from old to new system

#### Step 1: Internal Testing (10% of users)

**Feature Flag Implementation:**

**File: `app/models/concerns/migration_feature_flag.rb`**
```ruby
module MigrationFeatureFlag
  extend ActiveSupport::Concern

  def should_use_new_frontend?
    # Check cookie first (for manual testing)
    return true if cookies[:use_new_frontend] == 'true'
    return false if cookies[:use_new_frontend] == 'false'

    # Check user ID hash (10% of users)
    user_hash = Digest::MD5.hexdigest(id.to_s).to_i(16)
    percentage = user_hash % 100
    percentage < 10
  end
end
```

**File: `app/models/user.rb`**
```ruby
class User < ApplicationRecord
  include MigrationFeatureFlag
  # ...
end
```

**Update routing:**
```ruby
# In old system controller
before_action :redirect_to_new_frontend, if: :should_use_new_frontend?

def should_use_new_frontend?
  current_user&.should_use_new_frontend?
end

def redirect_to_new_frontend
  redirect_to "http://localhost:3001/app#{request.path}", allow_other_host: true
end
```

#### Step 2: Monitor and Adjust

**Metrics to track:**
- Error rates in both systems
- Response times
- User feedback
- Database performance

**Gradually increase percentage:**
```ruby
# Week 5: 10% → 25%
percentage < 25

# Week 6: 25% → 50%
percentage < 50

# Week 6 end: 50% → 100%
percentage < 100
```

---

### Phase 3: Cutover (Week 7)

**Goal:** Route all traffic to new system

**1. Update Traefik routing:**
```yaml
# Remove old system routing
# web_old service can be stopped or removed

# All traffic goes to new system
frontend:
  labels:
    - "traefik.http.routers.frontend.rule=Host(`localhost`)"
```

**2. Keep old system as backup:**
- Don't delete old system yet
- Keep it running but not receiving traffic
- Can be quickly re-enabled if issues arise

**3. Monitor for 1 week:**
- Watch error rates
- Monitor performance
- Collect user feedback

---

### Phase 4: Cleanup (Week 8)

**Goal:** Remove old system code

**1. Remove old routes:**
```ruby
# config/routes.rb
# Remove old MVC routes
# Keep only API routes
```

**2. Remove old controllers:**
```bash
# Remove old controllers (keep API controllers)
rm app/controllers/posts_controller.rb
rm app/controllers/users_controller.rb
# Keep app/controllers/api/v1/*
```

**3. Remove old views:**
```bash
rm -rf app/views/posts
rm -rf app/views/users
rm -rf app/views/sessions
```

**4. Update Docker Compose:**
```yaml
# Remove web_old service
# Keep only api, frontend, db, traefik
```

**5. Update application config:**
```ruby
# config/application.rb
# Always enable API mode
config.api_only = true
```

---

## Rollback Plan

### If Issues Occur

1. **Immediate Rollback:**
   - Route traffic back to old system
   - Disable feature flag
   - Investigate issues

2. **Data Consistency:**
   - Ensure database schema compatible
   - Verify data integrity
   - Check for data loss

3. **Communication:**
   - Notify stakeholders
   - Document issues
   - Plan fix timeline

### Rollback Checklist

- [ ] Feature flag disabled
- [ ] Traffic routed to old system
- [ ] Database integrity verified
- [ ] Issues documented
- [ ] Fix plan created

---

## Success Metrics

### Performance Metrics

- API response time: <200ms (p95)
- Frontend load time: <2s
- Time to interactive: <3s
- Error rate: <0.1%

### Business Metrics

- User satisfaction: Maintain or improve
- Feature parity: 100%
- Uptime: 99.9%+

### Technical Metrics

- Test coverage: 80%+
- API documentation: Complete
- Code quality: Maintain standards

---

## Timeline Summary

| Phase | Duration | Key Deliverables |
|-------|----------|------------------|
| Phase 1: Rails API Foundation | Week 1-2 | API endpoints, JSON responses, CORS |
| Phase 2: JWT Authentication | Week 2-3 | JWT service, token auth, refresh |
| Phase 3: Frontend Setup | Week 3-4 | React app, API client, routing |
| Phase 4: Data Flow Integration | Week 4-5 | Standardized responses, error handling |
| Phase 5: Docker Configuration | Week 5 | Docker Compose, frontend Dockerfile |
| Phase 6: Testing & Migration | Week 6 | Integration tests, migration execution |

**Total Duration:** 6 weeks

---

## Next Steps

1. **Review this plan** with team
2. **Set up development environment** (Docker, dependencies)
3. **Begin Phase 1** (Rails API Foundation)
4. **Set up CI/CD** for automated testing
5. **Create API documentation** (OpenAPI/Swagger)
6. **Plan deployment strategy** (staging, production)

---

## Production Deployment to DigitalOcean VPS

This section explains how to deploy the three-layer architecture to DigitalOcean VPS using **Kamal** for the Rails API, and how each layer connects to each other.

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    DigitalOcean VPS                          │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  Load Balancer / Reverse Proxy (Traefik)              │  │
│  │  - Port 80/443                                        │  │
│  │  - SSL/TLS termination                                │  │
│  │  - Routes: api.example.com → API, www.example.com → Frontend │
│  └──────────────────────────────────────────────────────┘  │
│                          ↓                                   │
│        ┌─────────────────┴─────────────────┐               │
│        ↓                                     ↓               │
│  ┌──────────────┐                    ┌──────────────┐      │
│  │ Rails API    │                    │ React        │      │
│  │ (Kamal)      │                    │ Frontend      │      │
│  │ Port: 3000   │                    │ (Nginx)      │      │
│  │              │                    │ Port: 80     │      │
│  └──────┬───────┘                    └──────────────┘      │
│         ↓                                                    │
│  ┌──────────────┐                                           │
│  │ PostgreSQL   │                                           │
│  │ (Managed DB) │                                           │
│  │ or           │                                           │
│  │ (Container)  │                                           │
│  └──────────────┘                                           │
└─────────────────────────────────────────────────────────────┘
```

### Prerequisites

1. **DigitalOcean Account**
2. **Droplet (VPS)**: Recommended specs:
   - **Basic**: 2GB RAM, 1 vCPU (for small apps)
   - **Recommended**: 4GB RAM, 2 vCPU (for production)
   - **High Traffic**: 8GB RAM, 4 vCPU (for scaling)
3. **Domain Name**: Pointed to your Droplet IP
4. **SSH Access**: Key-based authentication configured
5. **Docker**: Installed on Droplet (Kamal handles this)

### Step 1: DigitalOcean Setup

#### 1.1 Create Droplet

1. **Go to DigitalOcean Dashboard** → Create → Droplets
2. **Choose Image**: Ubuntu 22.04 LTS
3. **Choose Plan**: Basic (2GB RAM, 1 vCPU minimum)
4. **Add SSH Keys**: Your public SSH key
5. **Create Droplet**
6. **Note the IP Address**: e.g., `157.230.45.123`

#### 1.2 Configure DNS

Point your domain to the Droplet:

```
A Record:  api.example.com  →  157.230.45.123
A Record:  www.example.com   →  157.230.45.123
A Record:  example.com      →  157.230.45.123
```

#### 1.3 SSH Setup

```bash
# Test SSH connection
ssh root@157.230.45.123

# Or with specific key
ssh -i ~/.ssh/your_key root@157.230.45.123
```

---

### Step 2: Database Setup

#### Option A: DigitalOcean Managed Database (Recommended)

**Pros:**
- Automatic backups
- High availability
- Managed updates
- Monitoring included

**Setup:**
1. DigitalOcean Dashboard → Databases → Create Database
2. Choose PostgreSQL 16
3. Choose region (same as Droplet)
4. Note connection details:
   - Host: `your-db-do-user-123456.db.ondigitalocean.com`
   - Port: `25060`
   - Database: `defaultdb`
   - Username: `doadmin`
   - Password: (from DigitalOcean)

#### Option B: PostgreSQL Container (Kamal Accessory)

**Pros:**
- Full control
- Lower cost (no separate service)
- Good for development/small apps

**Setup via Kamal:**
```yaml
# config/deploy.yml
accessories:
  db:
    image: postgres:16
    host: 157.230.45.123  # Same server or separate
    port: "127.0.0.1:5432:5432"  # Internal only
    env:
      clear:
        POSTGRES_DB: microblog_production
      secret:
        - POSTGRES_PASSWORD
    directories:
      - data:/var/lib/postgresql/data
```

---

### Step 3: Rails API Deployment with Kamal

#### 3.1 Configure Kamal

**File: `config/deploy.yml`**
```yaml
# Name of your application
service: microblog-api

# Container image name
image: your-dockerhub-username/microblog-api

# Deploy to DigitalOcean Droplet
servers:
  web:
    - 157.230.45.123  # Your Droplet IP

# Docker registry (where to push images)
registry:
  server: docker.io
  username: your-dockerhub-username
  password:
    - KAMAL_REGISTRY_PASSWORD

# Environment variables
env:
  secret:
    - RAILS_MASTER_KEY
    - DATABASE_URL
    - SECRET_KEY_BASE
  clear:
    RAILS_ENV: production
    DATABASE_URL: postgresql://doadmin:PASSWORD@your-db-do-user-123456.db.ondigitalocean.com:25060/defaultdb?sslmode=require
    FRONTEND_URL: https://www.example.com
    # Solid services
    SOLID_QUEUE_IN_PUMA: true
    WEB_CONCURRENCY: 2
    JOB_CONCURRENCY: 2

# SSL/HTTPS configuration
proxy:
  ssl: true
  host: api.example.com
  cert_manager:
    provider: letsencrypt
    email: your-email@example.com

# Persistent volumes
volumes:
  - "microblog_storage:/rails/storage"

# SSH configuration
ssh:
  user: root
  keys:
    - ~/.ssh/your_key

# Health check
healthcheck:
  path: /up
  port: 3000
  max_attempts: 3
  interval: 10s
```

#### 3.2 Configure Secrets

**File: `.kamal/secrets`**
```bash
#!/bin/bash

# Docker Hub password
KAMAL_REGISTRY_PASSWORD=$DOCKERHUB_PASSWORD

# Rails master key (from config/master.key)
RAILS_MASTER_KEY=$(cat config/master.key)

# Generate secret key base
SECRET_KEY_BASE=$(openssl rand -hex 64)

# Database URL (for DigitalOcean Managed DB)
DATABASE_URL=postgresql://doadmin:YOUR_PASSWORD@your-db-do-user-123456.db.ondigitalocean.com:25060/defaultdb?sslmode=require
```

**Make executable:**
```bash
chmod +x .kamal/secrets
```

#### 3.3 Configure Production Environment

**File: `config/environments/production.rb`**
```ruby
Rails.application.configure do
  # Force SSL
  config.force_ssl = true
  config.assume_ssl = true

  # API mode
  config.api_only = true

  # CORS for frontend
  config.middleware.insert_before 0, Rack::Cors do
    allow do
      origins ENV['FRONTEND_URL'] || 'https://www.example.com'
      resource '*',
        headers: :any,
        methods: [:get, :post, :put, :patch, :delete, :options, :head],
        credentials: true
    end
  end

  # Database
  config.active_record.database_selector = { delay: 2.seconds }
  config.active_record.database_resolver = ActiveRecord::Middleware::DatabaseSelector::Resolver

  # Logging
  config.log_level = :info
  config.log_formatter = ::Logger::Formatter.new
end
```

#### 3.4 Deploy API

```bash
# First time setup (creates Kamal directory structure)
kamal setup

# Build and deploy
kamal deploy

# Check status
kamal app details

# View logs
kamal app logs -f

# Access Rails console
kamal app exec "bin/rails console"
```

---

### Step 4: Frontend Deployment

#### Option A: Static Files (Nginx on Same VPS)

**Build React App:**
```bash
cd frontend
npm run build
# Creates dist/ folder with static files
```

**Deploy to VPS:**
```bash
# Copy files to VPS
scp -r frontend/dist/* root@157.230.45.123:/var/www/microblog-frontend/

# Or use rsync
rsync -avz frontend/dist/ root@157.230.45.123:/var/www/microblog-frontend/
```

**Configure Nginx:**

**File: `/etc/nginx/sites-available/microblog`**
```nginx
server {
    listen 80;
    server_name www.example.com example.com;

    # Redirect HTTP to HTTPS
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name www.example.com example.com;

    # SSL certificates (Let's Encrypt)
    ssl_certificate /etc/letsencrypt/live/www.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/www.example.com/privkey.pem;

    # Frontend files
    root /var/www/microblog-frontend;
    index index.html;

    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/xml text/javascript application/x-javascript application/xml+rss application/json application/javascript;

    # Serve static files
    location / {
        try_files $uri $uri/ /index.html;
    }

    # Cache static assets
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    # Proxy API requests to Rails API
    location /api {
        proxy_pass https://api.example.com;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }
}
```

**Enable site:**
```bash
# On VPS
ln -s /etc/nginx/sites-available/microblog /etc/nginx/sites-enabled/
nginx -t  # Test configuration
systemctl reload nginx
```

#### Option B: Frontend Container (Kamal)

**File: `frontend/config/deploy.yml`**
```yaml
service: microblog-frontend

image: your-dockerhub-username/microblog-frontend

servers:
  web:
    - 157.230.45.123

registry:
  server: docker.io
  username: your-dockerhub-username
  password:
    - KAMAL_REGISTRY_PASSWORD

proxy:
  ssl: true
  host: www.example.com

volumes:
  - "frontend_storage:/usr/share/nginx/html"
```

**File: `frontend/Dockerfile`**
```dockerfile
# Build stage
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

# Production stage
FROM nginx:alpine
COPY --from=builder /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
```

**Deploy:**
```bash
cd frontend
kamal deploy
```

#### Option C: CDN (Cloudflare Pages, Vercel, Netlify)

**Pros:**
- Edge caching
- Global CDN
- Automatic SSL
- Free tier

**Setup:**
1. Connect GitHub repository
2. Build command: `npm run build`
3. Output directory: `dist`
4. Environment variable: `VITE_API_URL=https://api.example.com/api/v1`

---

### Step 5: Service Discovery and Connectivity

#### How Services Connect

**1. Frontend → API:**
```
Frontend (Browser)
  → HTTPS Request to api.example.com
  → DNS resolves to 157.230.45.123
  → Traefik (Kamal proxy) receives request
  → Routes to Rails API container (port 3000)
  → API processes request
  → Returns JSON response
```

**2. API → Database:**
```
Rails API Container
  → Reads DATABASE_URL from environment
  → Connects to PostgreSQL:
     - Managed DB: your-db-do-user-123456.db.ondigitalocean.com:25060
     - Container DB: microblog-db:5432 (via Docker network)
  → Executes queries
  → Returns data
```

**3. Internal Network (Docker):**
```
Kamal creates a Docker network for each deployment:
  - microblog-api_default (for API containers)
  - microblog-db_default (for database container)

Containers on same network can communicate via service names:
  - API → DB: postgresql://microblog-db:5432/microblog_production
```

#### Environment Variables Configuration

**API Service:**
```yaml
# config/deploy.yml
env:
  clear:
    DATABASE_URL: postgresql://doadmin:PASSWORD@your-db-do-user-123456.db.ondigitalocean.com:25060/defaultdb?sslmode=require
    FRONTEND_URL: https://www.example.com
    RAILS_ENV: production
```

**Frontend Build:**
```bash
# Build with API URL
VITE_API_URL=https://api.example.com/api/v1 npm run build
```

**Or in `frontend/.env.production`:**
```bash
VITE_API_URL=https://api.example.com/api/v1
```

---

### Step 6: Complete Deployment Process

#### 6.1 Initial Setup

```bash
# 1. Clone repository
git clone https://github.com/yourusername/microblog.git
cd microblog

# 2. Configure secrets
cp .kamal/secrets.example .kamal/secrets
# Edit .kamal/secrets with your values
chmod +x .kamal/secrets

# 3. Update deploy.yml with your:
#    - Server IP
#    - Domain names
#    - Registry credentials
#    - Database URL

# 4. Deploy API
kamal setup
kamal deploy

# 5. Build and deploy frontend
cd frontend
npm install
npm run build
# Copy to VPS or deploy via Kamal/CDN
```

#### 6.2 Continuous Deployment

**GitHub Actions Workflow:**

**File: `.github/workflows/deploy.yml`**
```yaml
name: Deploy to Production

on:
  push:
    branches: [main]

jobs:
  deploy-api:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Setup Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: 3.4.7

      - name: Install dependencies
        run: |
          gem install kamal
          bundle install

      - name: Deploy API
        env:
          KAMAL_REGISTRY_PASSWORD: ${{ secrets.DOCKERHUB_PASSWORD }}
          RAILS_MASTER_KEY: ${{ secrets.RAILS_MASTER_KEY }}
          DATABASE_URL: ${{ secrets.DATABASE_URL }}
        run: |
          kamal deploy

  deploy-frontend:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Setup Node
        uses: actions/setup-node@v3
        with:
          node-version: '20'

      - name: Build frontend
        working-directory: ./frontend
        env:
          VITE_API_URL: https://api.example.com/api/v1
        run: |
          npm ci
          npm run build

      - name: Deploy to VPS
        uses: appleboy/scp-action@master
        with:
          host: ${{ secrets.VPS_HOST }}
          username: root
          key: ${{ secrets.VPS_SSH_KEY }}
          source: "frontend/dist/*"
          target: "/var/www/microblog-frontend/"
```

---

### Step 7: Monitoring and Maintenance

#### 7.1 Health Checks

```bash
# API health
curl https://api.example.com/up

# Frontend
curl https://www.example.com

# Database (from API container)
kamal app exec "bin/rails db:version"
```

#### 7.2 Logs

```bash
# API logs
kamal app logs -f

# Nginx logs (frontend)
ssh root@157.230.45.123 "tail -f /var/log/nginx/access.log"
```

#### 7.3 Database Migrations

```bash
# Run migrations
kamal app exec "bin/rails db:migrate"

# Or with rollback
kamal app exec "bin/rails db:rollback"
```

#### 7.4 Updates and Rollbacks

```bash
# Deploy new version
kamal deploy

# Rollback to previous version
kamal rollback

# Check deployed versions
kamal app versions
```

---

### Step 8: Networking Details

#### Port Mapping

```
External (Internet)          Internal (VPS)
─────────────────────────────────────────────
:80  → Traefik (Kamal)  →  :3000 (Rails API)
:443 → Traefik (Kamal)  →  :3000 (Rails API)
      → Nginx           →  :80 (Frontend files)
```

#### Docker Networks

Kamal creates isolated Docker networks:

```bash
# View networks
ssh root@157.230.45.123 "docker network ls"

# View containers
ssh root@157.230.45.123 "docker ps"
```

#### Firewall Configuration

```bash
# On VPS
ufw allow 22/tcp   # SSH
ufw allow 80/tcp   # HTTP
ufw allow 443/tcp  # HTTPS
ufw enable
```

---

### Step 9: SSL/TLS Setup

#### Automatic (Let's Encrypt via Kamal)

Kamal handles SSL automatically:

```yaml
# config/deploy.yml
proxy:
  ssl: true
  host: api.example.com
  cert_manager:
    provider: letsencrypt
    email: your-email@example.com
```

#### Manual (Certbot)

```bash
# Install Certbot
apt-get install certbot python3-certbot-nginx

# Get certificate
certbot --nginx -d www.example.com -d example.com

# Auto-renewal (already configured)
certbot renew --dry-run
```

---

### Step 10: Scaling

#### Horizontal Scaling (Multiple Droplets)

```yaml
# config/deploy.yml
servers:
  web:
    - 157.230.45.123  # Droplet 1
    - 157.230.45.124  # Droplet 2
    - 157.230.45.125  # Droplet 3
```

Kamal automatically:
- Load balances across servers
- Deploys to all servers
- Handles health checks

#### Database Read Replicas

```yaml
# config/deploy.yml
accessories:
  db:
    # Primary
    host: 157.230.45.123
  db_replica:
    image: postgres:16
    host: 157.230.45.124  # Separate server
    # Rails automatically uses for reads
```

---

### Troubleshooting

#### Issue: API can't connect to database

**Solution:**
```bash
# Test connection
kamal app exec "bin/rails db:version"

# Check DATABASE_URL
kamal app exec "printenv DATABASE_URL"

# Verify database is accessible
kamal app exec "nc -zv your-db-host 25060"
```

#### Issue: Frontend can't reach API (CORS)

**Solution:**
```ruby
# config/environments/production.rb
config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins ENV['FRONTEND_URL'] || 'https://www.example.com'
    resource '*',
      headers: :any,
      methods: [:get, :post, :put, :patch, :delete, :options, :head],
      credentials: true
  end
end
```

#### Issue: SSL certificate not working

**Solution:**
```bash
# Check certificate
kamal app details

# Regenerate certificate
kamal app exec "certbot renew --force-renewal"
```

---

### Cost Estimation (DigitalOcean)

**Monthly Costs:**

- **Droplet (4GB RAM, 2 vCPU)**: ~$24/month
- **Managed PostgreSQL (1GB)**: ~$15/month
- **Domain**: ~$12/year (~$1/month)
- **Total**: ~$40/month

**Scaling:**
- **2 Droplets**: ~$48/month
- **3 Droplets**: ~$72/month
- **Load Balancer**: +$12/month (optional)

---

## References

- [Rails API Mode Guide](https://guides.rubyonrails.org/api_app.html)
- [JWT Best Practices](https://tools.ietf.org/html/rfc8725)
- [React Documentation](https://react.dev/)
- [Docker Compose Documentation](https://docs.docker.com/compose/)
- [Traefik Documentation](https://doc.traefik.io/traefik/)
- [Kamal Documentation](https://kamal-deploy.org/)
- [DigitalOcean Documentation](https://docs.digitalocean.com/)

---

**Document Version:** 1.0
**Last Updated:** 2024
**Author:** Development Team
**Status:** Planning Phase

