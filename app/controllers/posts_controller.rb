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
        # Cache feed posts with cursor-based key (5-minute TTL)
        cache_key = "user_feed:#{current_user.id}:#{params[:cursor]}"
        cached_result = Rails.cache.read(cache_key)

        if cached_result
          @posts, @next_cursor, @has_next = cached_result
          return # Early return for cached feed
        end

        # Cache miss - execute query and cache result
        posts_relation = current_user.feed_posts.timeline
      end
    else
      # Cache public posts aggressively (1 minute TTL) since they change less frequently
      @filter = "all"
      cache_key = "public_posts:#{params[:cursor]}"
      cached_result = Rails.cache.read(cache_key)

      if cached_result
        @posts, @next_cursor, @has_next = cached_result
      else
        posts_relation = Post.top_level.timeline
        @posts, @next_cursor, @has_next = cursor_paginate(posts_relation, per_page: per_page)
        Rails.cache.write(cache_key, [ @posts, @next_cursor, @has_next ], expires_in: 1.minute)
      end

      return # Early return for cached public posts
    end

    # Use cursor-based pagination (efficient SQL, no OFFSET)
    @posts, @next_cursor, @has_next = cursor_paginate(posts_relation, per_page: per_page)

    # Cache the paginated result for feed queries (if not already cached)
    if @filter == "timeline" && current_user
      cache_key = "user_feed:#{current_user.id}:#{params[:cursor]}"
      Rails.cache.write(cache_key, [ @posts, @next_cursor, @has_next ], expires_in: 5.minutes)
    end
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
    
    # If replying to a specific reply, set the parent_id
    # Otherwise, reply to the main post
    if params[:reply_to].present?
      @reply = Post.new(parent_id: params[:reply_to])
    else
      @reply = Post.new(parent_id: @post.id)
    end
  end

  def create
    @post = Post.new(post_params)
    @post.author = current_user

    if @post.save
      # If replying, redirect to the top-level post (original post, not intermediate replies)
      # Otherwise redirect to posts index
      if @post.parent
        # Find the top-level post by walking up the parent chain
        top_level_post = @post
        top_level_post = top_level_post.parent while top_level_post.parent
        redirect_to post_path(top_level_post), notice: "Post created successfully!"
      else
        redirect_to posts_path, notice: "Post created successfully!"
      end
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
