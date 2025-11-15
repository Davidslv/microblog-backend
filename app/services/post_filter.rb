class PostFilter
  attr_reader :user

  def initialize(user)
    @user = user
  end

  def filter_redacted(relation)
    if include_redacted?
      relation
    else
      relation.not_redacted
    end
  end

  def include_redacted?
    user&.admin? || false
  end
end
