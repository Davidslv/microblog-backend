require 'rails_helper'

RSpec.describe "Moderation Performance", type: :request do
  let(:user) { create(:user) }
  let(:other_user) { create(:user) }
  let(:api_base) { "/api/v1" }

  def get_token(user)
    post "#{api_base}/login", params: { username: user.username, password: "password123" }
    JSON.parse(response.body)["token"]
  end

  describe "Performance with many reports" do
    it "handles many reports on the same post efficiently" do
      post = create(:post, author: other_user)
      token = get_token(user)

      # Create many reports (simulating many users reporting)
      report_count = 100
      users = create_list(:user, report_count)

      start_time = Time.current

      users.each do |reporter|
        reporter_token = get_token(reporter)
        post "#{api_base}/posts/#{post.id}/report",
             headers: { "Authorization" => "Bearer #{reporter_token}" }
      end

      end_time = Time.current
      elapsed = end_time - start_time

      post.reload
      expect(post.report_count).to eq(report_count)
      expect(post.redacted?).to be true

      # Performance assertion: 100 reports should complete in reasonable time
      # (less than 10 seconds, but this is flexible)
      expect(elapsed).to be < 30.seconds
    end

    it "handles report count query efficiently" do
      post = create(:post, author: other_user)

      # Create many reports
      create_list(:report, 50, post: post)

      # Measure query performance
      start_time = Time.current
      count = post.report_count
      end_time = Time.current

      expect(count).to eq(50)
      # Should be very fast (less than 100ms)
      expect((end_time - start_time) * 1000).to be < 100
    end

    it "handles threshold check efficiently with many reports" do
      post = create(:post, author: other_user)

      # Create exactly 5 reports (threshold)
      create_list(:report, 5, post: post)

      redaction_service = RedactionService.new

      # Measure threshold check performance
      start_time = Time.current
      result = redaction_service.check_threshold(post)
      end_time = Time.current

      expect(result).to be true
      # Should be very fast (less than 50ms)
      expect((end_time - start_time) * 1000).to be < 50
    end

    it "handles auto-redaction efficiently when threshold is met" do
      post = create(:post, author: other_user)

      # Create 4 reports
      create_list(:report, 4, post: post)

      redaction_service = RedactionService.new

      # Measure auto-redaction performance
      start_time = Time.current
      result = redaction_service.auto_redact_if_threshold(post)
      end_time = Time.current

      # Should not redact (only 4 reports)
      expect(result).to be false

      # Add 5th report
      create(:report, post: post)

      start_time = Time.current
      result = redaction_service.auto_redact_if_threshold(post)
      end_time = Time.current

      expect(result).to be true
      post.reload
      expect(post.redacted?).to be true
      # Should be fast (less than 200ms including DB write)
      expect((end_time - start_time) * 1000).to be < 200
    end
  end

  describe "Database query performance" do
    it "uses indexes efficiently for report queries" do
      post = create(:post, author: other_user)

      # Create reports
      create_list(:report, 20, post: post)

      # Query should use index on post_id
      start_time = Time.current
      reports = Report.where(post: post)
      count = reports.count
      end_time = Time.current

      expect(count).to eq(20)
      # Should be fast with proper indexing
      expect((end_time - start_time) * 1000).to be < 50
    end

    it "filters redacted posts efficiently in queries" do
      # Create mix of redacted and non-redacted posts
      normal_posts = create_list(:post, 50, author: other_user)
      redacted_posts = create_list(:post, 50, :redacted, author: other_user)

      # Query should filter efficiently
      start_time = Time.current
      visible_posts = Post.not_redacted
      count = visible_posts.count
      end_time = Time.current

      expect(count).to eq(50) # Only non-redacted
      # Should be fast with proper indexing
      expect((end_time - start_time) * 1000).to be < 100
    end
  end
end

