module AuthenticationHelper
  def login_as(user)
    if self.class.metadata[:type] == :request
      # For request specs - make login request but use method call that avoids local variable conflicts
      # The full login flow is tested in spec/requests/sessions_spec.rb
      # Access the post method through ActionDispatch::Integration::RequestHelpers to avoid conflicts
      # with local variables named 'post'
      ActionDispatch::Integration::RequestHelpers.instance_method(:post).bind(self).call(
        "/login",
        params: { username: user.username, password: "password123" }
      )
    elsif respond_to?(:visit)
      # For feature specs - use the login form to test the full flow
      visit login_path
      fill_in "Username", with: user.username
      fill_in "Password", with: "password123"
      click_button "Log in"
    end
  end

  def logout
    if self.class.metadata[:type] == :request
      # For request specs - delete session via logout endpoint
      delete "/logout"
    elsif respond_to?(:visit)
      # For feature specs - click logout button
      if page.has_css?("form[action='#{logout_path}']")
        find("form[action='#{logout_path}'] button").click
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
