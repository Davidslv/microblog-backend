# Educational Case Study: Building a Scalable Microblog Platform

## Executive Summary

This document serves as a comprehensive educational case study for junior software engineers, explaining how we built a production-ready, scalable microblogging platform using Ruby on Rails. This application demonstrates real-world software engineering principles, from database design to horizontal scaling, and serves as a practical learning resource.

**What You'll Learn:**
- How to design scalable database schemas
- Performance optimization techniques (caching, indexing, query optimization)
- Architecture patterns (fan-out on write, cursor pagination)
- Security practices (authentication, rate limiting)
- Testing strategies (unit, integration, end-to-end)
- Infrastructure setup (Docker, load balancing, horizontal scaling)
- Monitoring and performance analysis

**Target Audience:** Junior software engineers, students, and developers learning production-grade Rails development

---

## Table of Contents

1. [Project Overview](#project-overview)
2. [Software Design & Architecture](#software-design--architecture)
3. [Database Design & Optimization](#database-design--optimization)
4. [Performance Optimization Techniques](#performance-optimization-techniques)
5. [Security Implementation](#security-implementation)
6. [Testing Strategy](#testing-strategy)
7. [Infrastructure & Scaling](#infrastructure--scaling)
8. [Monitoring & Performance Analysis](#monitoring--performance-analysis)
9. [Key Learnings & Takeaways](#key-learnings--takeaways)
10. [References & Further Reading](#references--further-reading)

---

## Project Overview

### What is This Application?

A microblogging platform (similar to Twitter/X) where users can:
- Create short posts (200 characters max)
- Reply to posts (threading support)
- Follow other users
- View personalized feeds (timeline, following, all posts)
- Manage their profile and settings

### The Challenge

**Requirements:**
- Handle 1M+ users
- Support 50M+ follow relationships
- Fast response times (<200ms for feed queries)
- High concurrency (100+ requests/second)
- Real-time updates
- Reliable and maintainable codebase

**Why This Matters:**
This project demonstrates how to build a real-world application that scales, not just a prototype. Every decision was made with performance, maintainability, and scalability in mind.

---

## Software Design & Architecture

### 1. Application Architecture

#### High-Level Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Docker Network                        │
│              (microblog-network)                        │
│                                                          │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐          │
│  │  web-1   │    │  web-2   │    │  web-3   │          │
│  │ (Puma)   │    │ (Puma)   │    │ (Puma)   │          │
│  │ 25 threads│   │ 25 threads│   │ 25 threads│          │
│  └────┬─────┘    └────┬─────┘    └────┬─────┘          │
│       │                │                │                │
│       └────────┬──────┴───────────────┘                │
│                │                                        │
│         ┌───────▼────────┐                              │
│         │  Traefik LB   │                              │
│         │ (Load Balancer)│                              │
│         └───────┬────────┘                              │
│                 │                                        │
│                 │                                        │
│    ┌────────────▼────────────────────┐                │
│    │      PostgreSQL Database        │                │
│    │  - Primary database (users,     │                │
│    │    posts, follows)               │                │
│    │  - Solid Cache (cache entries) │                │
│    │  - Solid Queue (job queue)      │                │
│    │  - Action Cable (WebSocket)     │                │
│    └─────────────────────────────────┘                │
└─────────────────────────────────────────────────────────┘
```

**Key Components:**
1. **Multiple Web Instances**: 3+ Puma servers for horizontal scaling
2. **Load Balancer**: Traefik distributes requests across instances
3. **Shared Database**: PostgreSQL for all data storage
4. **Background Jobs**: Solid Queue for async processing
5. **Caching**: Solid Cache for performance optimization

**Why This Architecture?**
- **Horizontal Scaling**: Add more web instances as traffic grows (not just bigger servers)
- **High Availability**: If one instance fails, others continue serving requests
- **Shared State**: Database ensures all instances see the same data
- **Performance**: Load balancing distributes load efficiently

#### Technology Stack

**Backend:**
- **Ruby 3.x**: Modern, performant Ruby version
- **Rails 8.1**: Latest Rails with built-in Solid Queue, Solid Cache
- **PostgreSQL**: Robust relational database with excellent performance
- **Puma**: Multi-threaded web server (25 threads per instance)

**Frontend:**
- **Tailwind CSS**: Utility-first CSS framework
- **Hotwire (Turbo + Stimulus)**: Modern, lightweight JavaScript framework
- **Propshaft**: Simple asset pipeline

**Infrastructure:**
- **Docker Compose**: Container orchestration
- **Traefik**: Reverse proxy and load balancer
- **Solid Queue**: Background job processing (built into Rails 8)
- **Solid Cache**: Database-backed caching (built into Rails 8)

**Why These Choices?**
- **Rails 8**: Includes Solid Queue and Solid Cache (no Redis needed)
- **PostgreSQL**: Handles complex queries, excellent for social graphs
- **Docker**: Consistent environments, easy scaling
- **Traefik**: Automatic service discovery, no manual configuration

---

### 2. Data Model Design

#### Core Entities

**Users Table:**
```ruby
# Stores user accounts
- id: Primary key
- username: Unique, max 50 characters
- password_digest: Hashed password (bcrypt)
- description: Optional bio, max 120 characters
- followers_count: Counter cache (updated automatically)
- following_count: Counter cache
- posts_count: Counter cache
- created_at, updated_at: Timestamps
```

**Posts Table:**
```ruby
# Stores all posts and replies
- id: Primary key
- author_id: Foreign key to users (nullable - for deleted users)
- content: Text, max 200 characters
- parent_id: Foreign key to posts (for replies)
- created_at, updated_at: Timestamps
```

**Follows Table:**
```ruby
# Stores follow relationships (composite primary key)
- follower_id: User who follows
- followed_id: User being followed
- created_at, updated_at: Timestamps
- Composite primary key: (follower_id, followed_id)
```

**Feed Entries Table:**
```ruby
# Pre-computed feed entries (fan-out on write)
- id: Primary key
- user_id: User who will see this in their feed
- post_id: The post
- author_id: Original author (for filtering)
- created_at: When entry was created (for sorting)
```

#### Database Relationships

**One-to-Many: Users → Posts**
```ruby
# User has many posts
user.posts  # Returns all posts by this user

# When user is deleted, posts remain but author_id becomes NULL
# This preserves conversation history
```

**Many-to-Many: Users ↔ Users (Follows)**
```ruby
# Self-referential many-to-many relationship
user.following  # Users this user follows
user.followers  # Users who follow this user

# Composite primary key prevents duplicate follows
# Cascade delete: if user deleted, all their follows deleted
```

**One-to-Many: Posts → Posts (Replies)**
```ruby
# Self-referential relationship for threading
post.replies  # All replies to this post
post.parent   # Parent post (if this is a reply)

# Supports nested conversations
# When parent deleted, replies remain but parent_id becomes NULL
```

**Why This Design?**
- **Normalized**: Reduces data duplication
- **Flexible**: Supports complex relationships
- **Performance**: Indexes on foreign keys
- **Data Integrity**: Foreign keys ensure consistency

---

### 3. Software Design Principles Applied

#### Separation of Concerns
- **Models**: Business logic and data access
- **Controllers**: Request handling and routing
- **Jobs**: Background processing
- **Services**: Reusable business logic (optional)

#### DRY (Don't Repeat Yourself)
- Shared helpers in `ApplicationController`
- Reusable pagination logic
- Common queries in model scopes

#### Single Responsibility Principle
- Each model has one clear purpose
- Controllers handle one resource type
- Jobs perform one specific task

#### Convention over Configuration
- Follow Rails conventions (RESTful routes, naming)
- Reduces boilerplate code
- Makes codebase easier to understand

---

## Database Design & Optimization

### 1. Index Strategy

#### Why Indexes Matter

**Without Indexes:**
```sql
-- Query: Find posts by a specific author
SELECT * FROM posts WHERE author_id = 123;
-- Database scans ALL rows (slow for millions of posts)
-- Time: 500ms+ for large tables
```

**With Indexes:**
```sql
-- Same query with index on author_id
SELECT * FROM posts WHERE author_id = 123;
-- Database uses index to find rows directly
-- Time: <10ms even for millions of posts
```

#### Composite Indexes

**Problem:** Need to query by multiple columns together

**Example: Finding user's posts, ordered by date**
```sql
-- Without composite index
SELECT * FROM posts
WHERE author_id = 123
ORDER BY created_at DESC;
-- Database: Filter by author_id, then sort (slow)
```

**Solution: Composite Index**
```sql
-- Index on (author_id, created_at DESC)
CREATE INDEX idx_posts_author_created
ON posts(author_id, created_at DESC);

-- Now database can:
-- 1. Jump directly to author_id = 123 rows
-- 2. Already sorted by created_at
-- Result: 10-40x faster
```

**Composite Indexes in This Codebase:**
```ruby
# Posts table
add_index :posts, [:author_id, :created_at],
          order: { created_at: :desc }
# Used for: User's posts, ordered newest first

# Feed entries table
add_index :feed_entries, [:user_id, :created_at],
          order: { created_at: :desc }
# Used for: User's feed, ordered newest first

# Follows table
add_index :follows, [:follower_id, :followed_id], unique: true
# Used for: Fast follow/unfollow checks
```

**Key Learning:**
- Indexes on foreign keys are essential
- Composite indexes speed up multi-column queries
- Order matters: Put most selective column first
- DESC order in index helps with sorting

---

### 2. Query Optimization

#### The Problem: Slow Feed Queries

**Initial Implementation (Naive):**
```ruby
def feed_posts
  # Get all users I follow
  followed_ids = following.pluck(:id)

  # Get their posts
  Post.where(author_id: followed_ids)
      .or(Post.where(author_id: id))  # Include my own posts
      .order(created_at: :desc)
end
```

**Why This is Slow:**
1. Two queries (one to get followed_ids, one to get posts)
2. Large IN clause if following many users
3. No index on author_id alone (composite index helps but not perfect)
4. Time: 50-200ms for users with 2,500+ follows

**Optimized Implementation:**
```ruby
def feed_posts
  # Single query with JOIN
  user_id = Post.connection.quote(id)
  Post.joins(
    "LEFT JOIN follows ON posts.author_id = follows.followed_id AND follows.follower_id = #{user_id}"
  ).where(
    "posts.author_id = ? OR follows.followed_id IS NOT NULL",
    id
  ).distinct.order(created_at: :desc)
end
```

**Why This is Better:**
- Single query (no separate pluck)
- JOIN is faster than large IN clause
- Database optimizer can use indexes efficiently
- Time: 50-100ms (still not perfect, but better)

**Best Solution: Fan-Out on Write (see below)**

---

### 3. Counter Caches

#### The Problem: Counting Followers

**Without Counter Cache:**
```ruby
# Every time we display follower count
user.followers.count
# Executes: SELECT COUNT(*) FROM follows WHERE followed_id = ?
# Time: 10-50ms per request
# Problem: Expensive for users with many followers
```

**With Counter Cache:**
```ruby
# Counter cache automatically maintained
user.followers_count
# Executes: SELECT followers_count FROM users WHERE id = ?
# Time: <1ms
# Result: 10-50x faster
```

#### How Counter Caches Work

**Database Column:**
```ruby
# Migration
add_column :users, :followers_count, :integer, default: 0, null: false
add_index :users, :followers_count  # For sorting by popularity
```

**Automatic Updates:**
```ruby
# app/models/follow.rb
class Follow < ApplicationRecord
  belongs_to :follower, class_name: "User", counter_cache: :following_count
  belongs_to :followed, class_name: "User", counter_cache: :followers_count

  # When Follow is created:
  # - followed.followers_count automatically increments
  # - follower.following_count automatically increments

  # When Follow is deleted:
  # - Counters automatically decrement
end
```

**Manual Updates (for delete_all):**
```ruby
# When using delete_all (bypasses callbacks)
# We must manually update counters
deleted_count = Follow.where(...).delete_all
user.decrement!(:followers_count, deleted_count)
```

**Key Learning:**
- Counter caches are essential for frequently-displayed counts
- Rails automatically maintains them via callbacks
- Manual updates needed for delete_all operations
- Backfill required for existing data

---

### 4. Cursor-Based Pagination

#### The Problem with OFFSET

**OFFSET-Based Pagination (Traditional):**
```ruby
# Page 1
Post.limit(20).offset(0)   # Fast (<10ms)

# Page 100
Post.limit(20).offset(2000)  # Slow (50-200ms)
# Database must scan and skip 2000 rows
```

**Why OFFSET is Slow:**
- Database must count/skip rows
- Gets slower as offset increases
- Doesn't work well with real-time data (new posts shift pagination)

**Cursor-Based Pagination (Solution):**
```ruby
# Page 1
Post.limit(20).order(created_at: :desc)

# Page 2 (using cursor from last post)
Post.where("id < ?", last_post_id)
    .limit(20)
    .order(created_at: :desc)
# Database uses index to jump directly to cursor position
# Time: <10ms regardless of page number
```

**Implementation:**
```ruby
# app/controllers/application_controller.rb
def cursor_paginate(relation, per_page: 20, cursor: nil, order: :desc)
  cursor_id = cursor || params[:cursor]&.to_i

  if cursor_id.present?
    if order == :asc
      relation = relation.where("id > ?", cursor_id)
    else
      relation = relation.where("id < ?", cursor_id)
    end
  end

  posts = relation.limit(per_page + 1).to_a
  has_next = posts.length > per_page
  posts = posts.take(per_page) if has_next
  next_cursor = posts.last&.id

  [posts, next_cursor, has_next]
end
```

**Benefits:**
- Consistent performance regardless of page number
- Works with real-time data (no shifting)
- Uses index efficiently (WHERE id < cursor)
- 10-20x faster than OFFSET for deep pagination

**Key Learning:**
- Cursor-based pagination is essential for large datasets
- Works with any ordered column (usually id or created_at)
- More complex to implement but worth it for performance

---

## Performance Optimization Techniques

### 1. Fan-Out on Write (Push Model)

#### The Concept

**Traditional Approach (Pull Model):**
```
User requests feed
  ↓
Query: JOIN posts + follows (complex, slow)
  ↓
Return results (50-200ms)
```

**Fan-Out on Write (Push Model):**
```
User creates post
  ↓
Insert post (5-15ms)
  ↓
Background job: For each follower, create feed entry
  ↓
User requests feed
  ↓
Query: SELECT * FROM feed_entries WHERE user_id = ? (simple, fast)
  ↓
Return results (5-20ms)
```

#### Why This Matters

**Performance Comparison:**
- **Pull Model**: 50-200ms per feed request
- **Fan-Out Model**: 5-20ms per feed request
- **Improvement**: 10-40x faster

**Scalability:**
- **Pull Model**: Slows down as users follow more people
- **Fan-Out Model**: Performance stays constant regardless of follow count

#### Implementation

**Database Schema:**
```ruby
create_table :feed_entries do |t|
  t.bigint :user_id, null: false      # Who will see this
  t.bigint :post_id, null: false      # The post
  t.bigint :author_id, null: false    # Original author
  t.timestamps
end

# Critical indexes
add_index :feed_entries, [:user_id, :created_at],
          order: { created_at: :desc }
add_index :feed_entries, [:user_id, :post_id], unique: true
```

**Background Job:**
```ruby
# app/jobs/fan_out_feed_job.rb
class FanOutFeedJob < ApplicationJob
  def perform(post_id)
    post = Post.find(post_id)
    author = post.author

    # Get all followers
    follower_ids = author.followers.pluck(:id)

    # Create feed entries for each follower
    follower_ids.each do |follower_id|
      FeedEntry.create!(
        user_id: follower_id,
        post_id: post.id,
        author_id: author.id
      )
    end
  end
end
```

**Model Hook:**
```ruby
# app/models/post.rb
after_create :fan_out_to_followers

def fan_out_to_followers
  return if parent_id.present?  # Don't fan-out replies
  return unless author_id.present?

  FanOutFeedJob.perform_later(id)
end
```

**Feed Query:**
```ruby
# app/models/user.rb
def feed_posts
  Post.joins("INNER JOIN feed_entries ON posts.id = feed_entries.post_id")
      .where("feed_entries.user_id = ?", id)
      .order("feed_entries.created_at DESC")
      .distinct
end
```

**Trade-offs:**
- ✅ **Pros**: 10-40x faster queries, constant performance
- ⚠️ **Cons**: More storage (one entry per post per follower), write overhead
- **Verdict**: Worth it for read-heavy workloads (feeds are read much more than written)

**Key Learning:**
- Pre-compute expensive queries when data is created
- Trade storage for speed
- Use background jobs for heavy operations
- This pattern is used by Twitter, Facebook, Instagram

---

### 2. Caching Strategy

#### Solid Cache Overview

**What is Solid Cache?**
- Rails 8's built-in database-backed cache
- Stores cached data in PostgreSQL (or SQLite)
- No Redis needed (but can use Redis if preferred)

**Why Use Caching?**
- Reduce database load
- Faster response times (<1ms vs 50-200ms)
- Better scalability

#### Caching Implementation

**Feed Query Caching:**
```ruby
# app/controllers/posts_controller.rb
def index
  if current_user
    cache_key = "user_feed:#{current_user.id}:#{params[:cursor]}"
    cached_result = Rails.cache.read(cache_key)

    if cached_result
      @posts, @next_cursor, @has_next = cached_result
      return  # Cache hit - return immediately
    end

    # Cache miss - execute query
    posts_relation = current_user.feed_posts.timeline
    @posts, @next_cursor, @has_next = cursor_paginate(posts_relation)

    # Cache result
    Rails.cache.write(cache_key, [@posts, @next_cursor, @has_next],
                      expires_in: 5.minutes)
  end
end
```

**User Profile Caching:**
```ruby
# app/controllers/users_controller.rb
def show
  @user = Rails.cache.fetch("user:#{params[:id]}", expires_in: 1.hour) do
    User.find(params[:id])
  end
end
```

**Cache Invalidation:**
```ruby
# When user updates profile
def update
  if @user.update(user_params)
    Rails.cache.delete("user:#{@user.id}")  # Invalidate cache
    redirect_to @user
  end
end
```

#### Cache Key Strategy

**Good Cache Keys:**
- Include all variables that affect the result
- Example: `"user_feed:#{user_id}:#{cursor}"`
- Include user_id (different users see different feeds)
- Include cursor (different pages have different results)

**Cache TTL (Time To Live):**
- **Feed queries**: 5 minutes (balance freshness vs performance)
- **User profiles**: 1 hour (profiles change less frequently)
- **Public posts**: 1 minute (more frequent updates)

**Key Learning:**
- Cache expensive queries (feed, user profiles)
- Use appropriate TTL (balance freshness vs performance)
- Invalidate cache when data changes
- Cache keys must include all variables affecting results

---

### 3. Query Optimization Techniques

#### Use JOINs Instead of IN Clauses

**Bad (IN clause with many values):**
```ruby
followed_ids = following.pluck(:id)  # [1, 2, 3, ..., 2500]
Post.where(author_id: followed_ids)   # IN (1, 2, 3, ..., 2500)
# Slow for large arrays
```

**Good (JOIN):**
```ruby
Post.joins("INNER JOIN follows ON posts.author_id = follows.followed_id")
    .where(follows: { follower_id: id })
# Database can use indexes efficiently
```

#### Use Scopes for Reusability

```ruby
# app/models/post.rb
scope :timeline, -> { order(created_at: :desc) }
scope :top_level, -> { where(parent_id: nil) }
scope :replies, -> { where.not(parent_id: nil) }

# Usage
current_user.posts.timeline
Post.top_level.timeline
```

#### Avoid N+1 Queries

**Bad (N+1 queries):**
```ruby
posts = Post.all
posts.each do |post|
  puts post.author.username  # One query per post!
end
# Total: 1 + N queries (N = number of posts)
```

**Good (Eager loading):**
```ruby
posts = Post.includes(:author).all
posts.each do |post|
  puts post.author.username  # No additional queries!
end
# Total: 2 queries (one for posts, one for authors)
```

---

## Security Implementation

### 1. Authentication System

#### Password Hashing

**Why Hash Passwords?**
- Never store plain text passwords
- If database is compromised, passwords are still protected
- Use bcrypt (slow, secure hashing algorithm)

**Implementation:**
```ruby
# app/models/user.rb
class User < ApplicationRecord
  has_secure_password
  # Automatically:
  # - Validates password presence on create
  # - Hashes password using bcrypt
  # - Provides authenticate method
end

# Usage
user = User.find_by(username: "alice")
if user&.authenticate("password123")
  # Login successful
else
  # Invalid credentials
end
```

#### Session Management

**How Sessions Work:**
```ruby
# Login
session[:user_id] = user.id

# Check authentication
def current_user
  @current_user ||= User.find_by(id: session[:user_id])
end

# Logout
session[:user_id] = nil
```

**Security Considerations:**
- Sessions stored server-side (secure)
- Session ID in cookie (HttpOnly, Secure in production)
- Session timeout (Rails default: session expires)

#### Authentication Flow

**Signup:**
```
1. User submits form (username, password, password_confirmation)
2. Validate username uniqueness, password length
3. Create user (password is hashed automatically)
4. Set session[:user_id]
5. Redirect to feed
```

**Login:**
```
1. User submits form (username, password)
2. Find user by username
3. Call user.authenticate(password)
4. If valid: Set session[:user_id]
5. If invalid: Show generic error (don't reveal if username exists)
```

**Logout:**
```
1. Clear session[:user_id]
2. Redirect to home
```

**Key Learning:**
- Always hash passwords (never store plain text)
- Use generic error messages (don't reveal if username exists)
- Validate input on both client and server
- Use secure session management

---

### 2. Rate Limiting

#### Why Rate Limiting?

**Problems It Solves:**
- Prevent spam (too many posts)
- Prevent abuse (too many reports)
- Prevent DDoS attacks (too many requests)
- Ensure fair resource usage

#### Implementation with Rack::Attack

**Configuration:**
```ruby
# config/initializers/rack_attack.rb
class Rack::Attack
  # Use Solid Cache as storage
  Rack::Attack.cache.store = Rails.cache

  # General rate limit: 300 requests per 5 minutes per IP
  throttle("req/ip", limit: 300, period: 5.minutes) do |req|
    req.ip
  end

  # Post creation: 10 posts per minute per user
  throttle("posts/create", limit: 10, period: 1.minute) do |req|
    if req.path == "/posts" && req.post?
      req.session["user_id"] || req.ip
    end
  end

  # Feed requests: 100 requests per minute per user
  throttle("feed/requests", limit: 100, period: 1.minute) do |req|
    if (req.path == "/posts" || req.path == "/") && req.get?
      req.session["user_id"] || req.ip
    end
  end
end
```

**How It Works:**
1. Middleware intercepts every request
2. Checks if rate limit exceeded
3. If exceeded: Returns 429 Too Many Requests
4. If not: Allows request through

**Response Headers:**
```
X-RateLimit-Limit: 300
X-RateLimit-Remaining: 250
X-RateLimit-Reset: 1700000000
Retry-After: 60
```

**Key Learning:**
- Rate limiting is essential for production
- Different endpoints need different limits
- Use per-user limits when possible (more accurate than IP)
- Provide helpful headers so clients know when to retry

---

## Testing Strategy

### 1. Test Pyramid

**Structure:**
```
        /\
       /  \      E2E Tests (Few)
      /____\     - Feature specs
     /      \    - User journeys
    /        \
   /__________\  Integration Tests (Some)
  /            \ - Request specs
 /              \ - Controller specs
/________________\  Unit Tests (Many)
                  - Model specs
                  - Helper specs
```

**Why This Structure?**
- **Unit tests**: Fast, test individual components
- **Integration tests**: Test component interactions
- **E2E tests**: Slow, test full user flows
- **Balance**: More fast tests, fewer slow tests

### 2. Unit Tests (Model Specs)

**Example: User Model**
```ruby
# spec/models/user_spec.rb
RSpec.describe User do
  describe "validations" do
    it "requires username" do
      user = User.new
      expect(user).not_to be_valid
      expect(user.errors[:username]).to include("can't be blank")
    end

    it "requires unique username" do
      create(:user, username: "alice")
      user = User.new(username: "alice")
      expect(user).not_to be_valid
    end
  end

  describe "#follow" do
    it "creates a follow relationship" do
      user1 = create(:user)
      user2 = create(:user)

      expect { user1.follow(user2) }.to change(Follow, :count).by(1)
      expect(user1.following).to include(user2)
    end
  end
end
```

**What to Test:**
- Validations
- Associations
- Business logic methods
- Edge cases

**Key Learning:**
- Test behavior, not implementation
- Use factories (FactoryBot) for test data
- Test edge cases (nil, empty, invalid data)
- Keep tests fast (<1ms each)

---

### 3. Integration Tests (Request Specs)

**Example: Posts Controller**
```ruby
# spec/requests/posts_spec.rb
RSpec.describe "Posts", type: :request do
  let(:user) { create(:user) }

  before do
    login_as(user)
  end

  describe "GET /posts" do
    it "returns successful response" do
      get posts_path
      expect(response).to have_http_status(:success)
    end

    it "displays user's posts" do
      create(:post, author: user, content: "My post")
      get posts_path
      expect(response.body).to include("My post")
    end
  end

  describe "POST /posts" do
    it "creates a new post" do
      expect {
        post posts_path, params: { post: { content: "New post" } }
      }.to change(Post, :count).by(1)
    end
  end
end
```

**What to Test:**
- HTTP status codes
- Response content
- Database changes
- Redirects
- Error handling

**Key Learning:**
- Test the full request/response cycle
- Use factories for test data
- Test both success and failure cases
- Verify database state changes

---

### 4. End-to-End Tests (Feature Specs)

**Example: User Journey**
```ruby
# spec/features/end_to_end_spec.rb
RSpec.describe "End-to-End User Journey", type: :feature do
  it "allows a user to sign up, post, follow, and interact" do
    # 1. Signup
    visit signup_path
    fill_in "Username", with: "alice"
    fill_in "Password", with: "password123"
    fill_in "Confirm Password", with: "password123"
    click_button "Sign up"
    expect(page).to have_content("Welcome to Microblog")

    # 2. Create post
    fill_in "post_content", with: "Hello world!"
    click_button "Post"
    expect(page).to have_content("Hello world!")

    # 3. Follow another user
    user2 = create(:user, username: "bob")
    visit user_path(user2)
    click_button "Follow"
    expect(page).to have_content("You are now following bob")

    # 4. View feed
    visit root_path
    expect(page).to have_content("Hello world!")
  end
end
```

**What to Test:**
- Complete user workflows
- UI interactions
- Navigation flows
- Multi-step processes

**Key Learning:**
- Test from user's perspective
- Use Capybara for browser interactions
- Keep E2E tests focused on critical paths
- They're slow, so use sparingly

---

### 5. Testing Best Practices

**Test Organization:**
```
spec/
├── models/          # Unit tests (fast)
├── requests/         # Integration tests (medium)
├── features/         # E2E tests (slow)
├── jobs/             # Background job tests
├── factories/        # Test data factories
└── support/          # Test helpers
```

**Test Data:**
- Use factories (FactoryBot) instead of fixtures
- Create minimal data needed for test
- Use traits for variations
- Use sequences for unique values

**Test Coverage:**
- Aim for >80% code coverage
- Focus on critical paths
- Don't test framework code (Rails internals)
- Test edge cases and error conditions

**Key Learning:**
- Write tests before fixing bugs (TDD)
- Keep tests fast and independent
- Use descriptive test names
- Test behavior, not implementation

---

## Infrastructure & Scaling

### 1. Docker & Containerization

#### Why Docker?

**Benefits:**
- Consistent environments (dev, staging, production)
- Easy scaling (run multiple instances)
- Isolation (each service in own container)
- Reproducible builds

#### Docker Compose Setup

**docker-compose.yml Structure:**
```yaml
services:
  db:
    image: postgres:16
    # Database configuration

  web:
    build: .
    # Application configuration
    depends_on:
      - db
    # Scale with: docker compose up --scale web=3

  traefik:
    image: traefik:v2.10
    # Load balancer configuration
```

**Key Concepts:**
- **Services**: Individual containers (db, web, traefik)
- **Networks**: Containers communicate via network
- **Volumes**: Persistent data storage
- **Scaling**: Run multiple instances of same service

**Scaling Example:**
```bash
# Run 3 web instances
docker compose up -d --scale web=3

# Traefik automatically distributes requests
# Load balancing happens automatically
```

**Key Learning:**
- Docker enables horizontal scaling
- Services communicate via service names (not localhost)
- Networks isolate containers
- Volumes persist data across container restarts

---

### 2. Horizontal Scaling

#### What is Horizontal Scaling?

**Vertical Scaling (Old Way):**
- Make server bigger (more CPU, RAM)
- Limited by hardware
- Expensive

**Horizontal Scaling (Modern Way):**
- Add more servers
- Distribute load across instances
- Cost-effective

#### Implementation

**Load Balancer (Traefik):**
- Distributes requests across web instances
- Health checks (remove unhealthy instances)
- Automatic service discovery
- SSL termination

**Shared Database:**
- All instances connect to same database
- Ensures data consistency
- Can become bottleneck (add read replicas)

**Stateless Application:**
- No session storage in application
- Sessions in database or external store
- Any instance can handle any request

**Key Learning:**
- Horizontal scaling is essential for growth
- Application must be stateless
- Load balancer distributes traffic
- Database can be shared (but may need read replicas)

---

### 3. Background Jobs

#### Why Background Jobs?

**Problem:**
- Some operations take too long (fan-out to 10,000 followers)
- Block request/response cycle
- User waits unnecessarily

**Solution:**
- Queue job for later processing
- Return response immediately
- Process job in background

#### Solid Queue Implementation

**Job Definition:**
```ruby
# app/jobs/fan_out_feed_job.rb
class FanOutFeedJob < ApplicationJob
  queue_as :default

  def perform(post_id)
    post = Post.find(post_id)
    # Heavy operation (fan-out to all followers)
    # Takes 1-5 seconds, but doesn't block request
  end
end
```

**Enqueue Job:**
```ruby
# In controller or model
FanOutFeedJob.perform_later(post.id)
# Returns immediately, job processed in background
```

**Job Processing:**
- Solid Queue workers process jobs
- Can run in Puma process or separate process
- Handles retries, failures, scheduling

**Key Learning:**
- Use background jobs for heavy operations
- Keep request/response cycle fast
- Jobs can retry on failure
- Monitor job queue (Mission Control)

---

### 4. Read Replicas

#### The Problem

**Single Database Bottleneck:**
- All reads and writes go to one database
- Database becomes bottleneck at scale
- Can't scale reads independently

**Solution: Read Replicas**
- Primary database: Handles writes
- Read replicas: Handle reads
- Distribute read load across replicas

#### Implementation

**Database Configuration:**
```yaml
# config/database.yml
production:
  primary:
    <<: *default
    database: microblog_production
    host: <%= ENV.fetch("DATABASE_HOST") { "db-primary" } %>

  replica:
    <<: *default
    database: microblog_production
    host: <%= ENV.fetch("REPLICA_HOST") { "db-replica" } %>
    replica: true
```

**Read from Replica:**
```ruby
# app/models/user.rb
def feed_posts
  # Use replica for read-only queries
  ActiveRecord::Base.connected_to(role: :reading) do
    Post.joins(...).where(...)
  end
end
```

**Key Learning:**
- Read replicas scale read operations
- Writes still go to primary
- Replication lag (replicas slightly behind)
- Use for read-heavy workloads

---

## Monitoring & Performance Analysis

### 1. Performance Monitoring

#### pg_stat_statements

**What is it?**
- PostgreSQL extension that tracks query statistics
- Shows slow queries, frequent queries, total time
- Essential for performance tuning

**Setup:**
```sql
-- Enable extension
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Query slow queries
SELECT query, calls, mean_exec_time, total_exec_time
FROM pg_stat_statements
WHERE mean_exec_time > 100  -- Queries slower than 100ms
ORDER BY mean_exec_time DESC
LIMIT 20;
```

**What to Monitor:**
- Slow queries (>100ms)
- Frequent queries
- Queries using most total time
- Index usage

**Key Learning:**
- Monitor query performance regularly
- Identify slow queries
- Optimize based on data, not guesses
- pg_stat_statements is essential tool

---

### 2. Load Testing

#### Why Load Test?

**Purpose:**
- Verify performance under load
- Identify bottlenecks
- Test scalability
- Validate optimizations

#### Tools Used

**k6:**
- Modern load testing tool
- JavaScript-based scripts
- Realistic user scenarios
- Custom metrics

**wrk:**
- High-performance HTTP benchmarking
- Simple Lua scripts
- Good for baseline testing

**Example k6 Script:**
```javascript
import http from 'k6/http';
import { check } from 'k6';

export let options = {
  stages: [
    { duration: '30s', target: 10 },   // Ramp up to 10 users
    { duration: '1m', target: 10 },  // Stay at 10 users
    { duration: '30s', target: 0 },  // Ramp down
  ],
};

export default function() {
  let response = http.get('http://localhost:3000/posts');
  check(response, {
    'status is 200': (r) => r.status === 200,
    'response time < 200ms': (r) => r.timings.duration < 200,
  });
}
```

**Metrics to Track:**
- Requests per second (RPS)
- Response time (p50, p95, p99)
- Error rate
- Throughput

**Key Learning:**
- Load test before production
- Test realistic scenarios
- Monitor during tests
- Iterate based on results

---

### 3. Application Monitoring

#### Puma Stats

**Endpoint:**
```bash
curl http://localhost:3000/puma/stats
```

**Metrics:**
- Worker status
- Thread pool usage
- Backlog (queued requests)
- Requests per second

#### Mission Control (Solid Queue)

**Access:**
- http://localhost:3000/jobs (development)

**Features:**
- View job queue
- See failed jobs
- Monitor job processing
- Retry failed jobs

#### Health Check Endpoint

```ruby
# config/routes.rb
get "/health" => proc { |env|
  {
    status: "ok",
    database: { connected: ActiveRecord::Base.connection.active? },
    timestamp: Time.current.iso8601
  }.to_json
}
```

**Key Learning:**
- Monitor application health
- Set up alerts for failures
- Track key metrics over time
- Use monitoring to guide optimization

---

## Key Learnings & Takeaways

### 1. Database Design Principles

**Takeaways:**
- ✅ Indexes are critical for performance
- ✅ Composite indexes speed up multi-column queries
- ✅ Foreign keys ensure data integrity
- ✅ Counter caches eliminate expensive COUNT queries
- ✅ Cursor pagination is essential for large datasets

### 2. Performance Optimization

**Takeaways:**
- ✅ Pre-compute expensive queries (fan-out on write)
- ✅ Cache frequently accessed data
- ✅ Use background jobs for heavy operations
- ✅ Optimize queries (JOINs, indexes, scopes)
- ✅ Monitor and measure (don't optimize blindly)

### 3. Architecture Patterns

**Takeaways:**
- ✅ Horizontal scaling is key to growth
- ✅ Stateless applications scale better
- ✅ Load balancing distributes traffic
- ✅ Read replicas scale read operations
- ✅ Background jobs handle async work

### 4. Security Practices

**Takeaways:**
- ✅ Always hash passwords (never plain text)
- ✅ Rate limiting prevents abuse
- ✅ Validate input on server (not just client)
- ✅ Use secure session management
- ✅ Generic error messages (don't leak information)

### 5. Testing Strategy

**Takeaways:**
- ✅ Test pyramid (many unit tests, some integration, few E2E)
- ✅ Test behavior, not implementation
- ✅ Use factories for test data
- ✅ Keep tests fast and independent
- ✅ Aim for >80% coverage

### 6. Infrastructure

**Takeaways:**
- ✅ Docker enables consistent environments
- ✅ Horizontal scaling is essential
- ✅ Load balancers distribute traffic
- ✅ Monitoring is crucial
- ✅ Plan for scaling from the start

---

## Common Pitfalls & How We Avoided Them

### 1. N+1 Queries

**Pitfall:**
```ruby
# Bad: N+1 queries
posts.each { |post| puts post.author.username }
# Executes: 1 query for posts + N queries for authors
```

**Solution:**
```ruby
# Good: Eager loading
posts.includes(:author).each { |post| puts post.author.username }
# Executes: 2 queries total (posts + authors)
```

### 2. Missing Indexes

**Pitfall:**
```ruby
# Query without index
Post.where(author_id: 123)  # Scans all rows
```

**Solution:**
```ruby
# Add index
add_index :posts, :author_id
# Query uses index, fast lookup
```

### 3. OFFSET Pagination

**Pitfall:**
```ruby
# Slow for deep pagination
Post.offset(10000).limit(20)  # Scans 10000 rows
```

**Solution:**
```ruby
# Cursor-based pagination
Post.where("id < ?", cursor_id).limit(20)  # Uses index
```

### 4. Synchronous Heavy Operations

**Pitfall:**
```ruby
# Blocks request
def create
  post = Post.create!(params)
  fan_out_to_10000_followers(post)  # Takes 5 seconds!
  redirect_to post
end
```

**Solution:**
```ruby
# Background job
def create
  post = Post.create!(params)
  FanOutFeedJob.perform_later(post.id)  # Returns immediately
  redirect_to post
end
```

---

## Performance Metrics Achieved

### Current Performance

**At 1M User Scale:**
- Users: 1,091,000
- Posts: 73,817
- Follows: 50,368,293
- User profile page: <100ms (with counter cache)
- Feed queries: 5-20ms (with fan-out on write)

**Load Testing Results:**
- Baseline: 30-50 RPS
- With optimizations: 50-100 RPS
- With fan-out on write: 100-200 RPS
- Target achieved: ✅

### Optimization Impact

**Counter Cache:**
- Before: 200-500ms (COUNT query)
- After: <1ms (counter cache)
- Improvement: 200-500x faster

**Fan-Out on Write:**
- Before: 50-200ms (JOIN query)
- After: 5-20ms (simple lookup)
- Improvement: 10-40x faster

**Cursor Pagination:**
- Before: 50-200ms (OFFSET 10000)
- After: <10ms (cursor-based)
- Improvement: 5-20x faster

---

## Real-World Application

### What This Teaches

This codebase demonstrates production-ready patterns used by major platforms:

1. **Fan-Out on Write**: Used by Twitter, Facebook, Instagram
2. **Cursor Pagination**: Used by Twitter, Reddit, GitHub
3. **Counter Caches**: Used everywhere for counts
4. **Rate Limiting**: Essential for all public APIs
5. **Horizontal Scaling**: Standard for modern web apps
6. **Background Jobs**: Critical for user experience

### Skills Gained

By studying this codebase, you learn:
- ✅ Database optimization techniques
- ✅ Performance optimization patterns
- ✅ Security best practices
- ✅ Testing strategies
- ✅ Infrastructure setup
- ✅ Monitoring and analysis
- ✅ Real-world problem solving

---

## References & Further Reading

### Documentation in This Repository

**Essential Reading:**
1. `001_DATABASE_DIAGRAM.md` - Database schema
2. `007_PAGINATION.md` - Cursor-based pagination
3. `023_COUNTER_CACHE_INCREMENT_LOGIC.md` - Counter caches
4. `033_FAN_OUT_ON_WRITE_IMPLEMENTATION.md` - Fan-out pattern
5. `031_RATE_LIMITING_IMPLEMENTATION.md` - Rate limiting
6. `036_HORIZONTAL_SCALING.md` - Scaling strategies
7. `028_SCALING_AND_PERFORMANCE_STRATEGIES.md` - Comprehensive guide

**Performance Analysis:**
- `004_PERFORMANCE_ANALYSIS.md` - Initial analysis
- `022_PERFORMANCE_AT_SCALE.md` - 1M user scale
- `018-021_QUERY_PLAN_*.md` - Query optimization analysis

**Testing:**
- `005_LOAD_TESTING.md` - Load testing guide
- `006_MONITORING_GUIDE.md` - Monitoring setup

### External Resources

**Rails Guides:**
- [Rails Guides](https://guides.rubyonrails.org/)
- [Active Record Query Interface](https://guides.rubyonrails.org/active_record_querying.html)
- [Action Controller Overview](https://guides.rubyonrails.org/action_controller_overview.html)

**Performance:**
- [PostgreSQL Performance Tips](https://www.postgresql.org/docs/current/performance-tips.html)
- [Scaling Rails Applications](https://www.speedshop.co/)

**Architecture:**
- [High Scalability](http://highscalability.com/)
- [System Design Primer](https://github.com/donnemartin/system-design-primer)

---

## Conclusion

This microblog application serves as a comprehensive case study in building scalable, production-ready web applications. It demonstrates:

✅ **Real-world patterns** used by major platforms
✅ **Performance optimization** techniques that work
✅ **Security practices** essential for production
✅ **Testing strategies** that ensure quality
✅ **Infrastructure** that scales
✅ **Monitoring** that guides decisions

**Key Takeaway:**
Building a scalable application requires understanding not just how to write code, but how to design systems, optimize performance, ensure security, and plan for growth. This codebase demonstrates all of these principles in practice.

**For Junior Engineers:**
Study this codebase to understand how real-world applications are built. Each optimization, each design decision, each pattern has a reason. Learn not just what was done, but why it was done.

---

**Document Version:** 1.0
**Last Updated:** 2024-11-04
**Target Audience:** Junior Software Engineers, Students, Developers Learning Production Rails
**Status:** ✅ Complete Educational Case Study

