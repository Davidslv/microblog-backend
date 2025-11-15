class CreateModerationAuditLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :moderation_audit_logs do |t|
      t.string :action, null: false # report, redact, unredact
      t.references :post, null: false, foreign_key: true
      t.references :user, foreign_key: { to_table: :users } # actor (reporter, admin, etc.)
      t.references :admin, foreign_key: { to_table: :users } # if admin action
      t.jsonb :metadata # flexible storage for action-specific data
      t.timestamps
    end

    add_index :moderation_audit_logs, [ :post_id, :created_at ]
    add_index :moderation_audit_logs, [ :user_id, :created_at ]
    add_index :moderation_audit_logs, [ :action, :created_at ]
  end
end
