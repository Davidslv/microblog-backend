# Ensure Solid Cache always uses the primary (writing) connection
# Cache operations are writes, so they must use the primary database, not the replica
Rails.application.config.after_initialize do
  if Rails.cache.is_a?(SolidCache::Store)
    # Wrap cache store operations to ensure they use writing connection
    module SolidCacheReadReplicaFix
      # Read operations may trigger writes (e.g., deleting expired entries)
      # So we wrap read to use writing connection as well
      def read(name, options = nil)
        ActiveRecord::Base.connected_to(role: :writing) do
          super
        end
      end

      def write(name, value, options = nil)
        ActiveRecord::Base.connected_to(role: :writing) do
          super
        end
      end

      def delete(name, options = nil)
        ActiveRecord::Base.connected_to(role: :writing) do
          super
        end
      end

      def clear(options = nil)
        ActiveRecord::Base.connected_to(role: :writing) do
          super
        end
      end

      def increment(name, amount = 1, **options)
        ActiveRecord::Base.connected_to(role: :writing) do
          super
        end
      end

      def decrement(name, amount = 1, **options)
        ActiveRecord::Base.connected_to(role: :writing) do
          super
        end
      end

      # fetch reads and potentially writes, so it must use writing connection
      def fetch(name, options = nil, &block)
        ActiveRecord::Base.connected_to(role: :writing) do
          super
        end
      end
    end

    # Extend the cache store to always use writing connection
    Rails.cache.extend(SolidCacheReadReplicaFix)
  end
end
