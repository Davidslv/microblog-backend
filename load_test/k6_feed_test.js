import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';

// Custom metrics
const errorRate = new Rate('errors');
const feedPageTime = new Trend('feed_page_duration');
const rateLimitHits = new Counter('rate_limit_hits');

// Test configuration - Focus on feed page performance
// Tests load balancing across multiple web servers (3 instances)
// Rate limits: 100 feeds/min per user, 300 req/5min per IP
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

// Use load balancer URL (Traefik) - tests full stack with 3 web servers
const BASE_URL = __ENV.BASE_URL || 'http://localhost';
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

  // Test all filter options
  const filters = ['timeline', 'mine', 'following'];
  const filter = filters[Math.floor(Math.random() * filters.length)];

  // Primary test: Feed page (the critical bottleneck)
  // Rate limit: 100 feeds/min per user - sleep 0.6s+ to stay under limit
  const startTime = Date.now();
  const feedRes = http.get(`${BASE_URL}/?filter=${filter}`, {
    cookies: cookies,
    tags: { name: 'FeedPage' },
  });
  const duration = Date.now() - startTime;
  feedPageTime.add(duration);

  if (feedRes.status === 429) {
    rateLimitHits.add(1);
    console.log(`Rate limited on feed page for user ${userId} with filter ${filter}`);
  }

  const feedSuccess = check(feedRes, {
    'feed page status 200': (r) => r.status === 200,
    'feed page has posts': (r) => r.body.includes('post') || r.body.length > 500,
    'feed page response time acceptable': (r) => r.timings.duration < 1000,
    'not rate limited': (r) => r.status !== 429,
  });

  if (!feedSuccess) {
    errorRate.add(1);
    console.log(`Feed page failed for user ${userId} with filter ${filter}: ${feedRes.status} (${duration}ms)`);
  }

  // Simulate user reading time (viewing feed)
  // Plus minimum delay to stay under rate limit (100/min = 0.6s between requests)
  sleep(Math.random() * 3 + 2.6); // 2.6-5.6 seconds (ensures <100 req/min)

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
