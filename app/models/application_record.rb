class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  # Configure read replicas
  # This tells Rails to use primary for writes and primary_replica for reads
  connects_to database: { writing: :primary, reading: :primary_replica }
end
