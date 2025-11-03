class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :username, limit: 50, null: false
      t.string :description, limit: 120
      t.string :password_digest, null: false

      t.timestamps
    end

    add_index :users, :username, unique: true
  end
end
