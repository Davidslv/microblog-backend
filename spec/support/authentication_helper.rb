module AuthenticationHelper
  def login_as(user)
    if self.class.metadata[:type] == :request
      # For request specs - make a request to set session
      get "/dev/login/#{user.id}"
    elsif respond_to?(:visit)
      # For feature specs - use the dev login route
      visit "/dev/login/#{user.id}"
    end
  end

  def logout
    if self.class.metadata[:type] == :request
      # For request specs - session is cleared after request
      # Can't easily clear session in request specs without a route
      # This is handled by the controller when user is deleted
    elsif respond_to?(:visit)
      # For feature specs - visit root and clear session via controller
      visit root_path
      # Session management in feature specs would need to be handled differently
      # For now, we'll just visit a page that doesn't require login
      page.driver.browser.manage.delete_all_cookies if page.driver.respond_to?(:browser)
    end
  end

  def current_user
    if self.class.metadata[:type] == :request && respond_to?(:session)
      User.find_by(id: session[:user_id])
    else
      nil
    end
  end
end

RSpec.configure do |config|
  config.include AuthenticationHelper, type: :request
  config.include AuthenticationHelper, type: :feature
end

