import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate } from 'k6/metrics';

// Stress test - gradually increase load until failure
const errorRate = new Rate('errors');

export const options = {
  stages: [
    { duration: '1m', target: 10 },   // Start low
    { duration: '2m', target: 50 },    // Ramp up
    { duration: '2m', target: 100 },   // Increase
    { duration: '2m', target: 150 },   // More
    { duration: '2m', target: 200 },   // Peak
    { duration: '1m', target: 0 },     // Cool down
  ],
  thresholds: {
    // More lenient thresholds for stress test
    http_req_duration: ['p(95)<2000'], // Allow up to 2s p95
    http_req_failed: ['rate<0.1'],     // Allow up to 10% errors
    errors: ['rate<0.1'],
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:3000';
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
  const feedRes = http.get(`${BASE_URL}/`, {
    cookies: cookies,
    tags: { name: 'FeedPage' },
    timeout: '10s',
  });

  const success = check(feedRes, {
    'feed status 200': (r) => r.status === 200,
    'feed response time < 5s': (r) => r.timings.duration < 5000,
  });

  if (!success) {
    errorRate.add(1);
  }

  // Short sleep to maximize load
  sleep(0.5);
}

