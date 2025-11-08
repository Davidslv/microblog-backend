class CreateUserAdmins < ActiveRecord::Migration[8.1]
  def change
    create_table :user_admins do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.timestamps
    end
  end
end
