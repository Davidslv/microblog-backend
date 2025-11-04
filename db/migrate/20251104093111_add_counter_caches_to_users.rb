class AddCounterCachesToUsers < ActiveRecord::Migration[8.1]
  def up
    # Add counter cache columns
    # NOTE: Backfilling is done separately via script/backfill_counter_caches.rb
    # See docs/WHY_NOT_BACKFILL_IN_MIGRATIONS.md for explanation
    add_column :users, :followers_count, :integer, default: 0, null: false
    add_column :users, :following_count, :integer, default: 0, null: false
    add_column :users, :posts_count, :integer, default: 0, null: false

    # Add indexes for better performance
    add_index :users, :followers_count
    add_index :users, :following_count
  end

  def down
    remove_index :users, :following_count if index_exists?(:users, :following_count)
    remove_index :users, :followers_count if index_exists?(:users, :followers_count)
    remove_column :users, :posts_count
    remove_column :users, :following_count
    remove_column :users, :followers_count
  end
end
