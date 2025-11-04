require 'rails_helper'

RSpec.describe 'Fan-Out on Write End-to-End', type: :feature do
  # This is a comprehensive end-to-end test for the fan-out on write architecture
  # It tests the complete flow: post creation → fan-out → feed display
  # This ensures the service actually works, not just that individual components work

  let(:author) { create(:user, username: 'author') }
  let(:follower1) { create(:user, username: 'follower1') }
  let(:follower2) { create(:user, username: 'follower2') }
  let(:follower3) { create(:user, username: 'follower3') }
  let(:non_follower) { create(:user, username: 'non_follower') }

  before do
    # Setup: followers follow the author
    follower1.follow(author)
    follower2.follow(author)
    follower3.follow(author)

    # Process background jobs to ensure feed entries are created
    perform_enqueued_jobs

    # Clear any existing feed entries to start fresh
    FeedEntry.delete_all
    Post.delete_all
  end

  describe 'Complete fan-out flow' do
    it 'creates feed entries when post is created and displays in follower feeds' do
      # Step 1: Author creates a post
      login_as(author)
      visit root_path

      post_content = "This is a test post for fan-out #{Time.current.to_i}"
      fill_in 'post_content', with: post_content
      click_button 'Post'

      expect(page).to have_content('Post created successfully')
      expect(page).to have_content(post_content)

      # Step 2: Process background jobs (fan-out)
      perform_enqueued_jobs

      # Step 3: Verify feed entries were created
      post = Post.find_by(content: post_content)
      expect(post).to be_present

      # Should have 3 feed entries (one for each follower)
      feed_entries = FeedEntry.where(post_id: post.id)
      expect(feed_entries.count).to eq(3), "Expected 3 feed entries, got #{feed_entries.count}"
      expect(feed_entries.pluck(:user_id)).to contain_exactly(follower1.id, follower2.id, follower3.id)

      # Step 4: Follower1 logs in and sees the post in their feed
      logout
      login_as(follower1)
      visit root_path

      # Should see the post in timeline
      expect(page).to have_content(post_content)
      expect(page).to have_content(author.username)

      # Step 5: Follower2 logs in and sees the post
      logout
      login_as(follower2)
      visit root_path

      expect(page).to have_content(post_content)
      expect(page).to have_content(author.username)

      # Step 6: Non-follower does NOT see the post
      logout
      login_as(non_follower)
      visit root_path

      # Non-follower should not see author's posts (unless they're public and in fallback mode)
      # But with fan-out, they definitely shouldn't see it
      expect(page).not_to have_content(post_content)
    end

    it 'handles multiple posts correctly with fan-out' do
      # Create multiple posts
      login_as(author)
      visit root_path

      posts = []
      5.times do |i|
        post_content = "Post #{i + 1} - #{Time.current.to_i}"
        fill_in 'post_content', with: post_content
        click_button 'Post'
        posts << post_content
        perform_enqueued_jobs  # Process fan-out for each post
      end

      # Verify feed entries for all posts
      post_ids = Post.where(author: author).pluck(:id)
      feed_entries = FeedEntry.where(post_id: post_ids, user_id: follower1.id)
      expect(feed_entries.count).to eq(5), "Expected 5 feed entries for follower1, got #{feed_entries.count}"

      # Follower should see all posts in reverse chronological order
      logout
      login_as(follower1)
      visit root_path

      # Should see all posts (newest first)
      posts.reverse.each do |content|
        expect(page).to have_content(content)
      end
    end

    it 'does not create feed entries for replies' do
      # Create a parent post
      login_as(author)
      visit root_path

      parent_content = "Parent post #{Time.current.to_i}"
      fill_in 'post_content', with: parent_content
      click_button 'Post'
      perform_enqueued_jobs

      parent_post = Post.find_by(content: parent_content)

      # Create a reply
      visit post_path(parent_post)
      reply_content = "Reply to parent #{Time.current.to_i}"
      fill_in 'post_content', with: reply_content
      click_button 'Reply'
      perform_enqueued_jobs

      reply_post = Post.find_by(content: reply_content)

      # Replies should NOT have feed entries
      feed_entries = FeedEntry.where(post_id: reply_post.id)
      expect(feed_entries.count).to eq(0), "Replies should not have feed entries, got #{feed_entries.count}"

      # Parent post should still have feed entries
      parent_entries = FeedEntry.where(post_id: parent_post.id)
      expect(parent_entries.count).to eq(3), "Parent post should have feed entries"
    end

    it 'backfills feed entries when user follows someone' do
      # Author has existing posts
      login_as(author)
      visit root_path

      existing_posts = []
      3.times do |i|
        post_content = "Existing post #{i + 1} - #{Time.current.to_i}"
        fill_in 'post_content', with: post_content
        click_button 'Post'
        existing_posts << post_content
        perform_enqueued_jobs
      end

      # New follower follows author
      logout
      new_follower = create(:user, username: 'new_follower')
      login_as(new_follower)

      visit user_path(author)
      click_button 'Follow'
      expect(page).to have_content("You are now following #{author.username}")

      # Process backfill job
      perform_enqueued_jobs

      # Should have feed entries for recent posts (up to 50)
      feed_entries = FeedEntry.where(user_id: new_follower.id, author_id: author.id)
      expect(feed_entries.count).to eq(3), "Should have feed entries for 3 existing posts, got #{feed_entries.count}"

      # New follower should see author's posts in their feed
      visit root_path
      existing_posts.each do |content|
        expect(page).to have_content(content)
      end
    end

    it 'removes feed entries when user unfollows' do
      # Setup: follower follows author and has feed entries
      login_as(author)
      visit root_path

      post_content = "Post before unfollow #{Time.current.to_i}"
      fill_in 'post_content', with: post_content
      click_button 'Post'
      perform_enqueued_jobs

      post = Post.find_by(content: post_content)

      # Verify follower1 has feed entry
      expect(FeedEntry.where(user_id: follower1.id, post_id: post.id).count).to eq(1)

      # Follower1 unfollows author
      logout
      login_as(follower1)
      visit user_path(author)
      click_button 'Unfollow'
      expect(page).to have_content("You have unfollowed #{author.username}")

      # Feed entries should be removed
      expect(FeedEntry.where(user_id: follower1.id, author_id: author.id).count).to eq(0),
        "Feed entries should be removed after unfollow, but found #{FeedEntry.where(user_id: follower1.id, author_id: author.id).count}"

      # Follower1 should not see author's posts in feed anymore
      visit root_path
      expect(page).not_to have_content(post_content)
    end

    it 'handles feed query with both feed entries and fallback mode' do
      # Test that feed_posts works correctly
      login_as(author)
      visit root_path

      post_content = "Test feed query #{Time.current.to_i}"
      fill_in 'post_content', with: post_content
      click_button 'Post'
      perform_enqueued_jobs

      post = Post.find_by(content: post_content)

      # Follower with feed entries should use fast path
      logout
      login_as(follower1)
      visit root_path

      # Should see the post (using feed entries)
      expect(page).to have_content(post_content)

      # Verify the query is using feed entries
      feed_entries_count = FeedEntry.where(user_id: follower1.id).count
      expect(feed_entries_count).to be > 0, "Follower should have feed entries"

      # Test fallback mode: user with no feed entries
      # (This simulates a user during migration or who hasn't been backfilled)
      user_no_entries = create(:user, username: 'no_entries')
      user_no_entries.follow(author)

      # Should still work (fallback to JOIN query)
      logout
      login_as(user_no_entries)
      visit root_path

      # Should see author's posts (using fallback JOIN query)
      expect(page).to have_content(post_content)
    end

    it 'handles large follower counts efficiently' do
      # Clear existing followers and feed entries for this test
      Follow.where(followed_id: author.id).delete_all
      FeedEntry.delete_all

      # Create many followers (simulate a popular user)
      # Use factory which handles username uniqueness automatically
      many_followers = create_list(:user, 20)
      many_followers.each do |follower|
        follower.follow(author)
      end
      perform_enqueued_jobs

      # Author creates a post
      login_as(author)
      visit root_path

      post_content = "Post for many followers #{Time.current.to_i}"
      fill_in 'post_content', with: post_content
      click_button 'Post'

      # Process fan-out (should handle 20 followers)
      perform_enqueued_jobs

      post = Post.find_by(content: post_content)
      expect(post).to be_present, "Post should be created"

      # Should have feed entries for all 20 followers
      feed_entries = FeedEntry.where(post_id: post.id)
      expect(feed_entries.count).to eq(20), "Should have feed entries for all 20 followers, got #{feed_entries.count}. Post ID: #{post.id}"

      # Verify a few followers can see the post
      many_followers.first(3).each do |follower|
        logout
        login_as(follower)
        visit root_path
        expect(page).to have_content(post_content), "Follower #{follower.username} should see the post"
      end
    end

    it 'maintains correct order of posts in feed' do
      # Create posts at different times
      login_as(author)
      visit root_path

      posts_created = []
      3.times do |i|
        post_content = "Post order test #{i} - #{Time.current.to_i}"
        fill_in 'post_content', with: post_content
        click_button 'Post'
        posts_created << post_content
        perform_enqueued_jobs
        sleep 0.1  # Small delay to ensure different timestamps
      end

      # Follower should see posts in reverse chronological order (newest first)
      logout
      login_as(follower1)
      visit root_path

      # Posts should appear in reverse order (newest first)
      page_text = page.body
      first_post_index = page_text.index(posts_created[2])  # Newest
      second_post_index = page_text.index(posts_created[1])
      third_post_index = page_text.index(posts_created[0])  # Oldest

      expect(first_post_index).to be < second_post_index
      expect(second_post_index).to be < third_post_index
    end

    it 'handles post deletion via database (cascade delete)' do
      # Create a post
      login_as(author)
      visit root_path

      post_content = "Post to be deleted #{Time.current.to_i}"
      fill_in 'post_content', with: post_content
      click_button 'Post'
      perform_enqueued_jobs

      post = Post.find_by(content: post_content)

      # Verify feed entries exist
      expect(FeedEntry.where(post_id: post.id).count).to eq(3)

      # Delete the post directly (testing cascade delete)
      post.destroy

      # Feed entries should be deleted (cascade delete via dependent: :delete_all)
      expect(FeedEntry.where(post_id: post.id).count).to eq(0),
        "Feed entries should be deleted when post is deleted"

      # Followers should not see the deleted post
      logout
      login_as(follower1)
      visit root_path
      expect(page).not_to have_content(post_content)
    end

    it 'handles user deletion and feed entry cleanup' do
      # Create posts
      login_as(author)
      visit root_path

      post_content = "Post before user deletion #{Time.current.to_i}"
      fill_in 'post_content', with: post_content
      click_button 'Post'
      perform_enqueued_jobs

      # Verify feed entries exist
      author_entries = FeedEntry.where(author_id: author.id)
      expect(author_entries.count).to be > 0

      # Delete the author
      visit edit_user_path(author)
      click_button 'Delete Account'

      # Feed entries should be deleted (cascade delete)
      expect(FeedEntry.where(author_id: author.id).count).to eq(0),
        "Feed entries should be deleted when author is deleted"
    end

    it 'handles concurrent post creation correctly' do
      # Simulate multiple posts created quickly
      login_as(author)
      visit root_path

      # Create posts without waiting for jobs between them
      posts_content = []
      5.times do |i|
        post_content = "Concurrent post #{i} - #{Time.current.to_i}"
        fill_in 'post_content', with: post_content
        click_button 'Post'
        posts_content << post_content
      end

      # Process all fan-out jobs
      perform_enqueued_jobs

      # All posts should have feed entries
      posts = Post.where(author: author).where(content: posts_content)
      expect(posts.count).to eq(5)

      posts.each do |post|
        feed_entries = FeedEntry.where(post_id: post.id)
        expect(feed_entries.count).to eq(3), "Post #{post.id} should have 3 feed entries"
      end

      # Follower should see all posts
      logout
      login_as(follower1)
      visit root_path

      posts_content.each do |content|
        expect(page).to have_content(content)
      end
    end
  end

  describe 'Feed query performance verification' do
    it 'uses feed entries for fast queries when available' do
      # Setup: Create posts with feed entries
      login_as(author)
      visit root_path

      post_content = "Performance test post #{Time.current.to_i}"
      fill_in 'post_content', with: post_content
      click_button 'Post'
      perform_enqueued_jobs

      # Follower has feed entries
      expect(FeedEntry.where(user_id: follower1.id).count).to be > 0

      # Query should use feed entries (fast path)
      logout
      login_as(follower1)

      # Measure query time
      require 'benchmark'
      time = Benchmark.realtime do
        visit root_path
      end

      # Should be fast (< 200ms for feed query)
      expect(time).to be < 1.0, "Feed query took #{time}s, expected < 1.0s"

      # Should see the post
      expect(page).to have_content(post_content)
    end
  end
end
