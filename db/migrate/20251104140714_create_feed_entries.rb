# Migration to create feed_entries table for fan-out on write architecture
# This table stores pre-computed feed entries for each user, enabling fast feed queries
# See: docs/033_FAN_OUT_ON_WRITE_IMPLEMENTATION.md
class CreateFeedEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :feed_entries do |t|
      # The user who will see this post in their feed (follower)
      t.bigint :user_id, null: false

      # The post to show in the feed
      t.bigint :post_id, null: false

      # Denormalized author_id for efficient filtering/cleanup
      # Allows us to quickly remove all entries from a specific author when unfollowing
      t.bigint :author_id, null: false

      # Post creation time (denormalized for sorting)
      # We store this to avoid JOINs when querying feeds
      t.datetime :created_at, null: false

      t.datetime :updated_at, null: false
    end

    # Index for fast feed queries: Get posts for a user, ordered by creation time
    # This is the primary query pattern: WHERE user_id = ? ORDER BY created_at DESC
    add_index :feed_entries, [ :user_id, :created_at ],
              order: { created_at: :desc },
              name: "index_feed_entries_on_user_id_and_created_at_desc"

    # Unique index to prevent duplicate feed entries
    # Ensures a post appears only once per user's feed
    add_index :feed_entries, [ :user_id, :post_id ],
              unique: true,
              name: "index_feed_entries_on_user_id_and_post_id"

    # Index for cleanup: Find all entries for a specific post (when post is deleted)
    add_index :feed_entries, :post_id,
              name: "index_feed_entries_on_post_id"

    # Index for cleanup: Find all entries from a specific author (when unfollowing)
    add_index :feed_entries, [ :user_id, :author_id ],
              name: "index_feed_entries_on_user_id_and_author_id"

    # Foreign key constraints for data integrity
    add_foreign_key :feed_entries, :users, column: :user_id, on_delete: :cascade
    add_foreign_key :feed_entries, :posts, column: :post_id, on_delete: :cascade
    add_foreign_key :feed_entries, :users, column: :author_id, on_delete: :cascade
  end
end
