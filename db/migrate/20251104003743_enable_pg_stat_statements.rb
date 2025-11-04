class EnablePgStatStatements < ActiveRecord::Migration[8.1]
  def up
    # Enable pg_stat_statements extension
    # This extension tracks execution statistics for all SQL statements
    execute "CREATE EXTENSION IF NOT EXISTS pg_stat_statements;"
  end

  def down
    # Disable the extension
    execute "DROP EXTENSION IF EXISTS pg_stat_statements;"
  end
end
