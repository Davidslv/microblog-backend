import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Counter } from 'k6/metrics';

// Stress test WITH rate limiting, but using IP spoofing
// This tests rate limiting behavior under load
// k6 can simulate requests from different IPs to distribute rate limit counters
//
// Usage:
//   k6 run --out json=results.json load_test/k6_stress_test_with_ip_spoofing.js
//
// Note: IP spoofing in k6 requires --ip-spoof flag (if supported)
// Alternative: Use multiple VUs with different user IDs to distribute load

const errorRate = new Rate('errors');
const rateLimitHits = new Counter('rate_limit_hits');
const serverErrors = new Counter('server_errors');

// Stress test that respects rate limits but distributes load
export const options = {
  stages: [
    { duration: '30s', target: 20 },   // Warm up
    { duration: '1m', target: 50 },    // Ramp up
    { duration: '2m', target: 100 },   // Increase
    { duration: '2m', target: 200 },   // More
    { duration: '2m', target: 300 },   // Peak
    { duration: '1m', target: 0 },     // Cool down
  ],
  thresholds: {
    http_req_duration: ['p(95)<3000'], // Allow up to 3s p95
    http_req_failed: ['rate<0.15'],     // Allow up to 15% errors (includes rate limits)
    errors: ['rate<0.15'],
    // Rate limiting is expected and measured
    rate_limit_hits: ['count>0'],     // Should see rate limiting
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost';
const NUM_USERS = parseInt(__ENV.NUM_USERS || '1000');

// Simulate different IPs by using different user IDs
// Each VU gets a different user, which helps distribute rate limit counters
export default function () {
  // Use VU ID and iteration to create unique user patterns
  // This helps distribute rate limit counters across different users/IPs
  const vuId = __VU; // Virtual User ID (1, 2, 3, ...)
  const iterId = __ITER; // Iteration number
  const userId = ((vuId * 1000) + (iterId % 1000)) % NUM_USERS + 1;

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

  // Hit feed page - will trigger rate limits at high load
  const feedRes = http.get(`${BASE_URL}/`, {
    cookies: cookies,
    tags: { name: 'FeedPage' },
    timeout: '10s',
  });

  if (feedRes.status === 429) {
    rateLimitHits.add(1);
    const retryAfter = feedRes.headers['Retry-After'];
    if (retryAfter) {
      console.log(`Rate limited for user ${userId} (VU ${vuId}), retry after ${retryAfter}s`);
    }
  }

  if (feedRes.status >= 500) {
    serverErrors.add(1);
    console.log(`Server error ${feedRes.status} for user ${userId}`);
  }

  const success = check(feedRes, {
    'feed status ok': (r) => r.status === 200 || r.status === 429,
    'feed response time < 10s': (r) => r.timings.duration < 10000,
    'not server error': (r) => r.status < 500,
  });

  if (!success && feedRes.status !== 429 && feedRes.status < 500) {
    errorRate.add(1);
  }

  // Short sleep to maximize load (will trigger rate limits)
  // But distributed across users helps spread the rate limit impact
  sleep(0.3);
}

