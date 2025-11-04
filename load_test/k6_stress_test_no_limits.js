import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Counter } from 'k6/metrics';

// Stress test WITHOUT rate limiting constraints
// Use this to find the true capacity of your application
//
// IMPORTANT: Disable rack-attack before running this test!
// Set DISABLE_RACK_ATTACK=true in docker-compose.yml or environment
//
// Usage:
//   # With Docker (disable rate limiting)
//   DISABLE_RACK_ATTACK=true docker compose up -d --scale web=3
//   k6 run load_test/k6_stress_test_no_limits.js
//
//   # Or restart with environment variable
//   docker compose down
//   DISABLE_RACK_ATTACK=true docker compose up -d --scale web=3

const errorRate = new Rate('errors');
const serverErrors = new Counter('server_errors'); // 500, 502, 503, etc.

// Aggressive stress test - find breaking point
export const options = {
  stages: [
    { duration: '30s', target: 20 },   // Warm up
    { duration: '1m', target: 50 },    // Ramp up
    { duration: '2m', target: 100 },   // Increase
    { duration: '2m', target: 200 },   // More
    { duration: '2m', target: 300 },   // Peak
    { duration: '2m', target: 400 },   // Extreme
    { duration: '2m', target: 500 },   // Maximum
    { duration: '1m', target: 0 },     // Cool down
  ],
  thresholds: {
    // Very lenient thresholds - we're testing limits
    http_req_duration: ['p(95)<5000'], // Allow up to 5s p95
    http_req_failed: ['rate<0.2'],     // Allow up to 20% errors at extreme load
    errors: ['rate<0.2'],
    // Should NOT see rate limiting (429) if rack-attack is disabled
    'http_req_status{status:429}': ['count==0'], // No rate limits expected
  },
};

// Use load balancer URL (Traefik) - tests distributed setup
const BASE_URL = __ENV.BASE_URL || 'http://localhost';
const NUM_USERS = parseInt(__ENV.NUM_USERS || '1000');

export default function () {
  const userId = Math.floor(Math.random() * NUM_USERS) + 1;

  // Login
  const loginRes = http.get(`${BASE_URL}/dev/login/${userId}`, {
    tags: { name: 'Login' },
    timeout: '15s',
  });

  if (!check(loginRes, { 'login successful': (r) => r.status === 200 || r.status === 302 })) {
    errorRate.add(1);
    return;
  }

  const cookies = loginRes.cookies;

  // Aggressively hit feed page - no rate limit delays
  // This tests true application capacity
  const feedRes = http.get(`${BASE_URL}/`, {
    cookies: cookies,
    tags: { name: 'FeedPage' },
    timeout: '15s',
  });

  // Track server errors (not rate limits)
  if (feedRes.status >= 500) {
    serverErrors.add(1);
    console.log(`Server error ${feedRes.status} for user ${userId}`);
  }

  // Check for rate limiting (shouldn't happen if disabled)
  if (feedRes.status === 429) {
    console.log(`⚠️  WARNING: Rate limited (429) - rack-attack may still be enabled!`);
    console.log(`   Set DISABLE_RACK_ATTACK=true and restart containers`);
  }

  const success = check(feedRes, {
    'feed status ok': (r) => r.status === 200 || r.status === 429, // 429 shouldn't happen
    'feed response time < 15s': (r) => r.timings.duration < 15000,
    'not server error': (r) => r.status < 500,
  });

  if (!success && feedRes.status !== 429) {
    errorRate.add(1);
  }

  // Minimal sleep to maximize load (stress test)
  sleep(0.1); // Very aggressive - 10 requests per second per VU
}

