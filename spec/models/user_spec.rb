require 'rails_helper'

RSpec.describe User, type: :model do
  describe "associations" do
    it { should have_many(:posts).with_foreign_key("author_id").dependent(:nullify) }
    it { should have_many(:active_follows).class_name("Follow").with_foreign_key("follower_id").dependent(:delete_all) }
    it { should have_many(:passive_follows).class_name("Follow").with_foreign_key("followed_id").dependent(:delete_all) }
    it { should have_many(:following).through(:active_follows).source(:followed) }
    it { should have_many(:followers).through(:passive_follows).source(:follower) }
    it { should have_many(:feed_entries).dependent(:delete_all) }
  end

  describe "validations" do
    subject { build(:user) }

    it { should validate_presence_of(:username) }
    it { should validate_uniqueness_of(:username) }
    it { should validate_length_of(:username).is_at_most(50) }
    it { should validate_length_of(:description).is_at_most(120).allow_nil }
    it { should validate_length_of(:password).is_at_least(6).allow_blank }
    it { should have_secure_password }
  end

  describe "#follow" do
    let(:user1) { create(:user) }
    let(:user2) { create(:user) }

    context "when following a valid user" do
      it "creates a follow relationship" do
        expect {
          user1.follow(user2)
        }.to change { Follow.count }.by(1)
      end

      it "returns truthy value" do
        expect(user1.follow(user2)).to be_truthy
      end

      it "adds user2 to user1 following list" do
        user1.follow(user2)
        expect(user1.following).to include(user2)
      end

      it "adds user1 to user2 followers list" do
        user1.follow(user2)
        expect(user2.followers).to include(user1)
      end
    end

    context "when trying to follow self" do
      it "does not create a follow relationship" do
        expect {
          user1.follow(user1)
        }.not_to change { Follow.count }
      end

      it "returns false" do
        expect(user1.follow(user1)).to be false
      end
    end

    context "when already following the user" do
      before do
        user1.follow(user2)
      end

      it "does not create a duplicate follow relationship" do
        expect {
          user1.follow(user2)
        }.not_to change { Follow.count }
      end

      it "returns false" do
        expect(user1.follow(user2)).to be false
      end
    end
  end

  describe "#unfollow" do
    let(:user1) { create(:user) }
    let(:user2) { create(:user) }

    before do
      user1.follow(user2)
    end

    it "removes the follow relationship" do
      expect {
        user1.unfollow(user2)
      }.to change { Follow.count }.by(-1)
    end

    it "removes user2 from user1 following list" do
      user1.unfollow(user2)
      expect(user1.following).not_to include(user2)
    end

    it "removes user1 from user2 followers list" do
      user1.unfollow(user2)
      expect(user2.followers).not_to include(user1)
    end

    context "when not following the user" do
      before do
        user1.unfollow(user2)
      end

      it "does not raise an error" do
        expect { user1.unfollow(user2) }.not_to raise_error
      end

      it "returns false when not following" do
        expect(user1.unfollow(user2)).to be false
      end
    end
  end

  describe "#following?" do
    let(:user1) { create(:user) }
    let(:user2) { create(:user) }

    context "when following the user" do
      before do
        user1.follow(user2)
      end

      it "returns true" do
        expect(user1.following?(user2)).to be true
      end
    end

    context "when not following the user" do
      it "returns false" do
        expect(user1.following?(user2)).to be false
      end
    end
  end

  describe "#feed_posts" do
    let(:user) { create(:user) }
    let(:followed_user) { create(:user) }

    context "with fallback mode (no feed entries)" do
      before do
        user.follow(followed_user)
        create(:post, author: user)
        create(:post, author: followed_user)
        create(:post, author: create(:user)) # Not followed
      end

      it "includes posts from the user" do
        feed_posts = user.feed_posts.to_a
        expect(feed_posts.map(&:author_id)).to include(user.id)
      end

      it "includes posts from followed users" do
        feed_posts = user.feed_posts.to_a
        expect(feed_posts.map(&:author_id)).to include(followed_user.id)
      end

      it "does not include posts from non-followed users" do
        feed_posts = user.feed_posts.to_a
        non_followed_posts = Post.where.not(author_id: [user.id, followed_user.id])
        expect(feed_posts.map(&:id)).not_to include(*non_followed_posts.pluck(:id))
      end

      it "returns all posts from user and followed users" do
        feed_posts = user.feed_posts.to_a
        expect(feed_posts.length).to eq(2)
      end
    end
  end

  describe "admin functionality" do
    let(:user) { create(:user) }
    let(:admin_user) { create(:user, :admin) }

    describe "#admin?" do
      it "returns false for regular users" do
        expect(user.admin?).to be false
      end

      it "returns true for admin users" do
        expect(admin_user.admin?).to be true
      end
    end

    describe "#user_admin" do
      it "is nil for regular users" do
        expect(user.user_admin).to be_nil
      end

      it "exists for admin users" do
        expect(admin_user.user_admin).to be_present
      end
    end
  end
end
