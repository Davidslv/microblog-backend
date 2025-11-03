import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Counter } from 'k6/metrics';

// Custom metrics
const errorRate = new Rate('errors');
const feedRequests = new Counter('feed_requests');
const postRequests = new Counter('post_requests');
const createRequests = new Counter('create_requests');

// Realistic load test - simulates actual user behavior
export const options = {
  stages: [
    { duration: '1m', target: 20 },   // Ramp up
    { duration: '3m', target: 50 },    // Normal load
    { duration: '2m', target: 100 },   // Peak load (3x normal)
    { duration: '2m', target: 50 },    // Back to normal
    { duration: '1m', target: 0 },     // Cool down
  ],
  thresholds: {
    http_req_duration: ['p(95)<500', 'p(99)<1000'],
    http_req_failed: ['rate<0.01'],   // Less than 1% errors
    errors: ['rate<0.01'],
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:3000';
const NUM_USERS = parseInt(__ENV.NUM_USERS || '1000');
const NUM_POSTS = parseInt(__ENV.NUM_POSTS || '100000');

export default function () {
  const userId = Math.floor(Math.random() * NUM_USERS) + 1;
  
  // Login
  const loginRes = http.get(`${BASE_URL}/dev/login/${userId}`, {
    tags: { name: 'Login' },
  });
  
  if (!check(loginRes, { 'login successful': (r) => r.status === 200 || r.status === 302 })) {
    errorRate.add(1);
    return;
  }
  
  const cookies = loginRes.cookies;
  
  // Simulate realistic user session
  const actions = Math.floor(Math.random() * 8) + 3; // 3-10 actions per session
  
  for (let i = 0; i < actions; i++) {
    const action = Math.random();
    
    // 50% - View feed (most common)
    if (action < 0.5) {
      feedRequests.add(1);
      const feedRes = http.get(`${BASE_URL}/`, {
        cookies: cookies,
        tags: { name: 'FeedPage' },
      });
      
      check(feedRes, {
        'feed status 200': (r) => r.status === 200,
      }) || errorRate.add(1);
      
      sleep(Math.random() * 5 + 3); // 3-8 seconds reading
    }
    // 30% - View specific post
    else if (action < 0.8) {
      postRequests.add(1);
      const postId = Math.floor(Math.random() * NUM_POSTS) + 1;
      const postRes = http.get(`${BASE_URL}/posts/${postId}`, {
        cookies: cookies,
        tags: { name: 'PostView' },
      });
      
      check(postRes, {
        'post status ok': (r) => r.status === 200 || r.status === 404,
      });
      
      sleep(Math.random() * 3 + 2); // 2-5 seconds reading
    }
    // 12% - View user profile
    else if (action < 0.92) {
      const profileUserId = Math.floor(Math.random() * NUM_USERS) + 1;
      const profileRes = http.get(`${BASE_URL}/users/${profileUserId}`, {
        cookies: cookies,
        tags: { name: 'UserProfile' },
      });
      
      check(profileRes, {
        'profile status ok': (r) => r.status === 200 || r.status === 404,
      });
      
      sleep(1);
    }
    // 5% - Create post
    else if (action < 0.97) {
      createRequests.add(1);
      const content = `Test post ${Date.now()} - ${Math.random().toString(36).substring(7)}`;
      
      const createRes = http.post(`${BASE_URL}/posts`, {
        cookies: cookies,
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: `post[content]=${encodeURIComponent(content)}`,
        tags: { name: 'PostCreate' },
      });
      
      check(createRes, {
        'create status redirect': (r) => r.status === 302 || r.status === 200,
      }) || errorRate.add(1);
      
      sleep(2);
    }
    // 3% - Follow/unfollow
    else {
      const targetUserId = Math.floor(Math.random() * NUM_USERS) + 1;
      
      if (Math.random() < 0.5) {
        // Follow
        const followRes = http.post(`${BASE_URL}/follow/${targetUserId}`, {
          cookies: cookies,
          tags: { name: 'Follow' },
        });
        
        check(followRes, {
          'follow status ok': (r) => r.status === 302 || r.status === 200,
        });
      } else {
        // Unfollow
        const unfollowRes = http.del(`${BASE_URL}/follow/${targetUserId}`, null, {
          cookies: cookies,
          tags: { name: 'Unfollow' },
        });
        
        check(unfollowRes, {
          'unfollow status ok': (r) => r.status === 302 || r.status === 200,
        });
      }
      
      sleep(1);
    }
  }
  
  // Session ends
  sleep(Math.random() * 10 + 5); // 5-15 seconds between sessions
}

