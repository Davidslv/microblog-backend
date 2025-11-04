# Mission Control – Jobs Configuration
# Configures the UI for monitoring Solid Queue jobs
# See: https://github.com/rails/mission_control-jobs#authentication
#
# Authentication is required by default. Configure via class-level accessors.
# In development, we use simple credentials. In production, use environment variables.

if Rails.env.development?
  # In development, use simple credentials (user: admin, password: admin)
  MissionControl::Jobs.http_basic_auth_user = "admin"
  MissionControl::Jobs.http_basic_auth_password = "admin"
  MissionControl::Jobs.http_basic_auth_enabled = true
else
  # In production, use environment variables for secure credentials
  MissionControl::Jobs.http_basic_auth_user = ENV.fetch("MISSION_CONTROL_USERNAME", "admin")
  MissionControl::Jobs.http_basic_auth_password = ENV.fetch("MISSION_CONTROL_PASSWORD")
  MissionControl::Jobs.http_basic_auth_enabled = true
end

# Mission Control automatically detects Solid Queue and uses the primary connection
# No need to explicitly add the application - it's auto-detected

