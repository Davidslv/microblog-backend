import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Counter } from 'k6/metrics';

// Custom metrics
const errorRate = new Rate('errors');
const rateLimitHits = new Counter('rate_limit_hits');

// Test configuration for API endpoints
export const options = {
  stages: [
    { duration: '30s', target: 10 },  // Warm up
    { duration: '1m', target: 10 },   // Stay at 10 users
    { duration: '30s', target: 0 },   // Cool down
  ],
  thresholds: {
    http_req_duration: ['p(95)<500'], // 95% of requests should be below 500ms
    http_req_failed: ['rate<0.01'],   // Error rate should be less than 1%
    errors: ['rate<0.01'],
    rate_limit_hits: ['count<5'],    // Should have minimal rate limit hits
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost';
const API_BASE = `${BASE_URL}/api/v1`;
const NUM_USERS = parseInt(__ENV.NUM_USERS || '1000');

export default function () {
  // Random user for this virtual user
  const userId = Math.floor(Math.random() * NUM_USERS) + 1;
  
  // Use dev login route to get session (same as monolith test)
  // API supports session-based auth for backward compatibility
  const devLoginRes = http.get(`${BASE_URL}/dev/login/${userId}`, {
    tags: { name: 'DevLogin' },
  });
  
  if (devLoginRes.status !== 200 && devLoginRes.status !== 302) {
    errorRate.add(1);
    return;
  }
  
  const cookies = devLoginRes.cookies;
  
  // API accepts session-based auth (from dev login)
  // This tests the parallel running scenario where monolith and API share sessions

  // Test feed endpoint (most critical)
  const feedRes = http.get(`${API_BASE}/posts`, {
    cookies: cookies,
    tags: { name: 'APIFeed' },
  });

  if (feedRes.status === 429) {
    rateLimitHits.add(1);
  }

  const feedSuccess = check(feedRes, {
    'feed status 200': (r) => r.status === 200,
    'feed returns JSON': (r) => {
      if (r.status === 200) {
        try {
          const body = JSON.parse(r.body);
          return body.posts && Array.isArray(body.posts);
        } catch (e) {
          return false;
        }
      }
      return false;
    },
    'feed has pagination': (r) => {
      if (r.status === 200) {
        try {
          const body = JSON.parse(r.body);
          return body.pagination !== undefined;
        } catch (e) {
          return false;
        }
      }
      return false;
    },
    'not rate limited': (r) => r.status !== 429,
  }) || errorRate.add(1);

  sleep(0.6); // Stay under 100 feeds/min limit

  // Test filter options
  const filters = ['timeline', 'mine', 'following'];
  const filter = filters[Math.floor(Math.random() * filters.length)];
  const filteredFeedRes = http.get(`${API_BASE}/posts?filter=${filter}`, {
    cookies: cookies,
    tags: { name: 'APIFeedFiltered' },
  });

  if (filteredFeedRes.status === 429) {
    rateLimitHits.add(1);
  }

  check(filteredFeedRes, {
    'filtered feed status 200': (r) => r.status === 200,
    'not rate limited': (r) => r.status !== 429,
  }) || errorRate.add(1);

  sleep(0.6);

  // Test viewing a random post
  const postId = Math.floor(Math.random() * 1000) + 1;
  const postRes = http.get(`${API_BASE}/posts/${postId}`, {
    cookies: cookies,
    tags: { name: 'APIPostView' },
  });

  check(postRes, {
    'post view status ok': (r) => r.status === 200 || r.status === 404,
    'post returns JSON': (r) => {
      if (r.status === 200) {
        try {
          JSON.parse(r.body);
          return true;
        } catch (e) {
          return false;
        }
      }
      return true;
    },
  }) || errorRate.add(1);

  sleep(1);

  // Test user profile
  const profileUserId = Math.floor(Math.random() * NUM_USERS) + 1;
  const profileRes = http.get(`${API_BASE}/users/${profileUserId}`, {
    cookies: cookies,
    tags: { name: 'APIUserProfile' },
  });

  check(profileRes, {
    'profile status ok': (r) => r.status === 200 || r.status === 404,
    'profile returns JSON': (r) => {
      if (r.status === 200) {
        try {
          const body = JSON.parse(r.body);
          return body.user !== undefined;
        } catch (e) {
          return false;
        }
      }
      return true;
    },
  }) || errorRate.add(1);

  sleep(2);
}

