import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';

// Custom metrics
const errorRate = new Rate('errors');
const rateLimitHits = new Counter('rate_limit_hits');
const postCreateTime = new Trend('post_create_duration');
const feedTime = new Trend('feed_duration');

// Test configuration - Realistic API usage
export const options = {
  stages: [
    { duration: '1m', target: 20 },   // Ramp up
    { duration: '3m', target: 50 },   // Increase load
    { duration: '3m', target: 100 },  // Peak load
    { duration: '1m', target: 50 },   // Ramp down
    { duration: '30s', target: 0 },   // Cool down
  ],
  thresholds: {
    'feed_duration': ['p(95)<500', 'p(99)<1000'],
    'post_create_duration': ['p(95)<1000'],
    'http_req_failed': ['rate<0.05'],
    'errors': ['rate<0.05'],
    'rate_limit_hits': ['count<100'],
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost';
const API_BASE = `${BASE_URL}/api/v1`;
const NUM_USERS = parseInt(__ENV.NUM_USERS || '1000');

export default function () {
  const userId = Math.floor(Math.random() * NUM_USERS) + 1;
  const username = `user${userId}`;
  const password = 'password123';

  // Login
  const loginRes = http.post(`${API_BASE}/login`, JSON.stringify({
    username: username,
    password: password,
  }), {
    headers: { 'Content-Type': 'application/json' },
    tags: { name: 'APILogin' },
  });

  if (!check(loginRes, { 'login successful': (r) => r.status === 200 })) {
    errorRate.add(1);
    return;
  }

  const cookies = loginRes.cookies;

  // Simulate realistic user behavior
  const action = Math.random();

  if (action < 0.40) {
    // 40% - View feed (most common)
    const filters = ['timeline', 'mine', 'following'];
    const filter = filters[Math.floor(Math.random() * filters.length)];

    const startTime = Date.now();
    const feedRes = http.get(`${API_BASE}/posts?filter=${filter}`, {
      cookies: cookies,
      tags: { name: 'APIFeed' },
    });
    feedTime.add(Date.now() - startTime);

    if (feedRes.status === 429) rateLimitHits.add(1);

    check(feedRes, {
      'feed status 200': (r) => r.status === 200,
      'feed has posts': (r) => {
        if (r.status === 200) {
          try {
            const body = JSON.parse(r.body);
            return body.posts && body.posts.length > 0;
          } catch (e) {
            return false;
          }
        }
        return false;
      },
    }) || errorRate.add(1);

    // Test pagination
    if (feedRes.status === 200) {
      try {
        const body = JSON.parse(feedRes.body);
        if (body.pagination && body.pagination.cursor && body.pagination.has_next) {
          const nextPageRes = http.get(`${API_BASE}/posts?filter=${filter}&cursor=${body.pagination.cursor}`, {
            cookies: cookies,
            tags: { name: 'APIFeedNextPage' },
          });
          check(nextPageRes, { 'next page status 200': (r) => r.status === 200 });
        }
      } catch (e) {
        // Ignore JSON parse errors
      }
    }

    sleep(Math.random() * 3 + 2.6);

  } else if (action < 0.65) {
    // 25% - View specific post
    const postId = Math.floor(Math.random() * 10000) + 1;
    const postRes = http.get(`${API_BASE}/posts/${postId}`, {
      cookies: cookies,
      tags: { name: 'APIPostView' },
    });

    check(postRes, {
      'post view status ok': (r) => r.status === 200 || r.status === 404,
    }) || errorRate.add(1);

    sleep(Math.random() * 2 + 1);

  } else if (action < 0.77) {
    // 12% - View user profile
    const profileUserId = Math.floor(Math.random() * NUM_USERS) + 1;
    const profileRes = http.get(`${API_BASE}/users/${profileUserId}`, {
      cookies: cookies,
      tags: { name: 'APIUserProfile' },
    });

    check(profileRes, {
      'profile status ok': (r) => r.status === 200 || r.status === 404,
    }) || errorRate.add(1);

    sleep(Math.random() * 2 + 1);

  } else if (action < 0.82) {
    // 5% - Create post
    const startTime = Date.now();
    const postRes = http.post(`${API_BASE}/posts`, JSON.stringify({
      post: {
        content: `Test post from load test at ${new Date().toISOString()}`,
      },
    }), {
      headers: { 'Content-Type': 'application/json' },
      cookies: cookies,
      tags: { name: 'APIPostCreate' },
    });
    postCreateTime.add(Date.now() - startTime);

    if (postRes.status === 429) rateLimitHits.add(1);

    check(postRes, {
      'post create status 201': (r) => r.status === 201,
      'post create returns post': (r) => {
        if (r.status === 201) {
          try {
            const body = JSON.parse(r.body);
            return body.post && body.post.id;
          } catch (e) {
            return false;
          }
        }
        return false;
      },
    }) || errorRate.add(1);

    sleep(Math.random() * 5 + 3);

  } else if (action < 0.85) {
    // 3% - Follow user
    const followUserId = Math.floor(Math.random() * NUM_USERS) + 1;
    if (followUserId !== userId) {
      const followRes = http.post(`${API_BASE}/users/${followUserId}/follow`, null, {
        cookies: cookies,
        tags: { name: 'APIFollow' },
      });

      if (followRes.status === 429) rateLimitHits.add(1);

      check(followRes, {
        'follow status ok': (r) => r.status === 200 || r.status === 422, // 422 = already following
      }) || errorRate.add(1);
    }

    sleep(Math.random() * 3 + 2);

  } else {
    // 15% - Other actions (unfollow, etc.)
    sleep(Math.random() * 2 + 1);
  }
}

