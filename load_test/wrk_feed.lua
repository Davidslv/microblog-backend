-- wrk script for feed page load testing
-- Usage: wrk -t4 -c50 -d30s -s load_test/wrk_feed.lua http://localhost:3000/

-- Get a random user ID (1 to 1000)
math.randomseed(os.time())

local userId = math.random(1, 1000)

-- Login first to get session cookie
request = function()
   -- Login
   local loginPath = "/dev/login/" .. userId
   local loginRes = wrk.format("GET", loginPath)

   -- Return login request
   return loginRes
end

-- Parse response to extract cookies
response = function(status, headers, body)
   -- Note: wrk doesn't easily handle cookies, so this is a simplified version
   -- For proper cookie handling, use k6 instead

   -- For now, just make feed request (will work if dev login doesn't require cookies)
   if status == 200 or status == 302 then
      local feedReq = wrk.format("GET", "/")
      return feedReq
   end
end

