# Implementation Plan: Authentication & Admin Dashboard

This document outlines the detailed implementation plan for two major features:
1. **Signup/Signin** - Simple but secure authentication
2. **Admin Dashboard** - Metrics, database monitoring, Mission Control access, and moderation tools

---

## Phase 1: Authentication (Signup/Signin)

### Overview
Build simple, secure authentication on top of existing infrastructure. Leverage `has_secure_password` already in place.

### Goals
- ✅ Simple user experience (username + password)
- ✅ Secure (password hashing, session management)
- ✅ Clean, minimal UI
- ✅ No unnecessary complexity (email verification can come later)

---

### 1.1 Database Changes

**Migration: Add admin flag to users**
```ruby
# db/migrate/YYYYMMDDHHMMSS_add_admin_to_users.rb
class AddAdminToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :admin, :boolean, default: false, null: false
    add_index :users, :admin
  end
end
```

**Rationale:**
- Simple boolean flag for admin status
- Indexed for admin queries
- Default false (security: no user is admin by default)

---

### 1.2 Sessions Controller

**File: `app/controllers/sessions_controller.rb`**

```ruby
class SessionsController < ApplicationController
  # Skip authentication checks for login/signup pages
  skip_before_action :require_login, only: [:new, :create]
  
  def new
    # Login form
    redirect_to root_path if logged_in?
  end

  def create
    user = User.find_by(username: params[:username])
    
    if user&.authenticate(params[:password])
      session[:user_id] = user.id
      redirect_to root_path, notice: "Welcome back, #{user.username}!"
    else
      flash.now[:alert] = "Invalid username or password"
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    session[:user_id] = nil
    redirect_to root_path, notice: "You have been logged out"
  end
end
```

**Security considerations:**
- ✅ Generic error message (doesn't reveal if username exists)
- ✅ Uses `authenticate` method from `has_secure_password`
- ✅ Session-based authentication (Rails default, secure)
- ✅ Clear session on logout

---

### 1.3 Update Users Controller

**Add signup actions to `app/controllers/users_controller.rb`:**

```ruby
class UsersController < ApplicationController
  skip_before_action :require_login, only: [:new, :create]
  
  # Add to existing actions:
  def new
    @user = User.new
    redirect_to root_path if logged_in?
  end

  def create
    @user = User.new(user_params)
    
    if @user.save
      session[:user_id] = @user.id
      redirect_to root_path, notice: "Welcome to Microblog, #{@user.username}!"
    else
      flash.now[:alert] = @user.errors.full_messages.join(", ")
      render :new, status: :unprocessable_entity
    end
  end

  # ... existing actions ...

  private

  def user_params
    params.require(:user).permit(:username, :description, :password, :password_confirmation)
  end
end
```

**Signup form fields:**
- Username (required, unique, max 50 chars)
- Password (required, min 6 chars)
- Password confirmation (required)
- Description (optional, max 120 chars)

---

### 1.4 Update Application Controller

**File: `app/controllers/application_controller.rb`**

```ruby
class ApplicationController < ActionController::Base
  # ... existing code ...

  # Remove dev_login method (no longer needed)
  # def dev_login
  #   session[:user_id] = params[:user_id]
  #   redirect_to root_path, notice: "Logged in as user #{params[:user_id]} (dev mode)"
  # end

  # Add admin helper
  def admin?
    current_user&.admin?
  end
  helper_method :admin?

  # Add require_admin before_action
  def require_admin
    unless admin?
      redirect_to root_path, alert: "Access denied. Admin privileges required."
    end
  end
end
```

---

### 1.5 Routes

**File: `config/routes.rb`**

```ruby
Rails.application.routes.draw do
  # ... existing routes ...

  # Authentication routes
  get "/login", to: "sessions#new", as: "login"
  post "/login", to: "sessions#create"
  delete "/logout", to: "sessions#destroy", as: "logout"
  
  # Signup routes (add to users resource)
  get "/signup", to: "users#new", as: "signup"
  post "/signup", to: "users#create"
  
  # Remove or comment out dev login route
  # get "/dev/login/:user_id", to: "application#dev_login", as: "dev_login"

  # ... rest of routes ...
end
```

---

### 1.6 Views

**File: `app/views/sessions/new.html.erb`**
```erb
<div class="max-w-md mx-auto mt-8">
  <h1 class="text-2xl font-bold mb-6">Login</h1>
  
  <%= form_with url: login_path, local: true do |f| %>
    <div class="mb-4">
      <%= f.label :username, class: "block text-sm font-medium mb-2" %>
      <%= f.text_field :username, 
          autofocus: true,
          required: true,
          class: "w-full px-3 py-2 border rounded-md" %>
    </div>

    <div class="mb-4">
      <%= f.label :password, class: "block text-sm font-medium mb-2" %>
      <%= f.password_field :password, 
          required: true,
          class: "w-full px-3 py-2 border rounded-md" %>
    </div>

    <%= f.submit "Login", class: "w-full bg-blue-600 text-white py-2 px-4 rounded-md hover:bg-blue-700" %>
  <% end %>

  <p class="mt-4 text-center text-sm text-gray-600">
    Don't have an account? <%= link_to "Sign up", signup_path, class: "text-blue-600 hover:underline" %>
  </p>
</div>
```

**File: `app/views/users/new.html.erb`**
```erb
<div class="max-w-md mx-auto mt-8">
  <h1 class="text-2xl font-bold mb-6">Sign Up</h1>
  
  <%= form_with model: @user, url: signup_path, local: true do |f| %>
    <% if @user.errors.any? %>
      <div class="mb-4 p-3 bg-red-100 border border-red-400 text-red-700 rounded">
        <ul class="list-disc list-inside">
          <% @user.errors.full_messages.each do |message| %>
            <li><%= message %></li>
          <% end %>
        </ul>
      </div>
    <% end %>

    <div class="mb-4">
      <%= f.label :username, class: "block text-sm font-medium mb-2" %>
      <%= f.text_field :username, 
          autofocus: true,
          required: true,
          maxlength: 50,
          class: "w-full px-3 py-2 border rounded-md" %>
      <p class="mt-1 text-xs text-gray-500">Maximum 50 characters</p>
    </div>

    <div class="mb-4">
      <%= f.label :description, class: "block text-sm font-medium mb-2" %>
      <%= f.text_area :description, 
          rows: 3,
          maxlength: 120,
          placeholder: "Tell us about yourself (optional)",
          class: "w-full px-3 py-2 border rounded-md" %>
      <p class="mt-1 text-xs text-gray-500">Maximum 120 characters</p>
    </div>

    <div class="mb-4">
      <%= f.label :password, class: "block text-sm font-medium mb-2" %>
      <%= f.password_field :password, 
          required: true,
          minlength: 6,
          class: "w-full px-3 py-2 border rounded-md" %>
      <p class="mt-1 text-xs text-gray-500">Minimum 6 characters</p>
    </div>

    <div class="mb-4">
      <%= f.label :password_confirmation, "Confirm Password", class: "block text-sm font-medium mb-2" %>
      <%= f.password_field :password_confirmation, 
          required: true,
          class: "w-full px-3 py-2 border rounded-md" %>
    </div>

    <%= f.submit "Sign Up", class: "w-full bg-blue-600 text-white py-2 px-4 rounded-md hover:bg-blue-700" %>
  <% end %>

  <p class="mt-4 text-center text-sm text-gray-600">
    Already have an account? <%= link_to "Login", login_path, class: "text-blue-600 hover:underline" %>
  </p>
</div>
```

---

### 1.7 Update Navigation

**File: `app/views/layouts/application.html.erb`**

Update navigation to show login/logout based on session:

```erb
<nav>
  <!-- ... existing navigation ... -->
  
  <div class="flex items-center gap-4">
    <% if logged_in? %>
      <span class="text-sm text-gray-600">Logged in as <%= current_user.username %></span>
      <%= link_to "Settings", edit_user_path(current_user), class: "..." %>
      <%= button_to "Logout", logout_path, method: :delete, class: "..." %>
    <% else %>
      <%= link_to "Login", login_path, class: "..." %>
      <%= link_to "Sign Up", signup_path, class: "..." %>
    <% end %>
  </div>
</nav>
```

---

### 1.8 Update User Model

**File: `app/models/user.rb`**

```ruby
class User < ApplicationRecord
  has_secure_password

  # ... existing code ...

  # Add admin scope
  scope :admins, -> { where(admin: true) }
  
  def admin?
    admin
  end
end
```

---

### 1.9 Security Enhancements

**Rate limiting for auth endpoints:**

Add to `config/initializers/rack_attack.rb`:

```ruby
# Throttle login attempts
throttle("logins/ip", limit: 5, period: 20.minutes) do |req|
  if req.path == "/login" && req.post?
    req.ip
  end
end

# Throttle signup attempts
throttle("signups/ip", limit: 3, period: 1.hour) do |req|
  if req.path == "/signup" && req.post?
    req.ip
  end
end
```

**Password requirements:**
- Already enforced: minimum 6 characters (via User model validation)
- Consider: Add password strength validation (optional, can be added later)

---

### 1.10 Testing

**Spec files to create:**

1. `spec/controllers/sessions_controller_spec.rb`
   - Test login with valid credentials
   - Test login with invalid credentials
   - Test logout
   - Test redirects when already logged in

2. `spec/controllers/users_controller_spec.rb` (update existing)
   - Test signup with valid data
   - Test signup with invalid data
   - Test signup requires unique username

3. `spec/models/user_spec.rb` (update existing)
   - Test admin? method
   - Test admin scope

---

## Phase 2: Admin Dashboard

### Overview
Comprehensive admin dashboard with metrics, database monitoring, Mission Control access, and moderation tools.

### Goals
- ✅ Real-time application metrics
- ✅ Database performance monitoring (pg_stat_statements)
- ✅ Access to Mission Control (Solid Queue jobs)
- ✅ Post moderation tools
- ✅ User management (banning, etc.)
- ✅ Clean, organized dashboard

---

### 2.1 Admin Controller

**File: `app/controllers/admin_controller.rb`**

```ruby
class AdminController < ApplicationController
  before_action :require_login
  before_action :require_admin

  def index
    # Dashboard overview
    @stats = {
      users: User.count,
      posts: Post.count,
      follows: Follow.count,
      active_users_24h: User.where("updated_at > ?", 24.hours.ago).count,
      posts_24h: Post.where("created_at > ?", 24.hours.ago).count,
    }
  end

  def metrics
    # Application metrics
    @puma_stats = fetch_puma_stats
    @cache_stats = fetch_cache_stats
    @queue_stats = fetch_queue_stats
  end

  def database
    # Database performance metrics
    @slow_queries = fetch_slow_queries
    @database_stats = fetch_database_stats
    @connection_stats = fetch_connection_stats
  end

  def moderation
    # Post moderation queue
    @reported_posts = [] # Placeholder for future reporting feature
    @recent_posts = Post.includes(:author).order(created_at: :desc).limit(50)
  end

  def users
    # User management
    @users = User.order(created_at: :desc).page(params[:page]).per(50)
    @search = params[:search]
    @users = @users.where("username ILIKE ?", "%#{@search}%") if @search.present?
  end

  private

  def fetch_puma_stats
    # Get Puma statistics
    JSON.parse(Puma.stats) rescue {}
  end

  def fetch_cache_stats
    # Solid Cache statistics
    {
      entries: SolidCache::Entry.count,
      size_mb: (SolidCache::Entry.sum(:byte_size) / 1_000_000.0).round(2),
      hit_rate: calculate_cache_hit_rate # Placeholder
    }
  end

  def fetch_queue_stats
    # Solid Queue statistics
    {
      pending: SolidQueue::Job.where(finished_at: nil).count,
      failed: SolidQueue::FailedExecution.count,
      completed_24h: SolidQueue::Job.where("finished_at > ?", 24.hours.ago).count,
    }
  end

  def fetch_slow_queries
    # pg_stat_statements slow queries
    return [] unless pg_stat_statements_enabled?

    ActiveRecord::Base.connection.execute(<<-SQL).to_a
      SELECT 
        query,
        calls,
        total_exec_time,
        mean_exec_time,
        max_exec_time,
        (total_exec_time / 1000.0) as total_seconds
      FROM pg_stat_statements
      WHERE mean_exec_time > 100  -- Queries slower than 100ms on average
      ORDER BY mean_exec_time DESC
      LIMIT 20
    SQL
  rescue
    []
  end

  def fetch_database_stats
    # General database statistics
    conn = ActiveRecord::Base.connection
    
    {
      database_size: conn.execute("SELECT pg_size_pretty(pg_database_size(current_database()));").first&.values&.first,
      table_sizes: fetch_table_sizes,
      index_sizes: fetch_index_sizes,
    }
  end

  def fetch_connection_stats
    # Connection pool statistics
    {
      active_connections: ActiveRecord::Base.connection_pool.stat[:size] - ActiveRecord::Base.connection_pool.stat[:available],
      available_connections: ActiveRecord::Base.connection_pool.stat[:available],
      total_connections: ActiveRecord::Base.connection_pool.stat[:size],
      waiting: ActiveRecord::Base.connection_pool.stat[:waiting],
    }
  end

  def fetch_table_sizes
    ActiveRecord::Base.connection.execute(<<-SQL).to_a
      SELECT 
        schemaname,
        tablename,
        pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
      FROM pg_tables
      WHERE schemaname = 'public'
      ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC
      LIMIT 10
    SQL
  rescue
    []
  end

  def fetch_index_sizes
    ActiveRecord::Base.connection.execute(<<-SQL).to_a
      SELECT 
        indexname,
        pg_size_pretty(pg_relation_size(indexname::regclass)) AS size
      FROM pg_indexes
      WHERE schemaname = 'public'
      ORDER BY pg_relation_size(indexname::regclass) DESC
      LIMIT 10
    SQL
  rescue
    []
  end

  def calculate_cache_hit_rate
    # Placeholder - would need cache hit/miss tracking
    "N/A"
  end

  def pg_stat_statements_enabled?
    ActiveRecord::Base.connection.execute(
      "SELECT * FROM pg_extension WHERE extname = 'pg_stat_statements';"
    ).any?
  rescue
    false
  end
end
```

---

### 2.2 Admin Routes

**File: `config/routes.rb`**

```ruby
Rails.application.routes.draw do
  # ... existing routes ...

  # Admin routes (require admin authentication)
  namespace :admin do
    root "admin#index"
    get "metrics", to: "admin#metrics"
    get "database", to: "admin#database"
    get "moderation", to: "admin#moderation"
    get "users", to: "admin#users"
    
    # User management actions
    patch "users/:id/ban", to: "admin#ban_user", as: "ban_user"
    patch "users/:id/unban", to: "admin#unban_user", as: "unban_user"
    
    # Post moderation actions
    patch "posts/:id/delete", to: "admin#delete_post", as: "delete_post"
    patch "posts/:id/hide", to: "admin#hide_post", as: "hide_post"
  end
end
```

---

### 2.3 Database Schema Updates

**Migration: Add banned flag and moderation fields**

```ruby
# db/migrate/YYYYMMDDHHMMSS_add_moderation_to_users_and_posts.rb
class AddModerationToUsersAndPosts < ActiveRecord::Migration[8.1]
  def change
    # User moderation
    add_column :users, :banned, :boolean, default: false, null: false
    add_column :users, :banned_at, :datetime
    add_column :users, :banned_by_id, :bigint
    add_column :users, :ban_reason, :text
    add_index :users, :banned

    # Post moderation
    add_column :posts, :hidden, :boolean, default: false, null: false
    add_column :posts, :hidden_at, :datetime
    add_column :posts, :hidden_by_id, :bigint
    add_column :posts, :hide_reason, :text
    add_index :posts, :hidden

    # Foreign keys
    add_foreign_key :users, :users, column: :banned_by_id
    add_foreign_key :posts, :users, column: :hidden_by_id
  end
end
```

---

### 2.4 Update Models

**File: `app/models/user.rb`**

```ruby
class User < ApplicationRecord
  # ... existing code ...

  # Admin and moderation
  scope :admins, -> { where(admin: true) }
  scope :banned, -> { where(banned: true) }
  scope :active, -> { where(banned: false) }

  belongs_to :banned_by, class_name: "User", optional: true

  def admin?
    admin
  end

  def banned?
    banned
  end

  def ban!(admin_user, reason = nil)
    update!(
      banned: true,
      banned_at: Time.current,
      banned_by: admin_user,
      ban_reason: reason
    )
  end

  def unban!
    update!(
      banned: false,
      banned_at: nil,
      banned_by: nil,
      ban_reason: nil
    )
  end
end
```

**File: `app/models/post.rb`**

```ruby
class Post < ApplicationRecord
  # ... existing code ...

  # Moderation
  belongs_to :hidden_by, class_name: "User", optional: true

  scope :visible, -> { where(hidden: false) }
  scope :hidden, -> { where(hidden: true) }

  def hidden?
    hidden
  end

  def hide!(admin_user, reason = nil)
    update!(
      hidden: true,
      hidden_at: Time.current,
      hidden_by: admin_user,
      hide_reason: reason
    )
  end

  def unhide!
    update!(
      hidden: false,
      hidden_at: nil,
      hidden_by: nil,
      hide_reason: nil
    )
  end
end
```

---

### 2.5 Update Controllers to Respect Bans

**File: `app/controllers/application_controller.rb`**

```ruby
class ApplicationController < ActionController::Base
  # ... existing code ...

  def current_user
    user = User.find_by(id: session[:user_id]) if session[:user_id]
    # Don't allow banned users to access the site
    if user&.banned?
      session[:user_id] = nil
      redirect_to root_path, alert: "Your account has been banned. Reason: #{user.ban_reason}"
      return nil
    end
    @current_user ||= user
  end
end
```

**File: `app/controllers/posts_controller.rb`**

Update to filter hidden posts:

```ruby
class PostsController < ApplicationController
  # ... existing code ...

  def index
    # ... existing code ...
    # Filter out hidden posts for non-admins
    posts_relation = posts_relation.visible unless admin?
    # ... rest of code ...
  end

  def show
    @post = Post.visible.find(params[:id])
    # ... rest of code ...
  end
end
```

---

### 2.6 Admin Views

**File: `app/views/admin/index.html.erb`**
```erb
<div class="max-w-7xl mx-auto px-4 py-8">
  <h1 class="text-3xl font-bold mb-8">Admin Dashboard</h1>

  <!-- Stats Cards -->
  <div class="grid grid-cols-1 md:grid-cols-3 gap-6 mb-8">
    <div class="bg-white p-6 rounded-lg shadow">
      <h3 class="text-lg font-semibold mb-2">Total Users</h3>
      <p class="text-3xl font-bold"><%= @stats[:users] %></p>
      <p class="text-sm text-gray-600 mt-2">Active in 24h: <%= @stats[:active_users_24h] %></p>
    </div>

    <div class="bg-white p-6 rounded-lg shadow">
      <h3 class="text-lg font-semibold mb-2">Total Posts</h3>
      <p class="text-3xl font-bold"><%= @stats[:posts] %></p>
      <p class="text-sm text-gray-600 mt-2">Last 24h: <%= @stats[:posts_24h] %></p>
    </div>

    <div class="bg-white p-6 rounded-lg shadow">
      <h3 class="text-lg font-semibold mb-2">Follows</h3>
      <p class="text-3xl font-bold"><%= @stats[:follows] %></p>
    </div>
  </div>

  <!-- Quick Links -->
  <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
    <%= link_to "Metrics", admin_metrics_path, class: "..." %>
    <%= link_to "Database", admin_database_path, class: "..." %>
    <%= link_to "Moderation", admin_moderation_path, class: "..." %>
    <%= link_to "Users", admin_users_path, class: "..." %>
    <%= link_to "Mission Control", "/jobs", class: "...", target: "_blank" %>
  </div>
</div>
```

**File: `app/views/admin/database.html.erb`**
```erb
<div class="max-w-7xl mx-auto px-4 py-8">
  <h1 class="text-3xl font-bold mb-8">Database Performance</h1>

  <!-- Slow Queries -->
  <div class="mb-8">
    <h2 class="text-2xl font-semibold mb-4">Slow Queries</h2>
    <% if @slow_queries.any? %>
      <div class="overflow-x-auto">
        <table class="min-w-full bg-white rounded-lg shadow">
          <thead>
            <tr>
              <th>Query</th>
              <th>Calls</th>
              <th>Mean Time (ms)</th>
              <th>Max Time (ms)</th>
              <th>Total Time (s)</th>
            </tr>
          </thead>
          <tbody>
            <% @slow_queries.each do |query| %>
              <tr>
                <td class="font-mono text-xs"><%= truncate(query['query'], length: 100) %></td>
                <td><%= query['calls'] %></td>
                <td><%= query['mean_exec_time'].round(2) %></td>
                <td><%= query['max_exec_time'].round(2) %></td>
                <td><%= query['total_seconds'].round(2) %></td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
    <% else %>
      <p class="text-gray-600">No slow queries found or pg_stat_statements not enabled.</p>
    <% end %>
  </div>

  <!-- Database Stats -->
  <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
    <div>
      <h3 class="text-xl font-semibold mb-4">Database Size</h3>
      <p class="text-lg"><%= @database_stats[:database_size] %></p>
    </div>

    <div>
      <h3 class="text-xl font-semibold mb-4">Connection Pool</h3>
      <ul>
        <li>Active: <%= @connection_stats[:active_connections] %></li>
        <li>Available: <%= @connection_stats[:available_connections] %></li>
        <li>Total: <%= @connection_stats[:total_connections] %></li>
        <li>Waiting: <%= @connection_stats[:waiting] %></li>
      </ul>
    </div>
  </div>
</div>
```

**File: `app/views/admin/moderation.html.erb`**
```erb
<div class="max-w-7xl mx-auto px-4 py-8">
  <h1 class="text-3xl font-bold mb-8">Post Moderation</h1>

  <!-- Recent Posts -->
  <div>
    <h2 class="text-2xl font-semibold mb-4">Recent Posts</h2>
    <div class="space-y-4">
      <% @recent_posts.each do |post| %>
        <div class="bg-white p-4 rounded-lg shadow">
          <div class="flex justify-between items-start">
            <div class="flex-1">
              <p class="text-sm text-gray-600">
                By <%= link_to post.author.username, user_path(post.author) %> 
                <%= time_ago_in_words(post.created_at) %> ago
              </p>
              <p class="mt-2"><%= post.content %></p>
            </div>
            <div class="flex gap-2">
              <% unless post.hidden? %>
                <%= button_to "Hide", admin_hide_post_path(post), 
                    method: :patch, 
                    class: "..." %>
              <% else %>
                <%= button_to "Unhide", admin_unhide_post_path(post), 
                    method: :patch, 
                    class: "..." %>
                <span class="text-sm text-red-600">Hidden</span>
              <% end %>
              <%= button_to "Delete", admin_delete_post_path(post), 
                  method: :patch, 
                  confirm: "Are you sure?",
                  class: "..." %>
            </div>
          </div>
        </div>
      <% end %>
    </div>
  </div>
</div>
```

**File: `app/views/admin/users.html.erb`**
```erb
<div class="max-w-7xl mx-auto px-4 py-8">
  <h1 class="text-3xl font-bold mb-8">User Management</h1>

  <!-- Search -->
  <%= form_with url: admin_users_path, method: :get, local: true, class: "mb-6" do |f| %>
    <%= f.text_field :search, 
        placeholder: "Search by username...", 
        value: params[:search],
        class: "..." %>
    <%= f.submit "Search", class: "..." %>
  <% end %>

  <!-- Users Table -->
  <div class="overflow-x-auto">
    <table class="min-w-full bg-white rounded-lg shadow">
      <thead>
        <tr>
          <th>Username</th>
          <th>Posts</th>
          <th>Followers</th>
          <th>Created</th>
          <th>Status</th>
          <th>Actions</th>
        </tr>
      </thead>
      <tbody>
        <% @users.each do |user| %>
          <tr>
            <td><%= link_to user.username, user_path(user) %></td>
            <td><%= user.posts_count %></td>
            <td><%= user.followers_count %></td>
            <td><%= user.created_at.strftime("%Y-%m-%d") %></td>
            <td>
              <% if user.banned? %>
                <span class="text-red-600">Banned</span>
              <% elsif user.admin? %>
                <span class="text-blue-600">Admin</span>
              <% else %>
                <span class="text-green-600">Active</span>
              <% end %>
            </td>
            <td>
              <% if user.banned? %>
                <%= button_to "Unban", admin_unban_user_path(user), 
                    method: :patch, 
                    class: "..." %>
              <% else %>
                <%= button_to "Ban", admin_ban_user_path(user), 
                    method: :patch, 
                    confirm: "Are you sure?",
                    class: "..." %>
              <% end %>
            </td>
          </tr>
        <% end %>
      </tbody>
    </table>
  </div>

  <!-- Pagination -->
  <%= paginate @users if defined?(Kaminari) %>
</div>
```

---

### 2.7 Update Admin Controller with Actions

**File: `app/controllers/admin_controller.rb`** (add actions)

```ruby
class AdminController < ApplicationController
  # ... existing code ...

  def ban_user
    user = User.find(params[:id])
    user.ban!(current_user, params[:reason])
    redirect_to admin_users_path, notice: "User #{user.username} has been banned."
  end

  def unban_user
    user = User.find(params[:id])
    user.unban!
    redirect_to admin_users_path, notice: "User #{user.username} has been unbanned."
  end

  def delete_post
    post = Post.find(params[:id])
    post.destroy
    redirect_to admin_moderation_path, notice: "Post deleted."
  end

  def hide_post
    post = Post.find(params[:id])
    if post.hidden?
      post.unhide!
      redirect_to admin_moderation_path, notice: "Post unhidden."
    else
      post.hide!(current_user, params[:reason])
      redirect_to admin_moderation_path, notice: "Post hidden."
    end
  end
end
```

---

### 2.8 Update Navigation

**File: `app/views/layouts/application.html.erb`**

Add admin link for admin users:

```erb
<% if logged_in? && admin? %>
  <%= link_to "Admin", admin_root_path, class: "..." %>
<% end %>
```

---

### 2.9 Create First Admin User

**Script: `script/create_admin.rb`**

```ruby
# Usage: rails runner script/create_admin.rb username password
username = ARGV[0] || "admin"
password = ARGV[1] || "admin123"

user = User.find_or_create_by(username: username) do |u|
  u.password = password
  u.password_confirmation = password
  u.description = "System Administrator"
end

user.update(admin: true)
puts "Admin user created: #{user.username}"
puts "Password: #{password}"
```

---

## Implementation Order

### Phase 1: Authentication (Week 1)

**Day 1-2: Database & Models**
- [ ] Add admin flag migration
- [ ] Update User model with admin methods
- [ ] Test admin functionality

**Day 3-4: Sessions Controller**
- [ ] Create SessionsController
- [ ] Add login/logout routes
- [ ] Create login view
- [ ] Test login functionality

**Day 5: Signup**
- [ ] Add signup to UsersController
- [ ] Create signup view
- [ ] Update routes
- [ ] Test signup functionality

**Day 6: Integration**
- [ ] Update navigation with login/logout
- [ ] Remove dev login route
- [ ] Update all controllers to use proper authentication
- [ ] Test end-to-end

**Day 7: Security & Polish**
- [ ] Add rate limiting for auth endpoints
- [ ] Test security features
- [ ] Update documentation

---

### Phase 2: Admin Dashboard (Week 2)

**Day 1-2: Database Schema**
- [ ] Add moderation fields migration
- [ ] Update User and Post models
- [ ] Add scopes and methods
- [ ] Test moderation functionality

**Day 3-4: Admin Controller & Routes**
- [ ] Create AdminController
- [ ] Add admin routes
- [ ] Implement dashboard index
- [ ] Implement metrics action
- [ ] Test basic admin access

**Day 5: Database Monitoring**
- [ ] Implement database action
- [ ] Add pg_stat_statements queries
- [ ] Create database view
- [ ] Test database monitoring

**Day 6: Moderation Tools**
- [ ] Implement moderation action
- [ ] Add ban/unban functionality
- [ ] Add post hide/delete functionality
- [ ] Create moderation views
- [ ] Test moderation features

**Day 7: User Management**
- [ ] Implement users action
- [ ] Add search functionality
- [ ] Create users view
- [ ] Test user management

**Day 8: Integration & Polish**
- [ ] Add admin navigation links
- [ ] Create first admin user script
- [ ] Test all admin features
- [ ] Update documentation
- [ ] Add pagination if needed

---

## Security Considerations

### Authentication
- ✅ Password hashing (bcrypt via has_secure_password)
- ✅ Session-based authentication (secure by default in Rails)
- ✅ Rate limiting on auth endpoints
- ✅ Generic error messages (don't reveal if username exists)
- ✅ Password minimum length (6 characters)

### Admin Dashboard
- ✅ Admin-only access (require_admin before_action)
- ✅ Audit trail (banned_by, hidden_by fields)
- ✅ Soft deletes for posts (hidden flag, not deleted)
- ✅ Ban reasons stored for accountability

---

## Testing Strategy

### Unit Tests
- User model: admin?, ban!, unban!
- Post model: hide!, unhide!
- SessionsController: login, logout
- UsersController: signup

### Integration Tests
- Login flow
- Signup flow
- Admin dashboard access
- Ban/unban functionality
- Post moderation

### Security Tests
- Non-admin cannot access admin routes
- Rate limiting works on auth endpoints
- Banned users cannot login
- Hidden posts not visible to non-admins

---

## Dependencies

### Gems (may need to add)
- `kaminari` or `pagy` - For pagination in admin users list (optional, can use limit/offset)

### Existing
- ✅ `has_secure_password` - Already in User model
- ✅ `pg_stat_statements` - Already enabled
- ✅ `mission_control-jobs` - Already mounted
- ✅ Session management - Already in place

---

## Future Enhancements (Out of Scope)

- Email verification
- Password reset
- Two-factor authentication
- Post reporting system
- Automated moderation (AI/content filtering)
- Admin activity logs
- User roles (beyond admin boolean)
- Email notifications

---

## Summary

This plan provides:
1. **Simple, secure authentication** - Login/signup with minimal complexity
2. **Comprehensive admin dashboard** - Metrics, database monitoring, Mission Control access, moderation tools
3. **Incremental implementation** - Can be built in phases
4. **Security-focused** - Rate limiting, proper access control, audit trails
5. **Scalable foundation** - Can extend with more features later

Total estimated time: **2 weeks** (1 week per phase)

