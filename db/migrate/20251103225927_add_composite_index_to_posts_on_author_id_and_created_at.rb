class AddCompositeIndexToPostsOnAuthorIdAndCreatedAt < ActiveRecord::Migration[8.1]
  def change
    # Composite index for efficient feed queries
    # This optimizes queries like: WHERE author_id IN (...) ORDER BY created_at DESC
    # The index order matches our query pattern (author_id first, then created_at DESC)
    add_index :posts, [:author_id, :created_at],
              name: 'index_posts_on_author_id_and_created_at',
              order: { created_at: :desc }
  end
end
