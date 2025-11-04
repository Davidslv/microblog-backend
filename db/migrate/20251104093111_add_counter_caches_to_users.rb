class AddCounterCachesToUsers < ActiveRecord::Migration[8.1]
  def up
    # Add counter cache columns
    add_column :users, :followers_count, :integer, default: 0, null: false
    add_column :users, :following_count, :integer, default: 0, null: false
    add_column :users, :posts_count, :integer, default: 0, null: false
    
    # Add indexes for better performance
    add_index :users, :followers_count
    add_index :users, :following_count
    
    # Backfill counter caches using efficient SQL queries
    puts "Backfilling counter caches (this may take a while)..."
    
    # Backfill followers_count
    execute <<-SQL
      UPDATE users
      SET followers_count = (
        SELECT COUNT(*)
        FROM follows
        WHERE follows.followed_id = users.id
      )
    SQL
    
    # Backfill following_count
    execute <<-SQL
      UPDATE users
      SET following_count = (
        SELECT COUNT(*)
        FROM follows
        WHERE follows.follower_id = users.id
      )
    SQL
    
    # Backfill posts_count
    execute <<-SQL
      UPDATE users
      SET posts_count = (
        SELECT COUNT(*)
        FROM posts
        WHERE posts.author_id = users.id
      )
    SQL
    
    puts "Counter caches backfilled!"
  end

  def down
    remove_index :users, :following_count if index_exists?(:users, :following_count)
    remove_index :users, :followers_count if index_exists?(:users, :followers_count)
    remove_column :users, :posts_count
    remove_column :users, :following_count
    remove_column :users, :followers_count
  end
end
