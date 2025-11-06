# CORS configuration for API endpoints
# Allows frontend (React) to make requests to API from different origin

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    # Allow requests from frontend origins
    if Rails.env.development?
      origins ['http://localhost:3001', 'http://localhost:5173', 'http://localhost:5174']
    else
      # In production, use explicit FRONTEND_URL or default to empty array
      frontend_url = ENV.fetch('FRONTEND_URL', nil)
      origins frontend_url ? [frontend_url] : []
    end

    resource '/api/*',
      headers: :any,
      methods: [:get, :post, :put, :patch, :delete, :options, :head],
      credentials: true,
      expose: ['Authorization']
  end
end

