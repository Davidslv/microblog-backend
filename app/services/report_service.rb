class ReportService
  class DuplicateReportError < StandardError; end
  class SelfReportError < StandardError; end

  def initialize(weight_calculator: nil)
    @weight_calculator = weight_calculator
  end

  def create_report(post, reporter)
    validate_report(post, reporter)

    Report.create!(post: post, reporter: reporter)
  end

  def can_report?(post, reporter)
    return false if post.nil? || reporter.nil?
    return false if post.author_id == reporter.id # Self-report prevention
    return false if Report.exists?(post: post, reporter: reporter) # Duplicate prevention

    true
  end

  def report_count(post)
    post.reports.count
  end

  private

  def validate_report(post, reporter)
    raise ArgumentError, 'Post cannot be nil' if post.nil?
    raise ArgumentError, 'Reporter cannot be nil' if reporter.nil?
    raise SelfReportError, 'Cannot report your own post' if post.author_id == reporter.id
    raise DuplicateReportError, 'Post has already been reported by this user' if Report.exists?(post: post, reporter: reporter)
  end
end

