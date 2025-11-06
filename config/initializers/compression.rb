# HTTP Compression Configuration
# Enables Gzip compression for API responses to reduce bandwidth usage
# See: docs/049_API_OPTIMIZATION_STRATEGIES.md
#
# Benefits:
# - 80-90% reduction in response size
# - Faster transfer times, especially on mobile networks
# - Lower bandwidth costs
# - Better user experience

Rails.application.config.middleware.use Rack::Deflater, {
  # Only compress responses that meet these criteria:
  if: ->(env, status, headers, body) {
    # Only compress successful responses
    return false unless status == 200
    
    # Only compress if response is large enough (avoid overhead for small responses)
    # Check Content-Length if available, otherwise allow compression (Rack::Deflater will handle it)
    content_length = headers['Content-Length']&.to_i
    return false if content_length && content_length < 1024
    
    # Only compress API responses and compressible content types
    env['PATH_INFO'].start_with?('/api/') ||
      headers['Content-Type']&.include?('application/json') ||
      headers['Content-Type']&.include?('text/html') ||
      headers['Content-Type']&.include?('text/css') ||
      headers['Content-Type']&.include?('application/javascript') ||
      headers['Content-Type']&.include?('text/plain') ||
      headers['Content-Type']&.include?('application/xml')
  },
  # Include Vary header to indicate compression
  include: %w[
    application/json
    application/javascript
    text/css
    text/html
    text/plain
    text/xml
    application/xml
    application/xml+rss
  ]
}

