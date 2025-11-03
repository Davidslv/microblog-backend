import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate } from 'k6/metrics';
import { parseHTML } from 'k6/html';

// Custom metrics
const errorRate = new Rate('errors');

// Test configuration
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
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:3000';

// Get a random user ID (assumes users exist from 1 to NUM_USERS)
const NUM_USERS = parseInt(__ENV.NUM_USERS || '100');

// Helper function to extract CSRF token from HTML
function extractCSRFToken(html) {
  const doc = parseHTML(html);
  const metaTag = doc.find('meta[name="csrf-token"]');
  if (metaTag.length > 0) {
    return metaTag.attr('content');
  }
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
  // Random user for this virtual user
  const userId = Math.floor(Math.random() * NUM_USERS) + 1;

  // Login as user (dev login route)
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

  // Extract cookies from login
  const cookies = loginRes.cookies;

  // Test feed page (most critical endpoint)
  const feedRes = http.get(`${BASE_URL}/`, {
    cookies: cookies,
    tags: { name: 'FeedPage' },
  });

  check(feedRes, {
    'feed page status 200': (r) => r.status === 200,
    'feed page has content': (r) => r.body.length > 1000,
  }) || errorRate.add(1);

  sleep(1);

  // Test filter options
  const filters = ['timeline', 'mine', 'following'];
  const filter = filters[Math.floor(Math.random() * filters.length)];
  const filteredFeedRes = http.get(`${BASE_URL}/?filter=${filter}`, {
    cookies: cookies,
    tags: { name: 'FeedPageFiltered' },
  });

  check(filteredFeedRes, {
    'filtered feed status 200': (r) => r.status === 200,
  }) || errorRate.add(1);

  sleep(1);

  // Test viewing a random post
  const postId = Math.floor(Math.random() * 1000) + 1;
  const postRes = http.get(`${BASE_URL}/posts/${postId}`, {
    cookies: cookies,
    tags: { name: 'PostView' },
  });

  check(postRes, {
    'post view status ok': (r) => r.status === 200 || r.status === 404,
  }) || errorRate.add(1);

  sleep(1);

  // Test user profile
  const profileUserId = Math.floor(Math.random() * NUM_USERS) + 1;
  const profileRes = http.get(`${BASE_URL}/users/${profileUserId}`, {
    cookies: cookies,
    tags: { name: 'UserProfile' },
  });

  check(profileRes, {
    'profile status ok': (r) => r.status === 200 || r.status === 404,
  }) || errorRate.add(1);

  sleep(2);
}
