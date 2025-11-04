# Rack::Attack Configuration
# Rate limiting middleware to protect against abuse and DDoS attacks
# See: docs/028_SCALING_AND_PERFORMANCE_STRATEGIES.md

class Rack::Attack
  # Use Solid Cache as the storage backend (same as Rails.cache)
  # This allows rate limiting to work across multiple server instances
  # For development, this uses SQLite. For production, can use Redis if needed.
  Rack::Attack.cache.store = Rails.cache

  # Enable/disable rate limiting based on environment
  # Can be disabled for testing or specific environments
  if ENV['DISABLE_RACK_ATTACK'] == 'true'
    Rack::Attack.enabled = false
  end

  ### Configure Cache ###

  # If you want to use a different cache store, uncomment and configure:
  # Rack::Attack.cache.store = ActiveSupport::Cache::RedisCacheStore.new(url: ENV['REDIS_URL'])

  ### Throttle Spam by IP Address ###

  # Throttle all requests by IP address
  # Limit: 300 requests per 5 minutes per IP
  # This provides baseline protection against abuse
  throttle('req/ip', limit: 300, period: 5.minutes) do |req|
    req.ip
  end

  ### Throttle Post Creation ###

  # Throttle post creation by user
  # Limit: 10 posts per minute per user
  # Prevents spam and ensures fair resource usage
  throttle('posts/create', limit: 10, period: 1.minute) do |req|
    # Only throttle POST requests to /posts
    if req.path == '/posts' && req.post?
      # Try to get user_id from session (for authenticated users)
      # Fall back to IP if no session (for unauthenticated abuse)
      session_key = req.session['user_id'] rescue nil
      session_key || req.ip
    end
  end

  ### Throttle Follow/Unfollow Actions ###

  # Throttle follow/unfollow actions by user
  # Limit: 50 actions per hour per user
  # Prevents automated following/unfollowing abuse
  throttle('follows/action', limit: 50, period: 1.hour) do |req|
    # Match both POST /follow/:user_id and DELETE /follow/:user_id
    if req.path.start_with?('/follow/') && (req.post? || req.delete?)
      session_key = req.session['user_id'] rescue nil
      session_key || req.ip
    end
  end

  ### Throttle Feed Requests ###

  # Throttle feed requests by user
  # Limit: 100 requests per minute per user
  # Prevents excessive feed refreshing (which can be expensive)
  throttle('feed/requests', limit: 100, period: 1.minute) do |req|
    # Match GET requests to /posts (feed page)
    # Also match root path which shows feed
    if (req.path == '/posts' || req.path == '/') && req.get?
      session_key = req.session['user_id'] rescue nil
      session_key || req.ip
    end
  end

  ### Throttle API Requests (if you add API endpoints later) ###

  # Throttle API requests by IP
  # Limit: 60 requests per minute per IP
  # This is a placeholder for future API endpoints
  throttle('api/requests', limit: 60, period: 1.minute) do |req|
    req.ip if req.path.start_with?('/api')
  end

  ### Custom Response for Throttled Requests ###

  # Customize the response when rate limit is exceeded
  # Returns 429 Too Many Requests with helpful headers
  # Using throttled_responder (newer API) instead of deprecated throttled_response
  Rack::Attack.throttled_responder = lambda do |request|
    match_data = request.env['rack.attack.match_data']
    now = match_data[:epoch_time]
    period = match_data[:period]

    # Calculate reset time (when the rate limit window resets)
    reset_time = now + (period - (now % period))

    headers = {
      'Content-Type' => 'application/json',
      'X-RateLimit-Limit' => match_data[:limit].to_s,
      'X-RateLimit-Remaining' => '0',
      'X-RateLimit-Reset' => reset_time.to_s,
      'Retry-After' => (reset_time - now).to_s
    }

    # Return 429 Too Many Requests
    body = {
      error: 'Rate limit exceeded',
      message: 'Too many requests. Please try again later.',
      retry_after: reset_time - now
    }.to_json

    [429, headers, [body]]
  end

  ### Logging (Optional) ###

  # Log when requests are throttled (useful for monitoring)
  ActiveSupport::Notifications.subscribe('throttle.rack_attack') do |name, start, finish, request_id, payload|
    req = payload[:request]
    Rails.logger.warn "[Rack::Attack] Throttled #{req.ip} for #{payload[:matched]}"
  end
end

