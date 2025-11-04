# Test Suite Documentation

This project uses RSpec for testing with comprehensive coverage of models, controllers, and features.

## Running Tests

### Run all tests
```bash
bundle exec rspec
```

### Run specific test files
```bash
# Model tests
bundle exec rspec spec/models

# Controller/Request tests
bundle exec rspec spec/requests

# Feature/System tests
bundle exec rspec spec/features

# Specific file
bundle exec rspec spec/models/user_spec.rb
```

### Run with documentation format
```bash
bundle exec rspec --format documentation
```

### Run specific examples
```bash
bundle exec rspec spec/models/user_spec.rb:25
```

## Test Coverage

### Unit Tests (Models)
- **User Model** (`spec/models/user_spec.rb`)
  - Associations (posts, follows, following, followers)
  - Validations (username, description, password)
  - Follow/unfollow functionality
  - Feed posts scope
  - Password encryption

- **Post Model** (`spec/models/post_spec.rb`)
  - Associations (author, parent, replies)
  - Validations (content length)
  - Scopes (timeline, top_level, replies)
  - Reply detection
  - Author name handling
  - Cascade behavior

- **Follow Model** (`spec/models/follow_spec.rb`)
  - Associations (follower, followed)
  - Validations (uniqueness, no self-following)
  - Cascade behavior

### Request Specs (Controllers)
- **PostsController** (`spec/requests/posts_spec.rb`)
  - Index (timeline with filters)
  - Show (post with replies)
  - Create (posts and replies)
  - Authentication requirements

- **UsersController** (`spec/requests/users_spec.rb`)
  - Show (profile display)
  - Edit (settings form)
  - Update (description, password)
  - Destroy (account deletion)
  - Authorization checks

- **FollowsController** (`spec/requests/follows_spec.rb`)
  - Create (follow user)
  - Destroy (unfollow user)
  - Authentication requirements

### Feature Specs (End-to-End)
- **Posts Feature** (`spec/features/posts_feature_spec.rb`)
  - Creating posts
  - Viewing timeline
  - Filtering posts
  - Replying to posts
  - Character counter

- **Users Feature** (`spec/features/users_feature_spec.rb`)
  - Viewing profiles
  - Editing settings
  - Updating password
  - Deleting account
  - Access control

- **Following Feature** (`spec/features/following_feature_spec.rb`)
  - Following users
  - Unfollowing users
  - Timeline integration
  - Follower counts

- **End-to-End** (`spec/features/end_to_end_spec.rb`)
  - Complete user workflows
  - Multiple user interactions
  - Deleted user scenarios
  - Navigation flows

## Test Data

Tests use FactoryBot for creating test data:
- `create(:user)` - Creates a user with random username
- `create(:post)` - Creates a post with random content
- `create(:follow)` - Creates a follow relationship

Traits available:
- `:with_posts` - User with posts
- `:with_description` - User with description
- `:reply` - Post as a reply
- `:top_level` - Top-level post

## Helpers

### Authentication Helper
The `AuthenticationHelper` module provides:
- `login_as(user)` - Logs in a user for tests
- `logout` - Logs out current user

Usage:
```ruby
let(:user) { create(:user) }
before { login_as(user) }
```

## Continuous Integration

To run tests in CI:
```bash
RAILS_ENV=test bundle exec rails db:test:prepare
bundle exec rspec
```

## Test Database

The test database is automatically maintained by RSpec. Run:
```bash
RAILS_ENV=test bundle exec rails db:test:prepare
```

if you need to reset the test database schema.



