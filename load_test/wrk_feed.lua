-- wrk script for feed page load testing
-- Usage: wrk -t4 -c50 -d30s -s load_test/wrk_feed.lua http://localhost:3000/
--
-- This script tests the feed page with authentication.
-- Note: wrk has limited cookie/session handling, so for comprehensive testing use k6.
--
-- For simple public feed testing (no auth), use:
-- wrk -t12 -c150 -d30s http://localhost:3000/

-- Thread-local storage for cookies
local threads = {}

-- Initialize thread
function init(args)
   local thread_id = wrk.thread
   threads[thread_id] = {
      cookies = nil,
      userId = math.random(1, 1000),
      login_done = false
   }
end

-- Extract cookies from Set-Cookie header
function extract_cookies(headers)
   -- Headers might be a table or string, handle both
   local set_cookie = headers["Set-Cookie"]

   if set_cookie then
      -- Rails session cookie format: _microblog_session=value; path=/; HttpOnly
      -- Extract just the cookie name=value part
      local cookie_match = string.match(set_cookie, "([^;]+)")
      if cookie_match then
         return cookie_match
      end
      return set_cookie
   end

   -- Try lowercase header name
   set_cookie = headers["set-cookie"]
   if set_cookie then
      local cookie_match = string.match(set_cookie, "([^;]+)")
      if cookie_match then
         return cookie_match
      end
   end

   return nil
end

-- Main request function
function request()
   local thread_id = wrk.thread
   local thread = threads[thread_id]

   -- First few requests: login to get session cookie
   -- Use a simple approach: every 100th request, refresh login
   -- This ensures we have cookies for most requests
   if not thread.login_done or (math.random(100) == 1) then
      thread.login_done = true
      local loginPath = "/dev/login/" .. thread.userId
      return wrk.format("GET", loginPath)
   end

   -- Use cookies if available, otherwise test public feed
   if not thread.cookies then
      -- No cookies yet, test public feed
      return wrk.format("GET", "/")
   end

   -- Test authenticated feed with different filters
   local filters = {
      "?filter=timeline",   -- Most common
      "?filter=mine",
      "?filter=following",
   }
   local filter = filters[math.random(#filters)]

   -- Include cookie in request headers
   local headers = {
      ["Cookie"] = thread.cookies
   }

   return wrk.format("GET", "/" .. filter, headers)
end

-- Handle response to extract cookies
function response(status, headers, body)
   local thread_id = wrk.thread
   local thread = threads[thread_id]

   -- Extract cookies from login response (302 redirect)
   if status == 302 or status == 200 then
      local cookie = extract_cookies(headers)
      if cookie then
         thread.cookies = cookie
      end
   end
end
