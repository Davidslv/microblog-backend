class CreateReports < ActiveRecord::Migration[8.1]
  def change
    create_table :reports do |t|
      t.references :post, null: false, foreign_key: true
      t.references :reporter, null: false, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :reports, [ :post_id, :reporter_id ], unique: true, name: "index_reports_on_post_and_reporter"
    add_index :reports, [ :post_id, :created_at ]
    add_index :reports, [ :reporter_id, :created_at ]
  end
end
