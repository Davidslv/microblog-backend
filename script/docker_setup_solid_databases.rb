#!/usr/bin/env ruby
# Setup script for Solid databases in Docker Compose
# Creates users and databases for Solid Cache, Queue, and Cable

# Connect to postgres database as superuser
superuser_conn = ActiveRecord::Base.establish_connection(
  adapter: 'postgresql',
  host: ENV.fetch('CACHE_DB_HOST', 'db'),
  port: ENV.fetch('CACHE_DB_PORT', '5432').to_i,
  database: 'postgres',
  username: ENV.fetch('DATABASE_USERNAME', 'postgres'),
  password: ENV.fetch('DATABASE_PASSWORD', '')
)

conn = ActiveRecord::Base.connection

# Create users
users = [
  {
    name: ENV.fetch('CACHE_DB_USERNAME', 'microblog_cache'),
    password: ENV.fetch('CACHE_DB_PASSWORD', 'cache_password')
  },
  {
    name: ENV.fetch('QUEUE_DB_USERNAME', 'microblog_queue'),
    password: ENV.fetch('QUEUE_DB_PASSWORD', 'queue_password')
  },
  {
    name: ENV.fetch('CABLE_DB_USERNAME', 'microblog_cable'),
    password: ENV.fetch('CABLE_DB_PASSWORD', 'cable_password')
  }
]

users.each do |user|
  begin
    conn.execute("CREATE USER #{conn.quote_column_name(user[:name])} WITH PASSWORD #{conn.quote(user[:password])} CREATEDB;")
    puts "Created user: #{user[:name]}"
  rescue ActiveRecord::StatementInvalid => e
    if e.message.include?('already exists')
      puts "User already exists: #{user[:name]}"
    else
      raise
    end
  end
end

puts "Solid database users setup complete!"
