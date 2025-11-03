class CreatePosts < ActiveRecord::Migration[8.1]
  def change
    create_table :posts do |t|
      t.references :author, null: true, foreign_key: { to_table: :users, on_delete: :nullify }, index: true
      t.string :content, limit: 200, null: false
      t.references :parent, null: true, foreign_key: { to_table: :posts, on_delete: :nullify }, index: true

      t.timestamps
    end

    add_index :posts, :created_at
  end
end
