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

    # Skip health check endpoint (small response, not worth compressing)
    return false if env['PATH_INFO'] == '/up'

    # Only compress API responses and compressible content types
    # Note: Rack::Deflater automatically skips very small responses (<860 bytes)
    # so we don't need to check Content-Length here (it may not be available yet)
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

