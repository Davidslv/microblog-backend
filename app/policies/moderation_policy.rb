class ModerationPolicy
  attr_reader :user

  def initialize(user)
    @user = user
  end

  def can_moderate?
    user&.admin? == true
  end

  def can_redact?(post)
    can_moderate?
  end

  def can_unredact?(post)
    can_moderate?
  end

  def can_view_redacted?
    can_moderate?
  end

  def can_view_reports?
    can_moderate?
  end
end
