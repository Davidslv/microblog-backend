class RemoveAdminFromUsers < ActiveRecord::Migration[8.1]
  def change
    remove_column :users, :admin, :boolean
    remove_index :users, :admin if index_exists?(:users, :admin)
  end
end
