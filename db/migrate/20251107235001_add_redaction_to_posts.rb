class AddRedactionToPosts < ActiveRecord::Migration[8.1]
  def change
    add_column :posts, :redacted, :boolean, default: false, null: false
    add_column :posts, :redacted_at, :datetime
    add_column :posts, :redaction_reason, :string

    add_index :posts, :redacted
    add_index :posts, [:redacted, :created_at]
  end
end
