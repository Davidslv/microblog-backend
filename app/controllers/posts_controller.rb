class PostsController < ApplicationController
  before_action :require_login_for_create, only: [:create]

  def index
    if current_user
      @posts = current_user.feed_posts.timeline
      @filter = params[:filter] || 'timeline'

      case @filter
      when 'mine'
        @posts = current_user.posts.timeline
      when 'following'
        following_ids = current_user.following.pluck(:id)
        @posts = Post.where(author_id: following_ids).timeline
      else
        @posts = current_user.feed_posts.timeline
      end
    else
      @posts = Post.top_level.timeline.limit(20)
      @filter = 'all'
    end

    @post = Post.new
  end

  def show
    @post = Post.find(params[:id])
    @replies = @post.replies.timeline
    @reply = Post.new(parent_id: @post.id)
  end

  def create
    @post = Post.new(post_params)
    @post.author = current_user

    if @post.save
      redirect_to @post.parent || posts_path, notice: 'Post created successfully!'
    else
      flash[:alert] = @post.errors.full_messages.join(', ')
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
      flash[:alert] = 'You must be logged in to create a post.'
      redirect_to posts_path
    end
  end
end

