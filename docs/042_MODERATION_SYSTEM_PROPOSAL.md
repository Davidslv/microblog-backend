# Moderation System Proposal

## Executive Summary

This document proposes a comprehensive moderation system for the microblog platform, addressing malicious content, spam, NSFW material, harmful URLs, and community self-moderation. The system combines automated detection, community reporting, and administrative oversight to create a safe environment while maintaining platform health.

**Core Features:**
1. **Post Redaction**: Boolean flag with placeholder text display
2. **Community Reporting**: Report button with auto-redaction at threshold (5 reports)
3. **Abuse Prevention**: Rate limiting, duplicate detection, trust scores
4. **Content Safety**: URL validation, content filtering, pattern detection
5. **Administrative Tools**: Review queue, appeals, audit trail

**Inspired by:** Reddit, Mastodon, Discord, Twitter/X moderation patterns

---

## Table of Contents

- [Overview](#overview)
- [Core Requirements](#core-requirements)
- [Database Schema](#database-schema)
- [Reporting System](#reporting-system)
- [Auto-Moderation](#auto-moderation)
- [Content Safety](#content-safety)
- [Abuse Prevention](#abuse-prevention)
- [Administrative Tools](#administrative-tools)
- [User Experience](#user-experience)
- [Implementation Plan](#implementation-plan)
- [Security Considerations](#security-considerations)
- [Performance Considerations](#performance-considerations)
- [Proven Solutions](#proven-solutions)
- [Future Enhancements](#future-enhancements)

---

## Overview

### Problem Statement

Microblog platforms face unique moderation challenges:
- **Text-only content** but still vulnerable to abuse
- **Malicious URLs** that lead to phishing, malware, or harmful sites
- **Harassment** through coordinated attacks or repeated abuse
- **Spam** and automated posting
- **NSFW content** descriptions or links
- **Illegal content** promotion or links
- **Disinformation** and false information spreading

### Solution Approach

A multi-layered moderation system combining:

1. **Community Self-Moderation**: Users report problematic content
2. **Automated Detection**: Pattern matching, URL safety checks, spam detection
3. **Threshold-Based Action**: Auto-redaction at report threshold
4. **Administrative Review**: Human oversight for appeals and edge cases
5. **User Trust Scores**: Reward good behavior, limit bad actors

---

## Core Requirements

### Requirement 1: Post Redaction

**Functionality:**
- Boolean flag `redacted` on `posts` table
- When `redacted = true`, show placeholder text instead of content
- Author can still see their own redacted content
- Admins can see original content for review

**Implementation:**
```ruby
# Migration
add_column :posts, :redacted, :boolean, default: false, null: false
add_column :posts, :redacted_at, :datetime
add_column :posts, :redacted_by_id, :bigint  # Admin who redacted
add_column :posts, :redaction_reason, :text
add_index :posts, :redacted
add_index :posts, :redacted_at
```

**Display Logic:**
```ruby
# app/models/post.rb
def display_content
  if redacted?
    if author == current_user || current_user&.admin?
      # Show original to author/admin
      content
    else
      # Show placeholder to everyone else
      "This message has been redacted"
    end
  else
    content
  end
end
```

### Requirement 2: Community Reporting

**Functionality:**
- Report button on every post
- Users can report with reason (spam, harassment, NSFW, illegal, etc.)
- When 5+ unique users report, post auto-redacts
- Rate limiting prevents abuse
- Duplicate reports from same user don't count

**Implementation:**
```ruby
# Migration
create_table :reports do |t|
  t.references :post, null: false, foreign_key: true
  t.references :reporter, null: false, foreign_key: { to_table: :users }
  t.string :reason, null: false
  t.text :details
  t.boolean :resolved, default: false
  t.references :resolved_by, foreign_key: { to_table: :users }
  t.datetime :resolved_at
  t.timestamps
end

add_index :reports, [:post_id, :reporter_id], unique: true
add_index :reports, [:post_id, :resolved]
```

---

## Database Schema

### Posts Table Updates

```ruby
# db/migrate/YYYYMMDDHHMMSS_add_moderation_to_posts.rb
class AddModerationToPosts < ActiveRecord::Migration[8.1]
  def change
    # Redaction fields
    add_column :posts, :redacted, :boolean, default: false, null: false
    add_column :posts, :redacted_at, :datetime
    add_column :posts, :redacted_by_id, :bigint
    add_column :posts, :redaction_reason, :text
    add_column :posts, :redaction_source, :string  # 'auto', 'admin', 'appeal'

    # Moderation metadata
    add_column :posts, :report_count, :integer, default: 0, null: false
    add_column :posts, :last_reported_at, :datetime

    # Appeals
    add_column :posts, :appealed, :boolean, default: false, null: false
    add_column :posts, :appealed_at, :datetime
    add_column :posts, :appeal_status, :string  # 'pending', 'approved', 'rejected'

    # Indexes
    add_index :posts, :redacted
    add_index :posts, :redacted_at
    add_index :posts, :report_count
    add_index :posts, :last_reported_at
    add_index :posts, :appealed
  end
end
```

### Reports Table

```ruby
# db/migrate/YYYYMMDDHHMMSS_create_reports.rb
class CreateReports < ActiveRecord::Migration[8.1]
  def change
    create_table :reports do |t|
      t.references :post, null: false, foreign_key: true
      t.references :reporter, null: false, foreign_key: { to_table: :users }
      t.string :reason, null: false  # 'spam', 'harassment', 'nsfw', 'illegal', 'other'
      t.text :details

      # Resolution
      t.boolean :resolved, default: false, null: false
      t.references :resolved_by, null: true, foreign_key: { to_table: :users }
      t.datetime :resolved_at
      t.text :resolution_notes

      # Metadata
      t.string :ip_address
      t.string :user_agent

      t.timestamps
    end

    # Unique constraint: one report per user per post
    add_index :reports, [:post_id, :reporter_id], unique: true

    # Indexes for queries
    add_index :reports, :post_id
    add_index :reports, :reporter_id
    add_index :reports, :reason
    add_index :reports, :resolved
    add_index :reports, :created_at
  end
end
```

### User Trust Scores (Optional but Recommended)

```ruby
# db/migrate/YYYYMMDDHHMMSS_add_trust_score_to_users.rb
class AddTrustScoreToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :trust_score, :integer, default: 100, null: false
    add_column :users, :reports_received, :integer, default: 0, null: false
    add_column :users, :reports_filed, :integer, default: 0, null: false
    add_column :users, :reports_upheld, :integer, default: 0, null: false
    add_column :users, :reports_rejected, :integer, default: 0, null: false

    add_index :users, :trust_score
  end
end
```

### Moderation Actions Audit Trail

```ruby
# db/migrate/YYYYMMDDHHMMSS_create_moderation_actions.rb
class CreateModerationActions < ActiveRecord::Migration[8.1]
  def change
    create_table :moderation_actions do |t|
      t.references :post, null: true, foreign_key: true
      t.references :user, null: true, foreign_key: true
      t.references :admin, null: false, foreign_key: { to_table: :users }
      t.string :action_type, null: false  # 'redact', 'unredact', 'ban', 'unban', 'approve_appeal'
      t.text :reason
      t.jsonb :metadata  # Store additional context
      t.timestamps
    end

    add_index :moderation_actions, :post_id
    add_index :moderation_actions, :user_id
    add_index :moderation_actions, :admin_id
    add_index :moderation_actions, :action_type
    add_index :moderation_actions, :created_at
  end
end
```

---

## Reporting System

### Report Model

```ruby
# app/models/report.rb
class Report < ApplicationRecord
  belongs_to :post
  belongs_to :reporter, class_name: "User"
  belongs_to :resolved_by, class_name: "User", optional: true

  # Report reasons (inspired by Reddit, Mastodon)
  REASONS = {
    'spam' => 'Spam or automated content',
    'harassment' => 'Harassment or bullying',
    'nsfw' => 'NSFW or inappropriate content',
    'illegal' => 'Illegal content or activity',
    'misinformation' => 'False or misleading information',
    'violence' => 'Violence or threats',
    'hate_speech' => 'Hate speech or discrimination',
    'other' => 'Other (please specify)'
  }.freeze

  validates :reason, inclusion: { in: REASONS.keys }
  validates :reporter_id, uniqueness: { scope: :post_id, message: "You have already reported this post" }

  scope :unresolved, -> { where(resolved: false) }
  scope :by_reason, ->(reason) { where(reason: reason) }
  scope :recent, -> { order(created_at: :desc) }

  # After creating a report, check if threshold is met
  after_create :check_auto_redaction_threshold
  after_create :increment_post_report_count

  def check_auto_redaction_threshold
    return if post.redacted?

    # Get unique reporter count (excluding the author)
    unique_reporters = post.reports
      .where.not(reporter_id: post.author_id)
      .distinct
      .count(:reporter_id)

    # Auto-redact at threshold (configurable, default 5)
    threshold = Rails.application.config.moderation_auto_redact_threshold || 5

    if unique_reporters >= threshold
      AutoRedactPostJob.perform_later(post.id, 'auto', 'Threshold reached')
    end
  end

  def increment_post_report_count
    post.increment!(:report_count)
    post.update_column(:last_reported_at, Time.current)
  end
end
```

### Report Controller

```ruby
# app/controllers/reports_controller.rb
class ReportsController < ApplicationController
  before_action :require_login
  before_action :rate_limit_reporting, only: [:create]

  def create
    @post = Post.find(params[:post_id])

    # Prevent reporting own posts
    if @post.author == current_user
      return render json: { error: "You cannot report your own posts" }, status: :unprocessable_entity
    end

    # Check if already reported
    if Report.exists?(post: @post, reporter: current_user)
      return render json: { error: "You have already reported this post" }, status: :unprocessable_entity
    end

    @report = Report.new(
      post: @post,
      reporter: current_user,
      reason: params[:reason],
      details: params[:details],
      ip_address: request.remote_ip,
      user_agent: request.user_agent
    )

    if @report.save
      # Send notification to author if threshold not yet met
      if @post.reports.unresolved.count < 5
        NotificationJob.perform_later(
          @post.author_id,
          "Your post has been reported",
          "A user reported your post for: #{Report::REASONS[@report.reason]}"
        ) if @post.author_id
      end

      render json: {
        message: "Report submitted successfully",
        report_count: @post.reports.unresolved.count,
        threshold: 5
      }, status: :created
    else
      render json: { errors: @report.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def rate_limit_reporting
    # Rate limit: 10 reports per hour per user
    # This prevents coordinated abuse
    key = "reports/user:#{current_user.id}"
    limit = 10
    period = 1.hour

    if Rack::Attack.cache.count(key, period) >= limit
      render json: {
        error: "Rate limit exceeded. Please try again later."
      }, status: :too_many_requests
    end
  end
end
```

### Routes

```ruby
# config/routes.rb
resources :posts do
  member do
    post :report
  end
end

# Admin routes
namespace :admin do
  resources :reports, only: [:index, :show, :update, :destroy]
  resources :moderation_queue, only: [:index]
end
```

---

## Auto-Moderation

### Auto-Redaction Job

```ruby
# app/jobs/auto_redact_post_job.rb
class AutoRedactPostJob < ApplicationJob
  queue_as :default

  def perform(post_id, source, reason)
    post = Post.find(post_id)

    # Don't redact if already redacted
    return if post.redacted?

    # Redact the post
    post.update!(
      redacted: true,
      redacted_at: Time.current,
      redaction_reason: reason,
      redaction_source: source  # 'auto', 'admin', 'appeal'
    )

    # Log moderation action
    ModerationAction.create!(
      post: post,
      admin: nil,  # Auto-moderation has no admin
      action_type: 'redact',
      reason: reason,
      metadata: { source: source, report_count: post.report_count }
    )

    # Notify author
    if post.author_id
      NotificationJob.perform_later(
        post.author_id,
        "Your post was redacted",
        "Your post was automatically redacted due to community reports. You can appeal this decision."
      )
    end

    # Invalidate cache
    Rails.cache.delete("post:#{post.id}")
    Rails.cache.delete_matched("user_posts:*")
    Rails.cache.delete_matched("public_posts:*")
  end
end
```

### Configurable Thresholds

```ruby
# config/initializers/moderation.rb
Rails.application.config.moderation_auto_redact_threshold = ENV.fetch('MODERATION_THRESHOLD', 5).to_i
Rails.application.config.moderation_auto_redact_time_window = ENV.fetch('MODERATION_TIME_WINDOW', 24.hours).to_i
Rails.application.config.moderation_appeal_window = ENV.fetch('MODERATION_APPEAL_WINDOW', 7.days).to_i
```

---

## Content Safety

### URL Safety Checking

```ruby
# app/services/url_safety_service.rb
class UrlSafetyService
  # Google Safe Browsing API (free tier: 10,000 requests/day)
  # Alternative: VirusTotal API, PhishTank

  def self.check_url(url)
    return { safe: true } if url.blank?

    # Extract domain from URL
    uri = URI.parse(url)
    domain = uri.host

    # Check against known bad domains (maintained list)
    if unsafe_domains.include?(domain)
      return { safe: false, reason: 'Known unsafe domain' }
    end

    # Check against Google Safe Browsing (if API key configured)
    if api_key = ENV['GOOGLE_SAFE_BROWSING_API_KEY']
      check_google_safe_browsing(domain, api_key)
    else
      { safe: true }  # Default to safe if no API configured
    end
  end

  private

  def self.unsafe_domains
    # Maintained list of known bad domains
    # Could be stored in database for admin updates
    @unsafe_domains ||= Rails.cache.fetch('unsafe_domains', expires_in: 1.hour) do
      # Load from database or config
      []
    end
  end

  def self.check_google_safe_browsing(domain, api_key)
    # Implement Google Safe Browsing API call
    # See: https://developers.google.com/safe-browsing/v4
    { safe: true }  # Placeholder
  end
end
```

### Content Filtering

```ruby
# app/services/content_filter_service.rb
class ContentFilterService
  # Profanity filter, spam pattern detection, etc.

  def self.check_content(content)
    issues = []

    # Check for spam patterns
    if spam_pattern?(content)
      issues << { type: 'spam', severity: 'high' }
    end

    # Check for profanity (optional, configurable)
    if profanity_detected?(content)
      issues << { type: 'profanity', severity: 'low' }
    end

    # Check for excessive capitalization (spam indicator)
    if excessive_caps?(content)
      issues << { type: 'spam_pattern', severity: 'medium' }
    end

    # Check for URL patterns
    urls = extract_urls(content)
    urls.each do |url|
      safety = UrlSafetyService.check_url(url)
      unless safety[:safe]
        issues << { type: 'unsafe_url', severity: 'high', url: url }
      end
    end

    { safe: issues.empty?, issues: issues }
  end

  private

  def self.spam_pattern?(content)
    # Common spam patterns:
    # - Multiple URLs
    # - Excessive special characters
    # - Repeated words
    # - "Click here" patterns

    url_count = content.scan(/https?:\/\/\S+/).count
    return true if url_count > 2

    # Repeated characters (e.g., "BUY NOW!!!")
    return true if content.match?(/(.)\1{4,}/)

    false
  end

  def self.profanity_detected?(content)
    # Use profanity filter gem (e.g., 'profanity-filter')
    # Or maintain custom list
    false  # Placeholder
  end

  def self.excessive_caps?(content)
    # More than 50% capital letters
    caps_ratio = content.scan(/[A-Z]/).count.to_f / content.length
    caps_ratio > 0.5 && content.length > 10
  end

  def self.extract_urls(content)
    content.scan(/https?:\/\/\S+/)
  end
end
```

### Post Creation Hook

```ruby
# app/models/post.rb
class Post < ApplicationRecord
  # ... existing code ...

  # Content safety check before saving
  before_validation :check_content_safety, on: :create

  def check_content_safety
    return if content.blank?

    safety_check = ContentFilterService.check_content(content)

    unless safety_check[:safe]
      # Log the issues
      Rails.logger.warn "Content safety issues detected: #{safety_check[:issues]}"

      # For high severity issues, prevent creation
      high_severity = safety_check[:issues].any? { |i| i[:severity] == 'high' }
      if high_severity
        errors.add(:content, "Content contains potentially unsafe material")
      end
    end
  end
end
```

---

## Abuse Prevention

### Rate Limiting

```ruby
# config/initializers/rack_attack.rb
class Rack::Attack
  # ... existing code ...

  # Rate limit reporting (prevent coordinated attacks)
  throttle("reports/user", limit: 10, period: 1.hour) do |req|
    if req.path.start_with?("/posts/") && req.post? && req.path.include?("/report")
      req.session["user_id"] rescue nil
    end
  end

  # Rate limit reporting same post (prevent brigading)
  throttle("reports/post", limit: 1, period: 1.hour) do |req|
    if req.path.start_with?("/posts/") && req.post? && req.path.include?("/report")
      post_id = req.path.split("/")[2]
      "#{req.session['user_id']}/#{post_id}" rescue nil
    end
  end
end
```

### Trust Scores

```ruby
# app/models/user.rb
class User < ApplicationRecord
  # ... existing code ...

  # Trust score calculation
  def calculate_trust_score
    base_score = 100

    # Penalties
    base_score -= reports_received * 5
    base_score -= reports_rejected * 2  # False reports

    # Bonuses
    base_score += reports_upheld * 3  # Good reporting

    # Account age bonus
    account_age_days = (Time.current - created_at) / 1.day
    base_score += [account_age_days / 30, 10].min  # Max +10 for account age

    # Posts without reports bonus
    posts_without_reports = posts.where(report_count: 0).count
    base_score += [posts_without_reports / 10, 5].min  # Max +5

    # Clamp between 0 and 200
    [[base_score, 0].max, 200].min
  end

  def update_trust_score!
    update_column(:trust_score, calculate_trust_score)
  end

  # Low trust score users have reduced privileges
  def low_trust?
    trust_score < 50
  end
end
```

### Report Weighting

```ruby
# app/models/report.rb
class Report < ApplicationRecord
  # ... existing code ...

  # Weight reports by reporter trust score
  def weighted_value
    base_weight = 1.0
    reporter_score = reporter.trust_score

    # High trust reporters have more weight
    if reporter_score > 100
      base_weight * 1.5
    elsif reporter_score < 50
      base_weight * 0.5  # Low trust reporters have less weight
    else
      base_weight
    end
  end

  # Update auto-redaction to use weighted reports
  def check_auto_redaction_threshold
    return if post.redacted?

    # Calculate weighted report count
    weighted_count = post.reports
      .where.not(reporter_id: post.author_id)
      .sum { |r| r.weighted_value }

    threshold = Rails.application.config.moderation_auto_redact_threshold || 5.0

    if weighted_count >= threshold
      AutoRedactPostJob.perform_later(post.id, 'auto', 'Weighted threshold reached')
    end
  end
end
```

---

## Administrative Tools

### Moderation Queue

```ruby
# app/controllers/admin/moderation_controller.rb
module Admin
  class ModerationController < ApplicationController
    before_action :require_admin

    def index
      @reports = Report.unresolved
        .includes(:post, :reporter)
        .order(created_at: :desc)
        .page(params[:page])
        .per(50)

      @reported_posts = Post.where(id: @reports.select(:post_id))
        .includes(:author)
        .order(redacted: :asc, report_count: :desc)
    end

    def show
      @report = Report.find(params[:id])
      @post = @report.post
      @similar_reports = Report.where(post: @post).where.not(id: @report.id)
    end

    def resolve
      @report = Report.find(params[:id])
      @report.update!(
        resolved: true,
        resolved_by: current_user,
        resolved_at: Time.current,
        resolution_notes: params[:notes]
      )

      redirect_to admin_moderation_path, notice: "Report resolved"
    end
  end
end
```

### Appeals System

```ruby
# app/models/appeal.rb
class Appeal < ApplicationRecord
  belongs_to :post
  belongs_to :user
  belongs_to :reviewed_by, class_name: "User", optional: true

  validates :reason, presence: true, length: { maximum: 500 }

  scope :pending, -> { where(status: 'pending') }
  scope :approved, -> { where(status: 'approved') }
  scope :rejected, -> { where(status: 'rejected') }

  def approve!(admin)
    update!(
      status: 'approved',
      reviewed_by: admin,
      reviewed_at: Time.current
    )

    # Unredact the post
    post.update!(
      redacted: false,
      appealed: true,
      appeal_status: 'approved'
    )

    # Notify user
    NotificationJob.perform_later(
      user_id,
      "Your appeal was approved",
      "Your post has been restored."
    )
  end

  def reject!(admin, notes = nil)
    update!(
      status: 'rejected',
      reviewed_by: admin,
      reviewed_at: Time.current,
      review_notes: notes
    )

    post.update!(
      appealed: true,
      appeal_status: 'rejected'
    )

    # Notify user
    NotificationJob.perform_later(
      user_id,
      "Your appeal was rejected",
      notes || "Your appeal was reviewed and rejected."
    )
  end
end
```

---

## User Experience

### Report Button UI

```erb
<!-- app/views/posts/_post.html.erb -->
<% if logged_in? && post.author != current_user && !post.redacted? %>
  <div class="relative">
    <%= button_to "Report",
        report_post_path(post),
        method: :post,
        class: "text-red-600 hover:text-red-700 text-sm",
        data: {
          turbo_frame: "report-modal",
          action: "click->modal#open"
        } %>

    <!-- Report Modal -->
    <turbo-frame id="report-modal" class="hidden">
      <%= form_with url: report_post_path(post), method: :post do |f| %>
        <div class="space-y-4">
          <h3>Report Post</h3>

          <%= f.label :reason, "Reason" %>
          <%= f.select :reason,
              Report::REASONS.map { |k, v| [v, k] },
              { prompt: "Select a reason" },
              { required: true } %>

          <%= f.label :details, "Additional details (optional)" %>
          <%= f.text_area :details, rows: 3 %>

          <%= f.submit "Submit Report" %>
          <%= button_tag "Cancel", type: "button", data: { action: "click->modal#close" } %>
        </div>
      <% end %>
    </turbo-frame>
  </div>
<% end %>
```

### Redacted Post Display

```erb
<!-- app/views/posts/_post.html.erb -->
<% if post.redacted? %>
  <div class="bg-gray-100 border border-gray-300 rounded-lg p-4 text-center">
    <p class="text-gray-600 italic">
      This message has been redacted
    </p>
    <% if post.author == current_user %>
      <p class="text-sm text-gray-500 mt-2">
        Your original content:
        <span class="font-mono text-xs"><%= post.content %></span>
      </p>
      <%= link_to "Appeal", new_appeal_path(post_id: post.id),
          class: "text-blue-600 hover:underline text-sm" %>
    <% end %>
  </div>
<% else %>
  <!-- Normal post content -->
  <%= simple_format(post.content) %>
<% end %>
```

---

## Implementation Plan

### Phase 1: Core Redaction (Week 1)

**Day 1-2: Database & Models**
- [ ] Create migration for `redacted` field on posts
- [ ] Update Post model with redaction logic
- [ ] Update views to show placeholder text
- [ ] Test redaction display

**Day 3-4: Basic Reporting**
- [ ] Create reports table migration
- [ ] Create Report model
- [ ] Create ReportsController
- [ ] Add report button to post views
- [ ] Test reporting flow

**Day 5: Auto-Redaction**
- [ ] Implement auto-redaction job
- [ ] Test threshold logic
- [ ] Add notifications

**Estimated Time:** 5 days

### Phase 2: Abuse Prevention (Week 2)

**Day 1-2: Rate Limiting**
- [ ] Add Rack::Attack rules for reporting
- [ ] Implement duplicate report detection
- [ ] Test rate limiting

**Day 3-4: Trust Scores**
- [ ] Add trust score fields to users
- [ ] Implement trust score calculation
- [ ] Add weighted reporting
- [ ] Test trust score system

**Day 5: Content Safety**
- [ ] Implement URL safety checking
- [ ] Add content filtering service
- [ ] Test content safety checks

**Estimated Time:** 5 days

### Phase 3: Admin Tools (Week 3)

**Day 1-2: Moderation Queue**
- [ ] Create admin moderation controller
- [ ] Build moderation queue view
- [ ] Add report resolution workflow

**Day 3-4: Appeals System**
- [ ] Create appeals table and model
- [ ] Build appeals interface
- [ ] Implement appeal approval/rejection

**Day 5: Audit Trail**
- [ ] Create moderation_actions table
- [ ] Log all moderation actions
- [ ] Build audit log view

**Estimated Time:** 5 days

### Phase 4: Advanced Features (Week 4)

**Day 1-2: URL Safety Integration**
- [ ] Integrate Google Safe Browsing API
- [ ] Build unsafe domain management
- [ ] Test URL checking

**Day 3-4: Analytics & Monitoring**
- [ ] Build moderation dashboard
- [ ] Add moderation metrics
- [ ] Create reports for admins

**Day 5: Testing & Polish**
- [ ] Comprehensive test suite
- [ ] Performance optimization
- [ ] Documentation

**Estimated Time:** 5 days

**Total Estimated Time:** 20 days

---

## Security Considerations

### 1. Prevent Coordinated Attacks

**Problem:** Groups of users coordinating to report good posts

**Solutions:**
- Rate limiting (10 reports/hour per user)
- Trust score weighting
- Time window for reports (reports must be within 24h to count)
- Admin review for threshold posts

### 2. Prevent False Reports

**Problem:** Users reporting posts they disagree with

**Solutions:**
- Track report accuracy (upheld vs rejected)
- Penalize false reporters (trust score reduction)
- Require reason selection
- Admin review for appeals

### 3. Prevent Self-Reporting

**Problem:** Users reporting their own posts to trigger auto-redaction

**Solutions:**
- Block self-reports in controller
- Don't count author's reports in threshold

### 4. Prevent Spam Reports

**Problem:** Automated accounts creating reports

**Solutions:**
- Rate limiting
- CAPTCHA for new accounts
- Trust score requirements
- IP-based limiting

---

## Performance Considerations

### Database Indexes

**Critical indexes for performance:**
```sql
-- Reports table
CREATE INDEX idx_reports_post_resolved ON reports(post_id, resolved);
CREATE INDEX idx_reports_post_reporter ON reports(post_id, reporter_id);
CREATE INDEX idx_reports_created_at ON reports(created_at DESC);

-- Posts table
CREATE INDEX idx_posts_redacted ON posts(redacted);
CREATE INDEX idx_posts_report_count ON posts(report_count DESC);
CREATE INDEX idx_posts_redacted_at ON posts(redacted_at DESC);
```

### Caching Strategy

```ruby
# Cache report counts (5 minute TTL)
def report_count
  Rails.cache.fetch("post:#{id}:report_count", expires_in: 5.minutes) do
    reports.unresolved.count
  end
end

# Cache redaction status (longer TTL, invalidate on update)
def redacted?
  Rails.cache.fetch("post:#{id}:redacted", expires_in: 1.hour) do
    read_attribute(:redacted)
  end
end
```

### Background Jobs

- Auto-redaction: Async job to prevent blocking
- Notifications: Async job for user notifications
- Trust score updates: Async job, run periodically

---

## Proven Solutions

### Inspiration from Real Platforms

#### 1. Reddit's Moderation System

**Features:**
- Community reporting with reasons
- Auto-removal at threshold
- Mod queue for review
- Appeals process

**What we're adopting:**
- Report reasons
- Threshold-based auto-action
- Moderation queue

#### 2. Mastodon's Moderation

**Features:**
- Community-driven moderation
- Instance-level rules
- User blocking/muting
- Content warnings

**What we're adopting:**
- Community self-moderation
- User trust scores

#### 3. Twitter/X Reporting

**Features:**
- Report categories
- Contextual reporting
- Appeal process
- Transparency reports

**What we're adopting:**
- Report categories
- Appeal system
- Audit trail

#### 4. Discord's Auto-Moderation

**Features:**
- Keyword filtering
- Spam detection
- Auto-timeout
- Trust levels

**What we're adopting:**
- Content filtering
- Pattern detection
- Trust scores

---

## Future Enhancements

### Phase 5: Advanced Features (Future)

1. **Machine Learning Detection**
   - Train model on reported content
   - Auto-flag suspicious posts
   - Reduce false positives

2. **Reputation System**
   - Community moderators
   - Trusted user program
   - Moderation badges

3. **Content Warnings**
   - User-set content warnings
   - Auto-detection of sensitive topics
   - Collapsible content

4. **Advanced Analytics**
   - Moderation trends
   - User behavior analysis
   - Effectiveness metrics

5. **Integration with External Services**
   - VirusTotal API
   - Google Safe Browsing
   - Perspective API (toxicity detection)

---

## Testing Strategy

### Unit Tests

```ruby
# spec/models/report_spec.rb
RSpec.describe Report do
  describe "#check_auto_redaction_threshold" do
    it "auto-redacts at threshold" do
      post = create(:post)
      5.times { create(:report, post: post) }

      expect(post.reload.redacted).to be true
    end
  end
end
```

### Integration Tests

```ruby
# spec/features/reporting_spec.rb
RSpec.describe "Reporting", type: :feature do
  it "allows users to report posts" do
    post = create(:post)
    user = create(:user)

    login_as(user)
    visit post_path(post)
    click_button "Report"
    select "Spam", from: "Reason"
    click_button "Submit Report"

    expect(page).to have_content "Report submitted"
  end
end
```

---

## Configuration

### Environment Variables

```bash
# .env
MODERATION_THRESHOLD=5
MODERATION_TIME_WINDOW=86400  # 24 hours in seconds
MODERATION_APPEAL_WINDOW=604800  # 7 days in seconds
GOOGLE_SAFE_BROWSING_API_KEY=your_key_here
ENABLE_CONTENT_FILTERING=true
ENABLE_PROFANITY_FILTER=false
```

### Initializer

```ruby
# config/initializers/moderation.rb
Rails.application.config.moderation = ActiveSupport::OrderedOptions.new
Rails.application.config.moderation.auto_redact_threshold = ENV.fetch('MODERATION_THRESHOLD', 5).to_i
Rails.application.config.moderation.time_window = ENV.fetch('MODERATION_TIME_WINDOW', 86400).to_i
Rails.application.config.moderation.appeal_window = ENV.fetch('MODERATION_APPEAL_WINDOW', 604800).to_i
Rails.application.config.moderation.enable_content_filtering = ENV.fetch('ENABLE_CONTENT_FILTERING', 'true') == 'true'
Rails.application.config.moderation.enable_profanity_filter = ENV.fetch('ENABLE_PROFANITY_FILTER', 'false') == 'true'
```

---

## Conclusion

This comprehensive moderation system provides:

1. ✅ **Post Redaction**: Boolean flag with placeholder display
2. ✅ **Community Reporting**: Report button with auto-redaction at threshold
3. ✅ **Abuse Prevention**: Rate limiting, trust scores, duplicate detection
4. ✅ **Content Safety**: URL checking, content filtering, pattern detection
5. ✅ **Administrative Tools**: Moderation queue, appeals, audit trail

**Next Steps:**
1. Review this proposal
2. Prioritize features
3. Begin Phase 1 implementation

---

**Document Version:** 1.0
**Last Updated:** 2024-11-04
**Author:** Moderation System Proposal

