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
      # For feature specs - use a logout route or clear cookies
      # For rack_test driver, we can't easily clear cookies, so just visit a page
      # The session will be handled by the next login
      if page.driver.respond_to?(:browser) && page.driver.browser.respond_to?(:manage)
        page.driver.browser.manage.delete_all_cookies
      else
        # For rack_test, we can't clear cookies, but that's okay
        # The next login_as will override the session anyway
      end
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
