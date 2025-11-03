# Development Guide

## Quick Start

1. **Setup the database:**
   ```bash
   bin/rails db:migrate
   ```

2. **Start the server:**
   ```bash
   bin/dev
   ```

3. **Create test users (in Rails console):**
   ```ruby
   # Open console: bin/rails console

   # Create users
   user1 = User.create!(username: "alice", password: "password123", description: "Hello, I'm Alice!")
   user2 = User.create!(username: "bob", password: "password123", description: "Bob here!")
   user3 = User.create!(username: "charlie", password: "password123")

   # Create posts
   user1.posts.create!(content: "My first microblog post! This is exciting.")
   user2.posts.create!(content: "Just joined this platform, looks cool!")
   user3.posts.create!(content: "Testing the microblog functionality.")

   # Follow relationships
   user1.follow(user2)
   user1.follow(user3)
   user2.follow(user1)
   ```

4. **Simulate being logged in (in Rails console):**
   ```ruby
   # To simulate being logged in as a user, set the session in the console:
   # Note: This needs to be done in the Rails console attached to the running server,
   # or you can manually set session[:user_id] in ApplicationController

   # Alternative: In the Rails console, you can manually update the session
   # For development, you can add a route to set the user:
   ```

5. **Set session manually (easier method):**
   In your browser, you can add a temporary route or use the Rails console:

   ```ruby
   # In bin/rails console:
   # Create a helper script or add this to ApplicationController temporarily:
   ```

## Manual Session Setup (For Development)

Since authentication is deferred, you can set `session[:user_id]` manually:

**Option 1: Via Rails Console (if using console in same process)**
- This is tricky as the console session is separate from web requests

**Option 2: Add a temporary route (recommended for now)**
Add to `config/routes.rb`:
```ruby
# Temporary dev route - remove before production!
get '/dev/login/:user_id', to: 'application#dev_login'
```

Add to `ApplicationController`:
```ruby
def dev_login
  session[:user_id] = params[:user_id]
  redirect_to root_path, notice: "Logged in as user #{params[:user_id]}"
end
```

**Option 3: Use browser console**
Open browser DevTools console and run:
```javascript
// Set a cookie (if needed)
// Or add a bookmarklet that sets session
```

## Features Implemented

✅ **Database Schema**
- Users table with username (unique, 50 chars), description (120 chars), password_digest
- Posts table with author_id, content (200 chars), parent_id (for replies)
- Follows table with composite primary key (follower_id, followed_id)

✅ **Models**
- User: has_secure_password, associations, follow/unfollow methods, feed_posts scope
- Post: associations, validations, scopes (timeline, top_level, replies)
- Follow: validations (no self-following, uniqueness)

✅ **Controllers**
- PostsController: index (timeline with filters), show, create
- UsersController: show (profile), edit, update, destroy
- FollowsController: create, destroy

✅ **Views**
- Posts index (timeline with filters)
- Post show (with replies)
- User profile
- User settings
- Layout with navigation

✅ **Styling**
- Modern, responsive CSS
- Character counter (Stimulus controller)

## Features Not Yet Implemented

⚠️ **Authentication** (deferred as requested)
- Login/Signup pages
- Password reset
- Session management

## Development Workflow

1. Create users in console with passwords
2. Set session manually to simulate being logged in
3. Test all features:
   - Creating posts
   - Replying to posts
   - Following/unfollowing users
   - Viewing timelines
   - Editing user settings
   - Deleting account

## Testing the Application

1. **Create test data:**
   ```ruby
   # In Rails console
   5.times do |i|
     user = User.create!(username: "user#{i+1}", password: "pass123", description: "User #{i+1}")
     user.posts.create!(content: "Post #{i+1} from user#{i+1}")
   end
   ```

2. **Set session (add temporary route or use manual method)**

3. **Test features:**
   - Visit `/` - see timeline
   - Visit `/posts` - see all posts
   - Click on a user - see profile
   - Follow users
   - Create posts
   - Reply to posts

## Next Steps

When ready to add authentication:
1. Generate authentication (Rails has generators for this)
2. Create SessionsController
3. Create login/signup views
4. Update ApplicationController with proper authentication
5. Add password verification to account deletion

