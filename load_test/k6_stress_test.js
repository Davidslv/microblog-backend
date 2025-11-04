import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Counter } from 'k6/metrics';

// Stress test - gradually increase load until failure
// Tests load balancing and rate limiting under extreme load
// This will intentionally trigger rate limits to test system behavior
const errorRate = new Rate('errors');
const rateLimitHits = new Counter('rate_limit_hits');

export const options = {
  stages: [
    { duration: '1m', target: 10 },   // Start low
    { duration: '2m', target: 50 },    // Ramp up
    { duration: '2m', target: 100 },   // Increase
    { duration: '2m', target: 150 },   // More
    { duration: '2m', target: 200 },   // Peak (will trigger rate limits)
    { duration: '1m', target: 0 },     // Cool down
  ],
  thresholds: {
    // More lenient thresholds for stress test
    http_req_duration: ['p(95)<2000'], // Allow up to 2s p95
    http_req_failed: ['rate<0.1'],     // Allow up to 10% errors (includes rate limits)
    errors: ['rate<0.1'],
    // Rate limiting is expected in stress test
    rate_limit_hits: ['count>0'],     // Should see some rate limiting
  },
};

// Use load balancer URL (Traefik) - tests distributed setup under stress
const BASE_URL = __ENV.BASE_URL || 'http://localhost';
const NUM_USERS = parseInt(__ENV.NUM_USERS || '1000');

export default function () {
  const userId = Math.floor(Math.random() * NUM_USERS) + 1;

  // Login
  const loginRes = http.get(`${BASE_URL}/dev/login/${userId}`, {
    tags: { name: 'Login' },
    timeout: '10s',
  });

  if (!check(loginRes, { 'login successful': (r) => r.status === 200 || r.status === 302 })) {
    errorRate.add(1);
    return;
  }

  const cookies = loginRes.cookies;

  // Continuously hit feed page (most stressful endpoint)
  // This will trigger rate limits (100 feeds/min per user) at high load
  const feedRes = http.get(`${BASE_URL}/`, {
    cookies: cookies,
    tags: { name: 'FeedPage' },
    timeout: '10s',
  });

  if (feedRes.status === 429) {
    rateLimitHits.add(1);
    // Rate limited - check retry-after header
    const retryAfter = feedRes.headers['Retry-After'];
    if (retryAfter) {
      console.log(`Rate limited for user ${userId}, retry after ${retryAfter}s`);
    }
  }

  const success = check(feedRes, {
    'feed status ok': (r) => r.status === 200 || r.status === 429, // 429 is expected under stress
    'feed response time < 5s': (r) => r.timings.duration < 5000,
  });

  if (!success && feedRes.status !== 429) {
    errorRate.add(1);
  }

  // Short sleep to maximize load (will trigger rate limits)
  // Normal operation would use 0.6s+ to stay under 100/min limit
  sleep(0.5);
}

