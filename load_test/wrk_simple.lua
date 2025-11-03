-- Simple wrk script for public feed testing (no authentication)
-- Usage: wrk -t12 -c150 -d30s -s load_test/wrk_simple.lua http://localhost:3000/
--
-- This is simpler and faster than wrk_feed.lua since it doesn't handle cookies.
-- Use this for quick baseline throughput testing of the public feed.

-- Randomly test different endpoints for variety
function request()
   local endpoints = {
      "/",                    -- Public feed
      "/posts",               -- Posts index (same as /)
   }

   local endpoint = endpoints[math.random(#endpoints)]
   return wrk.format("GET", endpoint)
end

