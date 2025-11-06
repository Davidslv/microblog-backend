import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';

// Custom metrics
const errorRate = new Rate('errors');
const feedPageTime = new Trend('feed_page_duration');
const rateLimitHits = new Counter('rate_limit_hits');

// Test configuration - Focus on API feed endpoint performance
export const options = {
  stages: [
    { duration: '30s', target: 20 },   // Ramp up to 20 users
    { duration: '1m', target: 50 },    // Ramp up to 50 users
    { duration: '2m', target: 100 },   // Peak at 100 concurrent users
    { duration: '1m', target: 50 },    // Ramp down
    { duration: '30s', target: 0 },     // Cool down
  ],
  thresholds: {
    'feed_page_duration': ['p(95)<500', 'p(99)<1000'], // Feed should be fast
    'http_req_failed': ['rate<0.05'],  // Allow up to 5% errors under stress
    'errors': ['rate<0.05'],
    'rate_limit_hits': ['count<50'],   // Some rate limiting is expected under load
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost';
const API_BASE = `${BASE_URL}/api/v1`;
const NUM_USERS = parseInt(__ENV.NUM_USERS || '1000');

export default function () {
  // Random user for this virtual user
  const userId = Math.floor(Math.random() * NUM_USERS) + 1;
  const username = `user${userId}`;
  const password = 'password123';

  // Login via API
  const loginRes = http.post(`${API_BASE}/login`, JSON.stringify({
    username: username,
    password: password,
  }), {
    headers: { 'Content-Type': 'application/json' },
    tags: { name: 'APILogin' },
  });

  const loginSuccess = check(loginRes, {
    'login successful': (r) => r.status === 200,
  });

  if (!loginSuccess) {
    errorRate.add(1);
    return;
  }

  const cookies = loginRes.cookies;

  // Test all filter options
  const filters = ['timeline', 'mine', 'following'];
  const filter = filters[Math.floor(Math.random() * filters.length)];

  // Primary test: Feed endpoint (the critical bottleneck)
  const startTime = Date.now();
  const feedRes = http.get(`${API_BASE}/posts?filter=${filter}`, {
    cookies: cookies,
    tags: { name: 'APIFeed' },
  });
  const duration = Date.now() - startTime;
  feedPageTime.add(duration);

  if (feedRes.status === 429) {
    rateLimitHits.add(1);
    console.log(`Rate limited on API feed for user ${userId} with filter ${filter}`);
  }

  const feedSuccess = check(feedRes, {
    'feed status 200': (r) => r.status === 200,
    'feed returns valid JSON': (r) => {
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
    'feed response time acceptable': (r) => r.timings.duration < 1000,
    'not rate limited': (r) => r.status !== 429,
  });

  if (!feedSuccess) {
    errorRate.add(1);
    console.log(`API feed failed for user ${userId} with filter ${filter}: ${feedRes.status} (${duration}ms)`);
  }

  // Simulate user reading time (viewing feed)
  // Plus minimum delay to stay under rate limit (100/min = 0.6s between requests)
  sleep(Math.random() * 3 + 2.6); // 2.6-5.6 seconds

  // Occasionally view a specific post
  if (Math.random() < 0.3) { // 30% chance
    const postId = Math.floor(Math.random() * 10000) + 1;
    const postRes = http.get(`${API_BASE}/posts/${postId}`, {
      cookies: cookies,
      tags: { name: 'APIPostView' },
    });

    check(postRes, {
      'post view status ok': (r) => r.status === 200 || r.status === 404,
    });

    sleep(1);
  }
}

