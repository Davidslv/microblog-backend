require 'rails_helper'

RSpec.describe FanOutFeedJob, type: :job do
  describe '#perform' do
    let(:author) { create(:user) }
    let(:followers) { create_list(:user, 3) }
    let(:post) { create(:post, author: author) }

    before do
      followers.each { |f| f.follow(author) }
    end

    it 'creates feed entries for all followers' do
      expect {
        FanOutFeedJob.perform_now(post.id)
      }.to change { FeedEntry.count }.by(3)
    end

    it 'creates correct feed entries' do
      FanOutFeedJob.perform_now(post.id)

      followers.each do |follower|
        entry = FeedEntry.find_by(user_id: follower.id, post_id: post.id)
        expect(entry).to be_present
        expect(entry.author_id).to eq(author.id)
        expect(entry.created_at).to be_within(1.second).of(post.created_at)
      end
    end

    it 'does not create entries for replies' do
      reply = create(:post, :reply, parent: post, author: author)

      expect {
        FanOutFeedJob.perform_now(reply.id)
      }.not_to change { FeedEntry.count }
    end

    it 'does not create entries if post has no author' do
      post_without_author = create(:post, author: nil)

      expect {
        FanOutFeedJob.perform_now(post_without_author.id)
      }.not_to change { FeedEntry.count }
    end

    it 'handles posts with no followers gracefully' do
      author_without_followers = create(:user)
      post_without_followers = create(:post, author: author_without_followers)

      expect {
        FanOutFeedJob.perform_now(post_without_followers.id)
      }.not_to raise_error
    end

    it 'handles non-existent post gracefully' do
      expect {
        FanOutFeedJob.perform_now(999999)
      }.not_to raise_error
    end

    it 'handles large follower counts efficiently' do
      # Create many followers
      many_followers = create_list(:user, 100)
      many_followers.each { |f| f.follow(author) }

      # Should still work
      expect {
        FanOutFeedJob.perform_now(post.id)
      }.to change { FeedEntry.count }.by(103) # 3 original + 100 new
    end
  end
end

