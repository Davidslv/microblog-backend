import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Counter } from 'k6/metrics';
import { parseHTML } from 'k6/html';

// Custom metrics
const errorRate = new Rate('errors');
const feedRequests = new Counter('feed_requests');
const postRequests = new Counter('post_requests');
const createRequests = new Counter('create_requests');
const filterRequests = new Counter('filter_requests');
const paginationRequests = new Counter('pagination_requests');
const rateLimitHits = new Counter('rate_limit_hits');

// Realistic load test - simulates actual user behavior
// Tests load balancing across 3 web servers via Traefik
// Rate limits (rack-attack):
// - General: 300 req/5min per IP
// - Posts: 10/min per user
// - Follows: 50/hour per user
// - Feeds: 100/min per user
export const options = {
  stages: [
    { duration: '1m', target: 20 },   // Ramp up
    { duration: '3m', target: 50 },    // Normal load
    { duration: '2m', target: 100 },   // Peak load (3x normal)
    { duration: '2m', target: 50 },    // Back to normal
    { duration: '1m', target: 0 },     // Cool down
  ],
  thresholds: {
    http_req_duration: ['p(95)<500', 'p(99)<1000'],
    http_req_failed: ['rate<0.01'],   // Less than 1% errors
    errors: ['rate<0.01'],
    rate_limit_hits: ['count<100'],   // Some rate limiting expected under peak load
  },
};

// Use load balancer URL (Traefik) - tests distributed setup
const BASE_URL = __ENV.BASE_URL || 'http://localhost';
const NUM_USERS = parseInt(__ENV.NUM_USERS || '1000');
const NUM_POSTS = parseInt(__ENV.NUM_POSTS || '100000');

// Helper function to extract CSRF token from HTML
function extractCSRFToken(html) {
  const doc = parseHTML(html);
  const metaTag = doc.find('meta[name="csrf-token"]');
  if (metaTag.length > 0) {
    return metaTag.attr('content');
  }
  // Fallback: try to find in form
  const form = doc.find('form');
  if (form.length > 0) {
    const tokenInput = form.find('input[name="authenticity_token"]');
    if (tokenInput.length > 0) {
      return tokenInput.attr('value');
    }
  }
  return null;
}

export default function () {
  const userId = Math.floor(Math.random() * NUM_USERS) + 1;

  // Login
  const loginRes = http.get(`${BASE_URL}/dev/login/${userId}`, {
    tags: { name: 'Login' },
  });

  if (!check(loginRes, { 'login successful': (r) => r.status === 200 || r.status === 302 })) {
    errorRate.add(1);
    return;
  }

  const cookies = loginRes.cookies;

  // Get CSRF token from feed page
  const feedPageRes = http.get(`${BASE_URL}/`, {
    cookies: cookies,
    tags: { name: 'FeedPage' },
  });

  if (!check(feedPageRes, { 'feed page loaded': (r) => r.status === 200 })) {
    errorRate.add(1);
    return;
  }

  const csrfToken = extractCSRFToken(feedPageRes.body);
  if (!csrfToken) {
    console.log(`Warning: Could not extract CSRF token for user ${userId}`);
  }

  // Simulate realistic user session
  const actions = Math.floor(Math.random() * 8) + 3; // 3-10 actions per session

  for (let i = 0; i < actions; i++) {
    const action = Math.random();

    // 40% - View feed (most common)
    if (action < 0.4) {
      feedRequests.add(1);

      // Test different filter options
      const filterOptions = ['timeline', 'mine', 'following'];
      const filter = filterOptions[Math.floor(Math.random() * filterOptions.length)];
      filterRequests.add(1);

      const feedRes = http.get(`${BASE_URL}/?filter=${filter}`, {
        cookies: cookies,
        tags: { name: 'FeedPage' },
      });

      if (feedRes.status === 429) {
        rateLimitHits.add(1);
      }

      check(feedRes, {
        'feed status 200': (r) => r.status === 200,
        'not rate limited': (r) => r.status !== 429,
      }) || errorRate.add(1);

      // 20% chance to test pagination
      if (Math.random() < 0.2 && feedRes.status === 200) {
        paginationRequests.add(1);
        // Extract cursor from "Load More" link if available
        const doc = parseHTML(feedRes.body);
        const loadMoreLink = doc.find('a[href*="cursor"]');
        if (loadMoreLink.length > 0) {
          const href = loadMoreLink.attr('href');
          const cursorMatch = href.match(/cursor=(\d+)/);
          if (cursorMatch) {
            const cursor = cursorMatch[1];
            const paginatedRes = http.get(`${BASE_URL}/?filter=${filter}&cursor=${cursor}`, {
              cookies: cookies,
              tags: { name: 'FeedPagePaginated' },
            });
            check(paginatedRes, {
              'paginated feed status 200': (r) => r.status === 200,
            });
          }
        }
      }

      // Sleep to stay under rate limit (100 feeds/min = 0.6s between requests)
      // Plus reading time
      sleep(Math.random() * 5 + 3.6); // 3.6-8.6 seconds
    }
    // 25% - View specific post
    else if (action < 0.65) {
      postRequests.add(1);
      const postId = Math.floor(Math.random() * NUM_POSTS) + 1;
      const postRes = http.get(`${BASE_URL}/posts/${postId}`, {
        cookies: cookies,
        tags: { name: 'PostView' },
      });

      check(postRes, {
        'post status ok': (r) => r.status === 200 || r.status === 404,
      });

      // Test replies pagination if post exists
      if (postRes.status === 200 && Math.random() < 0.3) {
        const doc = parseHTML(postRes.body);
        const repliesLoadMore = doc.find('a[href*="replies_cursor"]');
        if (repliesLoadMore.length > 0) {
          const href = repliesLoadMore.attr('href');
          const cursorMatch = href.match(/replies_cursor=(\d+)/);
          if (cursorMatch) {
            const repliesCursor = cursorMatch[1];
            const repliesRes = http.get(`${BASE_URL}/posts/${postId}?replies_cursor=${repliesCursor}`, {
              cookies: cookies,
              tags: { name: 'PostRepliesPaginated' },
            });
            check(repliesRes, {
              'replies paginated status 200': (r) => r.status === 200,
            });
          }
        }
      }

      sleep(Math.random() * 3 + 2); // 2-5 seconds reading
    }
    // 12% - View user profile
    else if (action < 0.77) {
      const profileUserId = Math.floor(Math.random() * NUM_USERS) + 1;
      const profileRes = http.get(`${BASE_URL}/users/${profileUserId}`, {
        cookies: cookies,
        tags: { name: 'UserProfile' },
      });

      check(profileRes, {
        'profile status ok': (r) => r.status === 200 || r.status === 404,
      });

      // Test profile posts pagination
      if (profileRes.status === 200 && Math.random() < 0.3) {
        const doc = parseHTML(profileRes.body);
        const loadMoreLink = doc.find('a[href*="cursor"]');
        if (loadMoreLink.length > 0) {
          const href = loadMoreLink.attr('href');
          const cursorMatch = href.match(/cursor=(\d+)/);
          if (cursorMatch) {
            const cursor = cursorMatch[1];
            const paginatedRes = http.get(`${BASE_URL}/users/${profileUserId}?cursor=${cursor}`, {
              cookies: cookies,
              tags: { name: 'UserProfilePaginated' },
            });
            check(paginatedRes, {
              'profile paginated status 200': (r) => r.status === 200,
            });
          }
        }
      }

      sleep(1);
    }
    // 5% - Create post
    else if (action < 0.82) {
      createRequests.add(1);

      // Get fresh CSRF token from feed page
      const formPageRes = http.get(`${BASE_URL}/`, {
        cookies: cookies,
        tags: { name: 'FeedPageForForm' },
      });
      const freshToken = extractCSRFToken(formPageRes.body) || csrfToken;

      const content = `Test post ${Date.now()} - ${Math.random().toString(36).substring(7)}`;
      const body = `authenticity_token=${encodeURIComponent(freshToken)}&post[content]=${encodeURIComponent(content)}`;

      const createRes = http.post(`${BASE_URL}/posts`, {
        cookies: cookies,
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: body,
        tags: { name: 'PostCreate' },
      });

      if (createRes.status === 429) {
        rateLimitHits.add(1);
        console.log(`Rate limited on post creation for user ${userId}`);
      }

      check(createRes, {
        'create status redirect': (r) => r.status === 302 || r.status === 200,
        'not rate limited': (r) => r.status !== 429,
      }) || errorRate.add(1);

      // Rate limit: 10 posts/min per user - sleep 6s+ to stay under limit
      sleep(6);
    }
    // 3% - Follow/unfollow
    else {
      const targetUserId = Math.floor(Math.random() * NUM_USERS) + 1;

      // Get fresh CSRF token
      const formPageRes = http.get(`${BASE_URL}/users/${targetUserId}`, {
        cookies: cookies,
        tags: { name: 'UserProfileForFollow' },
      });
      const freshToken = extractCSRFToken(formPageRes.body) || csrfToken;

      if (Math.random() < 0.5) {
        // Follow
        const followBody = `authenticity_token=${encodeURIComponent(freshToken)}`;
        const followRes = http.post(`${BASE_URL}/follow/${targetUserId}`, {
          cookies: cookies,
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          body: followBody,
          tags: { name: 'Follow' },
        });

        if (followRes.status === 429) {
          rateLimitHits.add(1);
        }

        check(followRes, {
          'follow status ok': (r) => r.status === 302 || r.status === 200,
          'not rate limited': (r) => r.status !== 429,
        });
      } else {
        // Unfollow - Rails uses POST with _method=delete
        const unfollowBody = `authenticity_token=${encodeURIComponent(freshToken)}&_method=delete`;
        const unfollowRes = http.post(`${BASE_URL}/follow/${targetUserId}`, unfollowBody, {
          cookies: cookies,
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          tags: { name: 'Unfollow' },
        });

        if (unfollowRes.status === 429) {
          rateLimitHits.add(1);
        }

        check(unfollowRes, {
          'unfollow status ok': (r) => unfollowRes.status === 302 || unfollowRes.status === 200,
          'not rate limited': (r) => unfollowRes.status !== 429,
        });
      }

      // Rate limit: 50 follows/hour per user - sleep 72s+ to stay under limit
      // But in practice, users don't follow/unfollow that frequently, so shorter sleep is fine
      sleep(Math.random() * 5 + 10); // 10-15 seconds between follow actions
    }
  }

  // Session ends
  sleep(Math.random() * 10 + 5); // 5-15 seconds between sessions
}
