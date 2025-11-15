require 'rails_helper'

RSpec.describe PostFilter, type: :service do
  let(:user) { create(:user) }
  let(:admin) { create(:user, :admin) }

  describe "#filter_redacted" do
    it "filters out redacted posts for regular users" do
      normal_post = create(:post)
      redacted_post = create(:post, :redacted)

      result = PostFilter.new(user).filter_redacted(Post.all)
      post_ids = result.pluck(:id)

      expect(post_ids).to include(normal_post.id)
      expect(post_ids).not_to include(redacted_post.id)
    end

    it "includes redacted posts for admin users" do
      normal_post = create(:post)
      redacted_post = create(:post, :redacted)

      result = PostFilter.new(admin).filter_redacted(Post.all)
      post_ids = result.pluck(:id)

      expect(post_ids).to include(normal_post.id)
      expect(post_ids).to include(redacted_post.id)
    end

    it "handles empty relation" do
      result = PostFilter.new(user).filter_redacted(Post.none)
      expect(result.count).to eq(0)
    end

    it "handles relation with only redacted posts for regular users" do
      create_list(:post, 3, :redacted)

      result = PostFilter.new(user).filter_redacted(Post.all)
      expect(result.count).to eq(0)
    end

    it "handles relation with only redacted posts for admin users" do
      posts = create_list(:post, 3, :redacted)

      result = PostFilter.new(admin).filter_redacted(Post.all)
      expect(result.count).to eq(3)
    end
  end

  describe "#include_redacted?" do
    it "returns false for regular users" do
      filter = PostFilter.new(user)
      expect(filter.include_redacted?).to be false
    end

    it "returns true for admin users" do
      filter = PostFilter.new(admin)
      expect(filter.include_redacted?).to be true
    end
  end
end
