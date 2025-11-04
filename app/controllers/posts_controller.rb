class PostsController < ApplicationController
  before_action :require_login_for_create, only: [ :create ]

  def index
    @post = Post.new
    @filter = params[:filter] || "timeline"
    per_page = 20

    if current_user
      case @filter
      when "mine"
        posts_relation = current_user.posts.timeline
      when "following"
        # Optimized: Use JOIN instead of IN clause for better performance
        user_id = Post.connection.quote(current_user.id)
        posts_relation = Post.joins(
          "INNER JOIN follows ON posts.author_id = follows.followed_id AND follows.follower_id = #{user_id}"
        ).timeline.distinct
      else
        posts_relation = current_user.feed_posts.timeline
      end
    else
      posts_relation = Post.top_level.timeline
      @filter = "all"
    end

    # Use cursor-based pagination (efficient SQL, no OFFSET)
    @posts, @next_cursor, @has_next = cursor_paginate(posts_relation, per_page: per_page)
  end

  def show
    @post = Post.find(params[:id])
    # Paginate replies using cursor-based pagination
    # Replies are ordered oldest to newest (ASC) for chronological conversation flow
    # Use a separate cursor param for replies
    replies_cursor = params[:replies_cursor] || params[:cursor]
    @replies, @replies_next_cursor, @replies_has_next = cursor_paginate(
      @post.replies.order(created_at: :asc),
      per_page: 20,
      cursor: replies_cursor,
      order: :asc
    )
    @reply = Post.new(parent_id: @post.id)
  end

  def create
    @post = Post.new(post_params)
    @post.author = current_user

    if @post.save
      redirect_to @post.parent || posts_path, notice: "Post created successfully!"
    else
      flash[:alert] = @post.errors.full_messages.join(", ")
      if @post.parent
        redirect_to @post.parent
      else
        redirect_to posts_path
      end
    end
  end

  private

  def post_params
    params.require(:post).permit(:content, :parent_id)
  end

  def require_login_for_create
    unless logged_in?
      flash[:alert] = "You must be logged in to create a post."
      redirect_to posts_path
    end
  end
end
