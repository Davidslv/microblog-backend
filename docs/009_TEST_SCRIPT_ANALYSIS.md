# Load Test Script Analysis

## Application Functionality Review

### Active Endpoints:
1. **GET /** - Posts index (feed/timeline)
   - Supports `filter` param: 'timeline', 'mine', 'following', 'all'
   - Supports `cursor` param for pagination
   - Returns different content based on logged-in status

2. **GET /posts** - Same as root
3. **GET /posts/:id** - Show post with replies
   - Supports `replies_cursor` param for pagination
4. **POST /posts** - Create post/reply (requires auth, CSRF token)
5. **GET /users/:id** - User profile
   - Supports `cursor` param for pagination
6. **GET /users/:id/edit** - Settings page
7. **PATCH /users/:id** - Update settings (requires auth, CSRF token)
8. **DELETE /users/:id** - Delete account (requires auth)
9. **POST /follow/:user_id** - Follow user (requires auth, CSRF token)
10. **DELETE /follow/:user_id** - Unfollow (requires auth, CSRF token)
11. **GET /dev/login/:user_id** - Dev login (development only)

## Issues Found in k6 Scripts

### Critical Issues:

1. **Missing CSRF Token Handling**
   - POST requests to `/posts`, `/follow/:id`, and PATCH requests need CSRF tokens
   - Rails forms include authenticity tokens that must be extracted
   - Current scripts will fail on POST requests

2. **Missing Filter Parameter Testing**
   - Scripts don't test `filter=mine` or `filter=following`
   - Only default timeline is tested

3. **Missing Pagination Testing**
   - No testing of `cursor` parameter for posts
   - No testing of `replies_cursor` parameter for replies
   - Pagination is a critical feature that should be tested

4. **Incomplete Coverage**
   - `k6_baseline.js` doesn't test post creation, follow/unfollow, user profiles
   - Missing tests for different filter options
   - No testing of pagination links

5. **POST Request Format**
   - Current format may not match Rails expected format exactly
   - Need to extract CSRF token from form page first

### Medium Issues:

1. **Cookie Handling**
   - Scripts extract cookies but may not be handling session properly
   - Should verify cookies are being passed correctly

2. **Error Handling**
   - Some scripts don't handle 404s gracefully when post/user doesn't exist
   - Should use realistic post/user IDs from seed data

3. **Missing Endpoint Tests**
   - User profile edit page not tested
   - Settings update not tested

## Recommendations

1. **Fix CSRF Token Handling**
   - Extract token from form page before POST
   - Include in POST request body

2. **Add Filter Testing**
   - Test all filter options: timeline, mine, following
   - Verify different content is returned

3. **Add Pagination Testing**
   - Test cursor-based pagination
   - Test "Load More" functionality
   - Verify pagination works correctly

4. **Improve Realistic Data**
   - Use actual post/user IDs from seeded data
   - Query database or use known IDs

5. **Complete Coverage**
   - Test all endpoints in comprehensive script
   - Add proper error handling

