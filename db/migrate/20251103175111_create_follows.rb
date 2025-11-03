class CreateFollows < ActiveRecord::Migration[8.1]
  def change
    create_table :follows, primary_key: [:follower_id, :followed_id], id: false do |t|
      t.bigint :follower_id, null: false
      t.bigint :followed_id, null: false
      t.timestamps
    end

    add_index :follows, :followed_id
    add_index :follows, [:follower_id, :followed_id], unique: true
    add_foreign_key :follows, :users, column: :followed_id, on_delete: :cascade
    add_foreign_key :follows, :users, column: :follower_id, on_delete: :cascade
  end
end
