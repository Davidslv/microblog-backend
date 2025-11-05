# Documentation Index

This directory contains all documentation for the microblog application. Documents are numbered chronologically by creation date to show the evolution of the project.

## 📚 Reading Order (Logical Flow)

For a comprehensive understanding, read documents in this order:

### 0. Start Here (Educational Overview) ⭐ NEW
- **045_EDUCATIONAL_CASE_STUDY.md** - **Complete educational case study for junior engineers** - Explains everything implemented in this codebase, from database design to horizontal scaling, perfect for learning production-grade Rails development

### 1. Project Overview & Setup
- **001_DATABASE_DIAGRAM.md** - Database schema and relationships
- **002_DEVELOPMENT.md** - Development setup and guidelines
- **003_IMPLEMENTATION_PLAN.md** - Initial implementation plan

### 2. Performance Analysis & Testing
- **004_PERFORMANCE_ANALYSIS.md** - Initial performance analysis (10k users scenario)
- **005_LOAD_TESTING.md** - Load testing methodology and setup
- **006_MONITORING_GUIDE.md** - How to monitor system performance

### 3. Performance Optimizations
- **007_PAGINATION.md** - Cursor-based pagination implementation
- **008_WRK_RESULTS_EXPLANATION.md** - Initial wrk test results
- **009_TEST_SCRIPT_ANALYSIS.md** - Load test script improvements
- **010_DATABASE_OPTIMIZATION.md** - Composite indexes and query optimization
- **011_WRK_RESULTS_AFTER_OPTIMIZATION.md** - Results after query optimization
- **012_FEED_QUERY_OPTIMIZATION.md** - Feed query JOIN optimization

### 4. Database & Infrastructure
- **013_WRK_RESULTS_POSTGRESQL.md** - Results with PostgreSQL
- **014_POSTGRESQL_SETUP.md** - PostgreSQL migration guide
- **015_WRK_RESULTS_AFTER_TUNING.md** - Results after connection pool tuning
- **016_PG_STAT_STATEMENTS.md** - Query performance monitoring setup
- **026_SOLID_QUEUE_SETUP.md** - Solid Queue setup and troubleshooting
- **034_READ_REPLICAS_SETUP.md** - Read replicas configuration for production
- **035_BIN_JOBS_SEGFAULT_ISSUE.md** - bin/jobs segfault issue and workaround

### 5. Query Analysis & Scaling
- **017_ARCHITECTURE_AND_FEED_PROPOSALS.md** - Architecture analysis and feed proposals
- **018_QUERY_PLAN_EXPLANATION.md** - Small scale query plan (257 followers)
- **019_QUERY_PLAN_SCALE_ANALYSIS.md** - Medium scale (14,883 followers)
- **020_QUERY_PLAN_LARGE_SCALE.md** - Large scale (49,601 followers)
- **021_QUERY_PLAN_VERY_LARGE_SCALE.md** - Very large scale (99,062 followers)

### 6. Architecture & Scale
- **022_PERFORMANCE_AT_SCALE.md** - Performance at 1M user scale

### 7. Counter Cache Optimization
- **023_COUNTER_CACHE_INCREMENT_LOGIC.md** - How counter caches are maintained
- **024_WHY_NOT_BACKFILL_IN_MIGRATIONS.md** - Why not to backfill in migrations
- **025_BACKFILL_COUNTER_CACHES.md** - Counter cache backfilling guide

## 📋 Quick Reference by Topic

### Performance
- `004_PERFORMANCE_ANALYSIS.md` - Initial analysis
- `022_PERFORMANCE_AT_SCALE.md` - 1M user scale analysis
- `007_PAGINATION.md` - Pagination optimization
- `008_DATABASE_OPTIMIZATION.md` - Database indexes
- `009_FEED_QUERY_OPTIMIZATION.md` - Feed query optimization

### Testing & Monitoring
- `005_LOAD_TESTING.md` - Load testing setup
- `006_MONITORING_GUIDE.md` - Monitoring tools
- `010_TEST_SCRIPT_ANALYSIS.md` - Test script fixes
- `013-016_WRK_RESULTS_*.md` - Load test results

### Database
- `011_POSTGRESQL_SETUP.md` - PostgreSQL setup
- `012_PG_STAT_STATEMENTS.md` - Query monitoring
- `017-020_QUERY_PLAN_*.md` - Query plan analysis
- `026_SOLID_QUEUE_SETUP.md` - Solid Queue setup
- `034_READ_REPLICAS_SETUP.md` - Read replicas setup
- `035_BIN_JOBS_SEGFAULT_ISSUE.md` - bin/jobs segfault issue

### Architecture
- `021_ARCHITECTURE_AND_FEED_PROPOSALS.md` - Architecture proposals

### Optimization
- `023_COUNTER_CACHE_INCREMENT_LOGIC.md` - Counter cache logic
- `024_WHY_NOT_BACKFILL_IN_MIGRATIONS.md` - Migration best practices
- `025_BACKFILL_COUNTER_CACHES.md` - Backfilling guide

## 🆕 Latest Documents

The most recent documents added (in reverse chronological order):

1. **045_EDUCATIONAL_CASE_STUDY.md** - Complete educational case study for junior engineers (Nov 4)
2. **044_MODERATION_DOCUMENTS_COMPARISON.md** - Comparison of moderation system proposals
3. **043_MODERATION_IDEOLOGY.md** - Strategic moderation approach
4. **042_MODERATION_SYSTEM_PROPOSAL.md** - Technical moderation implementation proposal
5. **041_ADMIN_DASHBOARD_ARCHITECTURE_PROPOSAL.md** - Admin dashboard architecture options

## 📝 Document Naming Convention

Documents are numbered chronologically by creation date:
- `001_*` - First document created
- `002_*` - Second document created
- ... and so on

This allows you to:
- See the evolution of the project
- Know which documents were added most recently
- Follow a logical reading order

## 🔍 Finding Information

- **New to the codebase?** → Start with `045_EDUCATIONAL_CASE_STUDY.md` for comprehensive overview
- **Performance issues?** → Start with `004_PERFORMANCE_ANALYSIS.md` or `022_PERFORMANCE_AT_SCALE.md`
- **Load testing?** → `005_LOAD_TESTING.md` and `006_MONITORING_GUIDE.md`
- **Database optimization?** → `008_DATABASE_OPTIMIZATION.md` and `009_FEED_QUERY_OPTIMIZATION.md`
- **Query performance?** → `017-020_QUERY_PLAN_*.md` series
- **Counter cache?** → `023-025_*` documents
- **Fan-out on write?** → `033_FAN_OUT_ON_WRITE_IMPLEMENTATION.md`
- **Rate limiting?** → `031_RATE_LIMITING_IMPLEMENTATION.md`
- **Horizontal scaling?** → `036_HORIZONTAL_SCALING.md`
- **Read replicas?** → `034_READ_REPLICAS_SETUP.md`
- **Solid Queue issues?** → `026_SOLID_QUEUE_SETUP.md` or `035_BIN_JOBS_SEGFAULT_ISSUE.md`
- **Architecture?** → `021_ARCHITECTURE_AND_FEED_PROPOSALS.md`
- **Admin dashboard?** → `041_ADMIN_DASHBOARD_ARCHITECTURE_PROPOSAL.md`
- **Moderation system?** → `042_MODERATION_SYSTEM_PROPOSAL.md` and `043_MODERATION_IDEOLOGY.md`

