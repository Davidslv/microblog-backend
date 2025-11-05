class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  # Authentication - require login by default
  before_action :require_login

  # Authentication helpers
  def current_user
    @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id]
  end

  def logged_in?
    current_user.present?
  end

  def require_login
    unless logged_in?
      redirect_to login_path, alert: "You must be logged in to perform that action."
    end
  end

  helper_method :current_user, :logged_in?

  # Cursor-based pagination helper
  # Uses SQL WHERE clause for efficient pagination (better than OFFSET for large datasets)
  #
  # This is much faster than OFFSET-based pagination for large datasets because:
  # - OFFSET 100000 means "skip 100k rows" (slow)
  # - WHERE id < cursor_id means "use index to find next batch" (fast)
  #
  # For DESC order (newest first): WHERE id < cursor_id
  # For ASC order (oldest first): WHERE id > cursor_id
  def cursor_paginate(relation, per_page: 20, cursor: nil, order: :desc)
    # Get the cursor ID from params or use provided cursor
    cursor_id = cursor || params[:cursor]&.to_i

    # Apply cursor filter if provided (for "load more" / "next page")
    if cursor_id.present? && cursor_id > 0
      if order == :asc
        # For ASC order (oldest first), get posts with ID greater than cursor
        relation = relation.where("posts.id > ?", cursor_id)
      else
        # For DESC order (newest first), get posts with ID less than cursor
        relation = relation.where("posts.id < ?", cursor_id)
      end
    end

    # Get one extra to know if there's a next page
    posts = relation.limit(per_page + 1).to_a

    # Determine if there's a next page
    has_next = posts.length > per_page
    posts = posts.take(per_page) if has_next

    # Get the cursor for next page (ID of last post on current page)
    next_cursor = posts.last&.id

    [ posts, next_cursor, has_next ]
  end
end
