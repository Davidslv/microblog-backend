namespace :db do
  namespace :stats do
    desc "Show top slow queries from pg_stat_statements"
    task slow_queries: :environment do
      limit = ENV.fetch("LIMIT", 20).to_i
      
      sql = <<-SQL
        SELECT 
          LEFT(query, 100) as query_preview,
          calls,
          total_exec_time,
          mean_exec_time,
          max_exec_time,
          stddev_exec_time,
          rows,
          100.0 * shared_blks_hit / NULLIF(shared_blks_hit + shared_blks_read, 0) AS hit_percent
        FROM pg_stat_statements
        ORDER BY mean_exec_time DESC
        LIMIT #{limit};
      SQL

      results = ActiveRecord::Base.connection.execute(sql)
      
      puts "\n" + "="*120
      puts "Top #{limit} Slowest Queries (by mean execution time)"
      puts "="*120
      puts
      
      results.each do |row|
        puts "Query: #{row['query_preview']}"
        puts "  Calls: #{row['calls']}"
        puts "  Mean Time: #{row['mean_exec_time'].to_f.round(2)}ms"
        puts "  Max Time: #{row['max_exec_time'].to_f.round(2)}ms"
        puts "  Total Time: #{row['total_exec_time'].to_f.round(2)}ms"
        puts "  Rows: #{row['rows']}"
        puts "  Cache Hit: #{row['hit_percent'].to_f.round(2)}%"
        puts "-" * 120
      end
    end

    desc "Show most frequently called queries"
    task frequent_queries: :environment do
      limit = ENV.fetch("LIMIT", 20).to_i
      
      sql = <<-SQL
        SELECT 
          LEFT(query, 100) as query_preview,
          calls,
          total_exec_time,
          mean_exec_time,
          rows
        FROM pg_stat_statements
        ORDER BY calls DESC
        LIMIT #{limit};
      SQL

      results = ActiveRecord::Base.connection.execute(sql)
      
      puts "\n" + "="*120
      puts "Top #{limit} Most Frequent Queries"
      puts "="*120
      puts
      
      results.each do |row|
        puts "Query: #{row['query_preview']}"
        puts "  Calls: #{row['calls']}"
        puts "  Mean Time: #{row['mean_exec_time'].to_f.round(2)}ms"
        puts "  Total Time: #{row['total_exec_time'].to_f.round(2)}ms"
        puts "  Rows: #{row['rows']}"
        puts "-" * 120
      end
    end

    desc "Show queries with highest total execution time"
    task total_time: :environment do
      limit = ENV.fetch("LIMIT", 20).to_i
      
      sql = <<-SQL
        SELECT 
          LEFT(query, 100) as query_preview,
          calls,
          total_exec_time,
          mean_exec_time,
          rows
        FROM pg_stat_statements
        ORDER BY total_exec_time DESC
        LIMIT #{limit};
      SQL

      results = ActiveRecord::Base.connection.execute(sql)
      
      puts "\n" + "="*120
      puts "Top #{limit} Queries by Total Execution Time"
      puts "="*120
      puts
      
      results.each do |row|
        puts "Query: #{row['query_preview']}"
        puts "  Calls: #{row['calls']}"
        puts "  Total Time: #{row['total_exec_time'].to_f.round(2)}ms"
        puts "  Mean Time: #{row['mean_exec_time'].to_f.round(2)}ms"
        puts "  Rows: #{row['rows']}"
        puts "-" * 120
      end
    end

    desc "Reset pg_stat_statements statistics"
    task reset: :environment do
      ActiveRecord::Base.connection.execute("SELECT pg_stat_statements_reset();")
      puts "✅ pg_stat_statements statistics reset"
    end

    desc "Show summary statistics"
    task summary: :environment do
      sql = <<-SQL
        SELECT 
          COUNT(*) as total_queries,
          SUM(calls) as total_calls,
          SUM(total_exec_time) as total_time_ms,
          AVG(mean_exec_time) as avg_mean_time_ms,
          MAX(max_exec_time) as max_time_ms
        FROM pg_stat_statements;
      SQL

      result = ActiveRecord::Base.connection.execute(sql).first
      
      puts "\n" + "="*60
      puts "pg_stat_statements Summary"
      puts "="*60
      puts "Total Unique Queries: #{result['total_queries']}"
      puts "Total Calls: #{result['total_calls']}"
      puts "Total Execution Time: #{result['total_time_ms'].to_f.round(2)}ms"
      puts "Average Mean Time: #{result['avg_mean_time_ms'].to_f.round(2)}ms"
      puts "Maximum Execution Time: #{result['max_time_ms'].to_f.round(2)}ms"
      puts "="*60
    end
  end
end

