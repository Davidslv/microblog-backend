import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend } from 'k6/metrics';

// Custom metrics
const errorRate = new Rate('errors');
const feedPageTime = new Trend('feed_page_duration');

// Test configuration - Focus on feed page performance
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
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:3000';
const NUM_USERS = parseInt(__ENV.NUM_USERS || '1000');

export default function () {
  // Random user for this virtual user
  const userId = Math.floor(Math.random() * NUM_USERS) + 1;

  // Login as user
  const loginRes = http.get(`${BASE_URL}/dev/login/${userId}`, {
    tags: { name: 'Login' },
  });

  const loginSuccess = check(loginRes, {
    'login successful': (r) => r.status === 302 || r.status === 200,
  });

  if (!loginSuccess) {
    errorRate.add(1);
    return;
  }

  const cookies = loginRes.cookies;

  // Primary test: Feed page (the critical bottleneck)
  const startTime = Date.now();
  const feedRes = http.get(`${BASE_URL}/`, {
    cookies: cookies,
    tags: { name: 'FeedPage' },
  });
  const duration = Date.now() - startTime;
  feedPageTime.add(duration);

  const feedSuccess = check(feedRes, {
    'feed page status 200': (r) => r.status === 200,
    'feed page has posts': (r) => r.body.includes('post') || r.body.length > 500,
    'feed page response time acceptable': (r) => r.timings.duration < 1000,
  });

  if (!feedSuccess) {
    errorRate.add(1);
    console.log(`Feed page failed for user ${userId}: ${feedRes.status} (${duration}ms)`);
  }

  // Simulate user reading time (viewing feed)
  sleep(Math.random() * 3 + 2); // 2-5 seconds

  // Occasionally view a specific post
  if (Math.random() < 0.3) { // 30% chance
    const postId = Math.floor(Math.random() * 10000) + 1;
    const postRes = http.get(`${BASE_URL}/posts/${postId}`, {
      cookies: cookies,
      tags: { name: 'PostView' },
    });

    check(postRes, {
      'post view status ok': (r) => r.status === 200 || r.status === 404,
    });

    sleep(1);
  }
}

