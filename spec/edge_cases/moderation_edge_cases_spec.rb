require 'rails_helper'

RSpec.describe "Moderation Edge Cases", type: :request do
  let(:user) { create(:user) }
  let(:other_user) { create(:user) }
  let(:api_base) { "/api/v1" }

  def get_token(user)
    post "#{api_base}/login", params: { username: user.username, password: "password123" }
    JSON.parse(response.body)["token"]
  end

  describe "Deleted post edge cases" do
    it "handles reporting a post that gets deleted" do
      post = create(:post, author: other_user)
      token = get_token(user)

      # Report the post
      post "#{api_base}/posts/#{post.id}/report",
           headers: { "Authorization" => "Bearer #{token}" }
      expect(response).to have_http_status(:success)

      # Delete audit logs first (they have foreign key constraints)
      ModerationAuditLog.where(post: post).destroy_all

      # Delete the post
      post.destroy

      # Verify report still exists (cascade behavior)
      expect(Report.where(post_id: post.id).count).to eq(0) # Should be deleted with post
    end

    it "returns 404 when reporting a non-existent post" do
      token = get_token(user)

      post "#{api_base}/posts/99999/report",
           headers: { "Authorization" => "Bearer #{token}" }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "Deleted user edge cases" do
    it "handles reports when reporter is deleted" do
      post = create(:post, author: other_user)
      reporter = create(:user)
      token = get_token(reporter)

      # Create report
      post "#{api_base}/posts/#{post.id}/report",
           headers: { "Authorization" => "Bearer #{token}" }
      expect(response).to have_http_status(:success)

      report = Report.last
      expect(report.reporter).to eq(reporter)

      # Delete audit logs and reports first (they have foreign key constraints)
      ModerationAuditLog.where(user: reporter).destroy_all
      Report.where(reporter: reporter).destroy_all

      # Delete reporter
      reporter.destroy

      # Verify reporter was deleted
      expect(User.find_by(id: reporter.id)).to be_nil
    end

    it "handles reports when post author is deleted" do
      author = create(:user)
      post = create(:post, author: author)
      token = get_token(user)

      # Create report
      post "#{api_base}/posts/#{post.id}/report",
           headers: { "Authorization" => "Bearer #{token}" }
      expect(response).to have_http_status(:success)

      # Delete author (post author_id becomes nil)
      author.destroy

      # Report should still work
      post.reload
      expect(post.report_count).to eq(1)
    end
  end

  describe "Concurrent reports edge cases" do
    it "handles concurrent reports from different users" do
      post = create(:post, author: other_user)
      users = create_list(:user, 5)

      # Simulate concurrent reports
      threads = users.map do |u|
        Thread.new do
          token = get_token(u)
          post "#{api_base}/posts/#{post.id}/report",
               headers: { "Authorization" => "Bearer #{token}" }
        end
      end

      threads.each(&:join)

      post.reload
      # Should have exactly 5 reports
      expect(post.report_count).to eq(5)
      expect(post.redacted?).to be true
    end

    it "handles race condition when threshold is reached simultaneously" do
      post = create(:post, author: other_user)

      # Create 4 existing reports
      create_list(:report, 4, post: post)

      # Two users report simultaneously (both would be 5th)
      user1 = create(:user)
      user2 = create(:user)

      token1 = get_token(user1)
      token2 = get_token(user2)

      # Make requests concurrently
      response1 = Thread.new do
        post "#{api_base}/posts/#{post.id}/report",
             headers: { "Authorization" => "Bearer #{token1}" }
        response
      end

      response2 = Thread.new do
        post "#{api_base}/posts/#{post.id}/report",
             headers: { "Authorization" => "Bearer #{token2}" }
        response
      end

      r1 = response1.value
      r2 = response2.value

      # Both should succeed
      expect(r1.status).to eq(200)
      expect(r2.status).to eq(200)

      post.reload
      # Should have 6 reports total
      expect(post.report_count).to eq(6)
      # Should be redacted (only one redaction should occur)
      expect(post.redacted?).to be true
    end
  end

  describe "Already redacted post edge cases" do
    it "allows reporting an already redacted post" do
      post = create(:post, :redacted, author: other_user)
      token = get_token(user)

      # Can still report (for audit trail)
      post "#{api_base}/posts/#{post.id}/report",
           headers: { "Authorization" => "Bearer #{token}" }
      expect(response).to have_http_status(:success)

      post.reload
      expect(post.report_count).to eq(1)
      expect(post.redacted?).to be true
    end

    it "does not auto-redact an already redacted post" do
      post = create(:post, :redacted, author: other_user)

      # Create initial redaction log (since factory doesn't create it)
      AuditLogger.new.log_redaction(post, reason: 'manual')

      # Create 4 reports
      create_list(:report, 4, post: post)

      token = get_token(user)

      # 5th report should not trigger another redaction
      post "#{api_base}/posts/#{post.id}/report",
           headers: { "Authorization" => "Bearer #{token}" }
      expect(response).to have_http_status(:success)

      post.reload
      expect(post.report_count).to eq(5)
      expect(post.redacted?).to be true

      # Should not have duplicate redaction logs (only the manual one)
      redaction_logs = ModerationAuditLog.where(post: post, action: "redact")
      expect(redaction_logs.count).to eq(1) # Only the original redaction
    end
  end

  describe "Multiple posts edge cases" do
    it "handles reporting multiple different posts" do
      posts = create_list(:post, 3, author: other_user)
      token = get_token(user)

      posts.each do |p|
        post "#{api_base}/posts/#{p.id}/report",
             headers: { "Authorization" => "Bearer #{token}" }
        expect(response).to have_http_status(:success)
      end

      # All posts should have reports
      posts.each do |p|
        p.reload
        expect(p.report_count).to eq(1)
      end
    end

    it "handles reporting posts from different authors" do
      authors = create_list(:user, 3)
      posts = authors.map { |a| create(:post, author: a) }
      token = get_token(user)

      posts.each do |p|
        post "#{api_base}/posts/#{p.id}/report",
             headers: { "Authorization" => "Bearer #{token}" }
        expect(response).to have_http_status(:success)
      end

      # All posts should have reports
      posts.each do |p|
        p.reload
        expect(p.report_count).to eq(1)
      end
    end
  end

  describe "Invalid input edge cases" do
    it "handles invalid post ID format" do
      token = get_token(user)

      post "#{api_base}/posts/invalid_id/report",
           headers: { "Authorization" => "Bearer #{token}" }
      expect(response).to have_http_status(:not_found)
    end

    it "handles missing authentication token" do
      post = create(:post, author: other_user)

      post "#{api_base}/posts/#{post.id}/report"
      expect(response).to have_http_status(:unauthorized)
    end

    it "handles invalid authentication token" do
      post = create(:post, author: other_user)

      post "#{api_base}/posts/#{post.id}/report",
           headers: { "Authorization" => "Bearer invalid_token" }
      expect(response).to have_http_status(:unauthorized)
    end
  end
end

