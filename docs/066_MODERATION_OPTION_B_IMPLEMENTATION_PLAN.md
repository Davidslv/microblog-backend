# Moderation System - Option B Implementation Plan

> **Pragmatic MVP: Production-Ready Moderation in 2-3 Weeks**
>
> This document provides a comprehensive, TDD-based implementation plan for Option B moderation system with extensibility for future Option C features.

---

## Table of Contents

1. [Overview](#overview)
2. [User Stories](#user-stories)
3. [Architecture Principles](#architecture-principles)
4. [Database Schema](#database-schema)
5. [API Design](#api-design)
6. [Implementation Phases](#implementation-phases)
7. [Testing Strategy](#testing-strategy)
8. [Extensibility for Option C](#extensibility-for-option-c)
9. [SOLID Principles Application](#solid-principles-application)
10. [Three-Layer Architecture Integration](#three-layer-architecture-integration)

---

## Overview

### Option B Features (Pragmatic MVP)

- ✅ Post redaction (boolean flag)
- ✅ Basic reporting with rate limiting (10 reports/hour)
- ✅ Auto-redaction at 5 reports
- ✅ Basic admin system (admin flag on users, simple API endpoints)
- ✅ Basic audit trail (log reports, redactions, admin actions)
- ✅ Duplicate report prevention
- ✅ Self-report prevention
- ✅ Silent redaction (users don't know their posts were redacted)

### Timeline

- **Total:** 10-14 days (2 weeks)
- **Phase 1 (Week 1):** Core reporting + rate limiting + auto-redaction
- **Phase 2 (Week 2):** Admin system + audit trail + frontend

### Success Criteria

- Users can report posts
- Posts auto-redact at 5 reports
- Rate limiting prevents abuse (10 reports/hour)
- Admins can manually redact/unredact posts
- Redacted posts are hidden from users (silent redaction)
- All actions are logged in audit trail
- Frontend provides intuitive reporting UI

---

## User Stories

### Core Reporting

**US-1: As a user, I want to report inappropriate posts so that the community stays safe.**
- **Acceptance Criteria:**
  - User can click "Report" button on any post
  - Report modal/form appears
  - User can submit report
  - Report is saved to database
  - User receives confirmation
  - User cannot report same post twice
  - User cannot report their own posts

**US-2: As a user, I want redacted posts to be hidden from me so I don't see inappropriate content.**
- **Acceptance Criteria:**
  - Redacted posts are completely hidden from user feeds
  - Redacted posts do not appear in post lists
  - Redacted posts do not appear in search results
  - Post author cannot see their own redacted posts (silent redaction)
  - Replies to redacted posts are also hidden

**US-3: As a user, I want to be rate-limited on reports so the system isn't abused.**
- **Acceptance Criteria:**
  - User can report maximum 10 posts per hour
  - After 10 reports, user sees "Rate limit exceeded" message
  - Rate limit resets after 1 hour
  - Rate limit is per-user (not per-IP)

### Auto-Redaction

**US-4: As the system, I want to automatically redact posts when they receive 5 reports so bad content is removed quickly.**
- **Acceptance Criteria:**
  - Post is automatically redacted when it reaches 5 unique reports
  - Auto-redaction happens immediately (synchronous)
  - Auto-redaction is logged in audit trail
  - Post author is not notified (silent redaction)
  - Redacted posts are filtered out of all user-facing queries

### Admin System

**US-5: As an admin, I want to manually redact posts so I can moderate content that hasn't reached 5 reports.**
- **Acceptance Criteria:**
  - Admin can access redaction API endpoint
  - Admin can redact any post
  - Admin can unredact any post
  - All admin actions are logged

**US-6: As an admin, I want to see all reports for a post so I can make informed moderation decisions.**
- **Acceptance Criteria:**
  - Admin can query reports for a specific post
  - Admin can see report count
  - Admin can see report timestamps
  - Admin can see reporter IDs (for audit)

### Audit Trail

**US-7: As the system, I want to log all moderation actions so we have a record for legal/compliance purposes.**
- **Acceptance Criteria:**
  - All reports are logged with timestamp, user, post
  - All redactions are logged (auto and manual)
  - All unredactions are logged
  - All admin actions are logged
  - Logs are immutable (cannot be deleted)

---

## Architecture Principles

### SOLID Principles

#### Single Responsibility Principle (SRP)

- **ReportService:** Handles report creation logic
- **RedactionService:** Handles redaction/unredaction logic
- **AuditLogger:** Handles all audit trail logging
- **ModerationPolicy:** Handles authorization (who can moderate)
- **PostFilter:** Handles filtering redacted posts from queries

#### Open/Closed Principle (OCP)

- Services are designed to be extended, not modified
- Future Option C features (trust scores, content safety) can be added via:
  - Strategy pattern for report weighting
  - Decorator pattern for content checking
  - Observer pattern for notifications

#### Liskov Substitution Principle (LSP)

- All services implement consistent interfaces
- Future implementations (e.g., weighted reporting) can substitute base implementations

#### Interface Segregation Principle (ISP)

- Services have focused, minimal interfaces
- Controllers only depend on what they need

#### Dependency Inversion Principle (DIP)

- Controllers depend on service abstractions, not implementations
- Services can be easily mocked in tests
- Future Option C features can inject new services without changing controllers

### Extensibility Design

#### For Option C: Trust Scores

- **Current:** All reports have equal weight
- **Future:** Inject `ReportWeightCalculator` service
- **Design:** `ReportService` accepts optional `weight_calculator` parameter
- **Migration:** Add `trust_score` column to `users` table (nullable)

#### For Option C: Content Safety

- **Current:** No content checking
- **Future:** Inject `ContentSafetyChecker` service
- **Design:** `RedactionService` accepts optional `content_checker` parameter
- **Migration:** Add `content_safety_checked` boolean to `posts` table

#### For Option C: Admin Dashboard

- **Current:** Simple API endpoints
- **Future:** Add `AdminDashboardController` with full UI
- **Design:** Reuse existing services, add new controller layer

#### For Option C: Background Jobs

- **Current:** Synchronous processing
- **Future:** Move auto-redaction to background job
- **Design:** Extract `AutoRedactionJob` that uses `RedactionService`
- **Migration:** No schema changes needed

---

## Database Schema

### New Tables

#### `reports`

```ruby
create_table :reports do |t|
  t.references :post, null: false, foreign_key: true
  t.references :reporter, null: false, foreign_key: { to_table: :users }
  t.timestamps

  t.index [:post_id, :reporter_id], unique: true, name: "index_reports_on_post_and_reporter"
  t.index [:post_id, :created_at]
  t.index [:reporter_id, :created_at]
end
```

**Purpose:** Track user reports on posts
**Constraints:** Unique (post_id, reporter_id) to prevent duplicate reports
**Extensibility:** Can add `reason` column later, `trust_weight` for Option C

#### `moderation_audit_logs`

```ruby
create_table :moderation_audit_logs do |t|
  t.string :action, null: false # report, redact, unredact
  t.references :post, null: false, foreign_key: true
  t.references :user, foreign_key: true # actor (reporter, admin, etc.)
  t.references :admin, foreign_key: { to_table: :users } # if admin action
  t.jsonb :metadata # flexible storage for action-specific data
  t.timestamps

  t.index [:post_id, :created_at]
  t.index [:user_id, :created_at]
  t.index [:action, :created_at]
end
```

**Purpose:** Immutable audit trail of all moderation actions
**Extensibility:** JSONB metadata allows storing any additional data without schema changes

### Modified Tables

#### `posts`

```ruby
add_column :posts, :redacted, :boolean, default: false, null: false
add_column :posts, :redacted_at, :datetime
add_column :posts, :redaction_reason, :string # auto, manual, appeal_approved

add_index :posts, :redacted
add_index :posts, [:redacted, :created_at]
```

**Purpose:** Track post redaction status
**Extensibility:** Can add `content_safety_checked` boolean for Option C

#### `users`

```ruby
add_column :users, :admin, :boolean, default: false, null: false

add_index :users, :admin
```

**Purpose:** Mark admin users
**Extensibility:** Can add `trust_score` decimal column for Option C

---

## API Design

### Endpoints

#### Reporting

**POST /api/v1/posts/:post_id/report**
- **Auth:** Required
- **Rate Limit:** 10/hour per user
- **Request Body:** `{}` (no body needed initially, can add `reason` later)
- **Response:** `{ "message": "Report submitted" }`
- **Errors:**
  - 401: Unauthorized
  - 404: Post not found
  - 422: Already reported, Cannot report own post, Rate limit exceeded

#### Redaction (Admin Only)

**POST /api/v1/posts/:post_id/redact**
- **Auth:** Required (admin only)
- **Request Body:** `{ "reason": "manual" }` (optional)
- **Response:** `{ "post": { ...post_json... } }`
- **Errors:**
  - 401: Unauthorized
  - 403: Forbidden (not admin)
  - 404: Post not found

**DELETE /api/v1/posts/:post_id/redact**
- **Auth:** Required (admin only)
- **Response:** `{ "post": { ...post_json... } }`
- **Errors:**
  - 401: Unauthorized
  - 403: Forbidden (not admin)
  - 404: Post not found

#### Reports (Admin Only)

**GET /api/v1/posts/:post_id/reports** (Admin Only)
- **Auth:** Required (admin only)
- **Response:** `{ "reports": [{ "id": 1, "reporter": {...}, "created_at": "..." }], "count": 5 }`
- **Errors:**
  - 401: Unauthorized
  - 403: Forbidden (not admin)
  - 404: Post not found

### Updated Endpoints

#### GET /api/v1/posts (Updated)

**Response includes redaction status:**
```json
{
  "posts": [
    {
      "id": 1,
      "content": "Hello world",
      "redacted": false,
      "author": {...}
    },
    {
      "id": 2,
      "content": null,
      "redacted": true,
      "redaction_reason": "auto",
      "author": {...}
    }
  ]
}
```

#### GET /api/v1/posts/:id (Updated)

**Response excludes redacted posts (silent redaction):**
- Redacted posts return 404 (not found) to regular users
- Admins can see redacted posts with `?include_redacted=true` query param

---

## Implementation Phases

### Phase 1: Core Reporting + Rate Limiting + Auto-Redaction (Week 1)

#### Day 1-2: Database & Models (TDD)

**Tasks:**
1. Write tests for `Report` model
2. Create `reports` migration
3. Implement `Report` model with validations
4. Write tests for `Post` model redaction
5. Add `redacted` column to `posts` migration
6. Update `Post` model with redaction methods
7. Write tests for report uniqueness (post + reporter)
8. Write tests for self-report prevention

**Files:**
- `db/migrate/YYYYMMDDHHMMSS_add_reports_table.rb`
- `db/migrate/YYYYMMDDHHMMSS_add_redaction_to_posts.rb`
- `app/models/report.rb`
- `spec/models/report_spec.rb`
- `spec/models/post_spec.rb` (update)

**SOLID Application:**
- `Report` model: Single responsibility (data persistence)
- Validations: Business rules in model

#### Day 3-4: Services & Business Logic (TDD)

**Tasks:**
1. Write tests for `ReportService`
2. Implement `ReportService` (create report, check duplicates, check self-report)
3. Write tests for `RedactionService`
4. Implement `RedactionService` (redact, unredact, check threshold)
5. Write tests for `AuditLogger`
6. Implement `AuditLogger` (log all actions)
7. Write integration tests for auto-redaction flow

**Files:**
- `app/services/report_service.rb`
- `app/services/redaction_service.rb`
- `app/services/audit_logger.rb`
- `spec/services/report_service_spec.rb`
- `spec/services/redaction_service_spec.rb`
- `spec/services/audit_logger_spec.rb`
- `spec/integration/auto_redaction_spec.rb`

**SOLID Application:**
- `ReportService`: Single responsibility (report creation)
- `RedactionService`: Single responsibility (redaction logic)
- `AuditLogger`: Single responsibility (logging)
- Services depend on abstractions (models), not implementations

**Extensibility:**
- `ReportService` accepts optional `weight_calculator` (for Option C trust scores)
- `RedactionService` accepts optional `content_checker` (for Option C content safety)

#### Day 5: Rate Limiting & Controllers (TDD)

**Tasks:**
1. Write tests for rate limiting (Rack::Attack)
2. Configure Rack::Attack for reports (10/hour per user)
3. Write tests for `ReportsController`
4. Implement `ReportsController` (create report)
5. Write tests for `PostsController` updates (include redaction status)
6. Update `PostsController` to include redaction in JSON

**Files:**
- `config/initializers/rack_attack.rb` (update)
- `app/controllers/api/v1/reports_controller.rb`
- `spec/requests/api/v1/reports_spec.rb`
- `spec/requests/api/v1/posts_spec.rb` (update)

**SOLID Application:**
- Controller: Thin layer, delegates to services
- Rate limiting: Separate concern (Rack::Attack)

#### Day 6-7: Integration & Edge Cases (TDD)

**Tasks:**
1. Write integration tests for full reporting flow
2. Write edge case tests (deleted posts, deleted users, concurrent reports)
3. Write performance tests (many reports on same post)
4. Fix any bugs found
5. Code review and refactoring

**Files:**
- `spec/integration/reporting_flow_spec.rb`
- `spec/edge_cases/moderation_edge_cases_spec.rb`

---

### Phase 2: Admin System + Audit Trail + Frontend (Week 2)

#### Day 8-9: Admin System (TDD)

**Tasks:**
1. Write tests for admin flag on users
2. Add `admin` column to `users` migration
3. Update `User` model with admin methods
4. Write tests for `ModerationPolicy` (authorization)
5. Implement `ModerationPolicy` (who can moderate)
6. Write tests for admin redaction endpoints
7. Implement admin redaction endpoints
8. Write tests for admin reports endpoint
9. Implement admin reports endpoint
10. Write tests for filtering redacted posts
11. Implement `PostFilter` service to exclude redacted posts

**Files:**
- `db/migrate/YYYYMMDDHHMMSS_add_admin_to_users.rb`
- `app/models/user.rb` (update)
- `app/policies/moderation_policy.rb`
- `app/services/post_filter.rb`
- `app/controllers/api/v1/admin/posts_controller.rb` (or add to existing)
- `spec/models/user_spec.rb` (update)
- `spec/policies/moderation_policy_spec.rb`
- `spec/services/post_filter_spec.rb`
- `spec/requests/api/v1/admin/posts_spec.rb`

**SOLID Application:**
- `ModerationPolicy`: Single responsibility (authorization)
- `PostFilter`: Single responsibility (filtering logic)
- Policy pattern: Separates authorization from business logic

#### Day 10-11: Audit Trail & Silent Redaction (TDD)

**Tasks:**
1. Write tests for `ModerationAuditLog` model
2. Create `moderation_audit_logs` migration
3. Implement `ModerationAuditLog` model
4. Update `AuditLogger` to use new model
5. Write tests for audit logging in all services
6. Integrate audit logging into all services
7. Write tests for audit log queries (admin)
8. Implement audit log query endpoint (optional, for admin)

**Files:**
- `db/migrate/YYYYMMDDHHMMSS_add_moderation_audit_logs_table.rb`
- `app/models/moderation_audit_log.rb`
- `app/services/audit_logger.rb` (update)
- `app/models/post.rb` (add scopes for redacted posts)
- `app/controllers/api/v1/posts_controller.rb` (update to filter redacted)
- `spec/models/moderation_audit_log_spec.rb`
- `spec/services/audit_logger_spec.rb` (update)
- `spec/models/post_spec.rb` (update with redaction scopes)
- `spec/requests/api/v1/posts_spec.rb` (update with redaction tests)

**SOLID Application:**
- `AuditLogger`: Single responsibility (logging)
- Observer pattern: Services notify logger without tight coupling
- `PostFilter`: Single responsibility (query filtering)

#### Day 12-13: Frontend Components (TDD)

**Tasks:**
1. Write tests for `ReportButton` component
2. Implement `ReportButton` component
3. Write tests for `ReportModal` component
4. Implement `ReportModal` component
5. Write tests for redacted post filtering (posts don't appear)
6. Update `PostList` component to handle missing posts gracefully
7. Write tests for error handling (rate limits, duplicates)
8. Implement error handling in components
9. Write integration tests for frontend flows

**Files:**
- `microblog-frontend/src/components/ReportButton.jsx`
- `microblog-frontend/src/components/ReportModal.jsx`
- `microblog-frontend/src/components/PostList.jsx` (update)
- `microblog-frontend/src/components/__tests__/ReportButton.test.jsx`
- `microblog-frontend/src/components/__tests__/ReportModal.test.jsx`
- `microblog-frontend/src/components/__tests__/PostList.test.jsx`

**SOLID Application:**
- Components: Single responsibility (UI rendering)
- Props: Interface segregation (only pass needed props)

#### Day 14: Integration & Testing (TDD)

**Tasks:**
1. Write end-to-end tests for full moderation flow
2. Write tests for admin workflows
3. Write tests for silent redaction (posts disappear)
4. Performance testing (many reports, filtering)
5. Security testing (unauthorized access, rate limit bypass)
6. Fix bugs and refactor

**Files:**
- `spec/features/moderation_end_to_end_spec.rb`
- `spec/features/admin_moderation_spec.rb`
- `spec/features/silent_redaction_spec.rb`
- `microblog-frontend/e2e/moderation.spec.js`

---


---

## Testing Strategy

### Test Pyramid

```
        /\
       /  \
      / E2E \          (10%)
     /------\
    /        \
   /Integration\       (20%)
  /------------\
 /              \
/   Unit Tests   \    (70%)
------------------
```

### Unit Tests (70%)

**Models:**
- `Report` model: validations, associations, scopes
- `ModerationAuditLog` model: validations, associations
- `Post` model: redaction methods, redacted scopes, filtering
- `User` model: admin methods

**Services:**
- `ReportService`: create report, duplicate check, self-report check
- `RedactionService`: redact, unredact, threshold check
- `PostFilter`: filter redacted posts from queries
- `AuditLogger`: log all action types

**Policies:**
- `ModerationPolicy`: admin checks, authorization

**Components (Frontend):**
- `ReportButton`: rendering, click handlers
- `ReportModal`: form submission, error display
- `PostList`: filtering redacted posts (posts simply don't appear)

### Integration Tests (20%)

**Backend:**
- Report creation → auto-redaction flow
- Silent redaction (posts filtered from queries)
- Rate limiting integration
- Audit logging integration

**Frontend:**
- Report button → modal → API call → success
- Post disappears after redaction (silent redaction)
- Error handling (rate limits, duplicates)

### E2E Tests (10%)

**Playwright:**
- Full user journey: report post → post disappears (silent redaction)
- Admin journey: view reports → redact post → unredact post
- Error scenarios: rate limits, duplicate reports, self-reports

### Test Coverage Goals

- **Models:** 100% coverage
- **Services:** 95%+ coverage
- **Controllers:** 90%+ coverage
- **Components:** 85%+ coverage
- **E2E:** Critical paths only

### TDD Workflow

1. **Red:** Write failing test
2. **Green:** Write minimal code to pass
3. **Refactor:** Improve code while keeping tests green
4. **Repeat:** Move to next test

### Test Data

**Factories:**
- `report` factory
- `moderation_audit_log` factory
- Update `post` factory to support redaction
- Update `user` factory to support admin flag

**Fixtures:**
- Test data for edge cases
- Performance test data (many reports)

---

## Extensibility for Option C

### Trust Scores (Future)

**Current Design:**
- All reports have equal weight
- `ReportService` checks threshold: `reports.count >= 5`
- Redacted posts are filtered from all user queries (silent redaction)

**Future Extension:**
```ruby
# Add to users table
add_column :users, :trust_score, :decimal, precision: 5, scale: 2, default: 1.0

# New service
class TrustScoreCalculator
  def calculate_weight(user)
    user.trust_score || 1.0
  end
end

# Update ReportService
class ReportService
  def initialize(weight_calculator: TrustScoreCalculator.new)
    @weight_calculator = weight_calculator
  end

  def check_threshold(post)
    weighted_count = post.reports.sum { |r| @weight_calculator.calculate_weight(r.reporter) }
    weighted_count >= 5.0
  end
end
```

**Migration Path:**
1. Add `trust_score` column (nullable, default 1.0)
2. Backfill existing users with default score
3. Inject `TrustScoreCalculator` into `ReportService`
4. No breaking changes to API
5. Silent redaction behavior unchanged

### Content Safety (Future)

**Current Design:**
- No content checking
- Redaction based on reports only

**Future Extension:**
```ruby
# New service
class ContentSafetyChecker
  def check_urls(post)
    # Google Safe Browsing API
  end

  def check_spam(post)
    # Pattern matching
  end
end

# Update RedactionService
class RedactionService
  def initialize(content_checker: nil)
    @content_checker = content_checker
  end

  def should_redact?(post)
    return true if post.reports.count >= 5
    return true if @content_checker&.check_urls(post) == :unsafe
    return true if @content_checker&.check_spam(post) == :spam
    false
  end
end
```

**Migration Path:**
1. Add `content_safety_checked` boolean to posts (nullable)
2. Inject `ContentSafetyChecker` into `RedactionService`
3. Background job to check existing posts
4. No breaking changes to API

### Admin Dashboard (Future)

**Current Design:**
- Simple API endpoints
- Admin uses API directly or basic UI

**Future Extension:**
- Add `AdminDashboardController` with full UI
- Reuse existing services (`ReportService`, `RedactionService`)
- Add analytics endpoints (report counts, redaction stats)
- No changes to core services needed

### Background Jobs (Future)

**Current Design:**
- Auto-redaction is synchronous (in request)

**Future Extension:**
```ruby
# New job
class AutoRedactionJob < ApplicationJob
  def perform(post_id)
    post = Post.find(post_id)
    RedactionService.new.auto_redact_if_threshold(post)
  end
end

# Update ReportService
class ReportService
  def create_report(post, reporter)
    # ... create report ...
    if check_threshold(post) && !post.redacted?
      AutoRedactionJob.perform_later(post.id) # Async
    end
  end
end
```

**Migration Path:**
1. Extract auto-redaction logic to job
2. Update `ReportService` to enqueue job
3. No breaking changes to API

---

## SOLID Principles Application

### Single Responsibility Principle (SRP)

**Services:**
- `ReportService`: Only handles report creation and validation
- `RedactionService`: Only handles redaction/unredaction logic
- `PostFilter`: Only handles filtering redacted posts from queries
- `AuditLogger`: Only handles logging

**Models:**
- `Report`: Only data persistence for reports
- `ModerationAuditLog`: Only data persistence for audit logs

**Controllers:**
- `ReportsController`: Only HTTP handling for reports
- `Admin::PostsController`: Only HTTP handling for admin actions
- `PostsController`: Updated to filter redacted posts

### Open/Closed Principle (OCP)

**Extensibility Points:**
- `ReportService` accepts `weight_calculator` (for trust scores)
- `RedactionService` accepts `content_checker` (for content safety)
- Services can be extended without modification

**Example:**
```ruby
# Current
ReportService.new.create_report(post, user)

# Future (Option C)
ReportService.new(
  weight_calculator: TrustScoreCalculator.new
).create_report(post, user)
```

### Liskov Substitution Principle (LSP)

**Interfaces:**
- All services implement consistent error handling
- All services return predictable results
- Future implementations can substitute base implementations

**Example:**
```ruby
# Base
class ReportService
  def create_report(post, reporter)
    # ...
  end
end

# Future (Option C)
class WeightedReportService < ReportService
  def create_report(post, reporter)
    # Enhanced with trust scores
    # Still returns same structure
  end
end
```

### Interface Segregation Principle (ISP)

**Minimal Interfaces:**
- Controllers only depend on what they need
- Services have focused methods
- No fat interfaces

**Example:**
```ruby
# Good: Focused interface
class ReportService
  def create_report(post, reporter)
  end

  def can_report?(post, reporter)
  end
end

# Bad: Fat interface (don't do this)
class ReportService
  def create_report(...)
  def approve_report(...)
  def reject_report(...)
  def list_reports(...)
  # Too many responsibilities
end
```

### Dependency Inversion Principle (DIP)

**Abstractions:**
- Controllers depend on service abstractions
- Services can be easily mocked in tests
- Future implementations can be injected

**Example:**
```ruby
# Controller depends on abstraction
class ReportsController < BaseController
  def create
    ReportService.new.create_report(...)
  end
end

# Test mocks abstraction
allow(ReportService).to receive(:new).and_return(mock_service)
```

---

## Three-Layer Architecture Integration

### Presentation Layer (Frontend)

**Components:**
- `ReportButton`: UI for reporting
- `ReportModal`: Form for report submission
- `AppealButton`: UI for appealing
- `AppealModal`: Form for appeal submission
- `Post`: Updated to show redacted state

**Services:**
- `moderation.js`: API client for moderation endpoints

**State Management:**
- React Context or local state
- No business logic in frontend

### Application Layer (Backend API)

**Controllers:**
- `Api::V1::ReportsController`: Report endpoints
- `Api::V1::AppealsController`: Appeal endpoints
- `Api::V1::Admin::PostsController`: Admin endpoints

**Services:**
- `ReportService`: Business logic for reports
- `RedactionService`: Business logic for redactions
- `AppealService`: Business logic for appeals
- `AuditLogger`: Logging service

**Policies:**
- `ModerationPolicy`: Authorization logic

**Models:**
- `Report`: Data model
- `Appeal`: Data model
- `ModerationAuditLog`: Data model
- `Post`: Updated with redaction
- `User`: Updated with admin flag

### Data Layer (Database)

**Tables:**
- `reports`: Report data
- `moderation_audit_logs`: Audit trail
- `posts`: Updated with redaction columns
- `users`: Updated with admin column

**Indexes:**
- Optimized for common queries (reports by post, redacted posts filtering)

### Data Flow

**Report Flow:**
```
Frontend (ReportButton)
  → API POST /api/v1/posts/:id/report
  → ReportsController#create
  → ReportService#create_report
  → Report.save
  → RedactionService#check_threshold
  → Post.update(redacted: true) if threshold met
  → AuditLogger#log
  → Response JSON
  → Frontend updates UI (post disappears on next refresh)
```

**Silent Redaction Flow:**
```
User requests posts
  → API GET /api/v1/posts
  → PostsController#index
  → PostFilter#filter_redacted (excludes redacted posts)
  → Response JSON (redacted posts not included)
  → Frontend displays posts (redacted posts never appear)
```

**Admin Unredaction Flow:**
```
Admin unredacts post
  → API DELETE /api/v1/posts/:id/redact
  → Admin::PostsController#unredact
  → RedactionService#unredact
  → Post.update(redacted: false)
  → AuditLogger#log
  → Response JSON
  → Post becomes visible again to users
```

---

## Risk Mitigation

### Technical Risks

**Risk:** Database migration locks on large `posts` table
**Mitigation:**
- Use `add_column` with `default: false` (fast, no lock)
- Add index in separate migration
- Test on staging with production-like data

**Risk:** Rate limiting cache issues
**Mitigation:**
- Use existing Rack::Attack setup (Solid Cache)
- Test rate limiting across multiple instances
- Monitor cache performance

**Risk:** Concurrent report race conditions
**Mitigation:**
- Database unique constraint on (post_id, reporter_id)
- Use database transactions
- Test concurrent report scenarios

### Business Risks

**Risk:** False redactions damage user trust
**Mitigation:**
- Admin can manually unredact (silent unredaction)
- Audit trail provides transparency
- Admin reviews reports before manual redaction

**Risk:** Abuse of reporting system
**Mitigation:**
- Rate limiting (10 reports/hour)
- Duplicate prevention
- Self-report prevention
- Future: Trust scores (Option C)

### Operational Risks

**Risk:** Support burden from users asking about missing posts
**Mitigation:**
- Silent redaction (users don't know posts were redacted)
- Admin can unredact if needed
- Support can check audit logs if users inquire

**Risk:** Legal/compliance issues
**Mitigation:**
- Comprehensive audit trail
- Immutable logs
- Admin access controls

---

## Success Metrics

### Technical Metrics

- **Test Coverage:** >90% for services, >85% for controllers
- **API Response Time:** <100ms for report creation
- **Database Queries:** <5 queries per report creation
- **Rate Limiting:** 100% effective (no bypasses)

### Business Metrics

- **False Positive Rate:** <5% (admin unredactions / total redactions)
- **Admin Response Time:** <24 hours (for manual reviews)
- **User Satisfaction:** >80% (survey)
- **Abuse Prevention:** <1% of reports are spam/abuse
- **Silent Redaction Effectiveness:** 100% (redacted posts never appear to users)

### Operational Metrics

- **Support Tickets:** <5% of redactions result in support tickets (silent redaction reduces inquiries)
- **Admin Time:** <5 minutes per manual redaction review
- **System Uptime:** >99.9%

---

## Next Steps After Approval

1. **Create TODO list** from this plan
2. **Set up project tracking** (GitHub issues, milestones)
3. **Create feature branch** (`feature/moderation-option-b`)
4. **Start Phase 1, Day 1:** Write first test for `Report` model
5. **Follow TDD workflow:** Red → Green → Refactor
6. **Daily standups:** Review progress, blockers
7. **Weekly reviews:** Assess timeline, adjust if needed

---

**Document Version:** 1.0
**Last Updated:** 2024-11-04
**Author:** Implementation Plan
**Based on:** 065_MODERATION_OPTIONS_CRITICAL_ANALYSIS.md (Option B)

