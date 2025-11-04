# Mission Control – Jobs Configuration
# Configures the UI for monitoring Solid Queue jobs
# See: https://github.com/rails/mission_control-jobs#authentication
#
# Authentication is required by default. In development, we use simple credentials.
# In production, use environment variables for secure credentials.

if Rails.env.development?
  # In development, use simple credentials (user: admin, password: admin)
  # Mission Control automatically detects Solid Queue and uses the primary connection
  MissionControl::Jobs.applications.add(:default) do |application|
    application.http_basic_authentication(
      name: "admin",
      password: "admin"
    )
  end
else
  # In production, use environment variables for secure credentials
  MissionControl::Jobs.applications.add(:default) do |application|
    application.http_basic_authentication(
      name: ENV.fetch("MISSION_CONTROL_USERNAME", "admin"),
      password: ENV.fetch("MISSION_CONTROL_PASSWORD") # Must be set in production
    )
  end
end

