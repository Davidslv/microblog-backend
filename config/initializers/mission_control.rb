# Mission Control – Jobs Authentication Configuration
# For development, we disable authentication for easier access.
# In production, you should enable authentication.

if Rails.env.development?
  # Disable authentication in development
  MissionControl::Jobs.applications.add(:default, url: "/jobs")
else
  # In production, configure HTTP Basic authentication
  # See: https://github.com/rails/mission_control-jobs#authentication
  MissionControl::Jobs.applications.add(:default, url: "/jobs") do |application|
    application.http_basic_authentication(
      name: ENV.fetch("MISSION_CONTROL_USERNAME", "admin"),
      password: ENV.fetch("MISSION_CONTROL_PASSWORD", "secret")
    )
  end
end

