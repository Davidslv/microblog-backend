require 'rails_helper'

RSpec.describe 'Auto-Redaction Integration', type: :integration do
  let(:post) { create(:post) }
  let(:report_service) { ReportService.new }
  let(:redaction_service) { RedactionService.new }
  let(:audit_logger) { AuditLogger.new }

  describe 'full auto-redaction flow' do
    it 'automatically redacts post when threshold is reached' do
      # Create 4 reports (below threshold)
      reporters = create_list(:user, 4)
      reporters.each do |reporter|
        report_service.create_report(post, reporter)
        audit_logger.log_report(post, reporter)
      end

      expect(post.reload.redacted).to be false
      expect(post.report_count).to eq(4)

      # Create 5th report (reaches threshold)
      fifth_reporter = create(:user)
      report_service.create_report(post, fifth_reporter)
      audit_logger.log_report(post, fifth_reporter)

      # Check threshold and auto-redact
      if redaction_service.check_threshold(post)
        redaction_service.auto_redact_if_threshold(post)
        audit_logger.log_redaction(post, reason: 'auto')
      end

      post.reload
      expect(post.redacted).to be true
      expect(post.redaction_reason).to eq('auto')
      expect(post.redacted_at).to be_present
    end

    it 'does not redact if threshold is not met' do
      # Create 4 reports (below threshold)
      reporters = create_list(:user, 4)
      reporters.each do |reporter|
        report_service.create_report(post, reporter)
        audit_logger.log_report(post, reporter)
      end

      # Check threshold
      result = redaction_service.auto_redact_if_threshold(post)

      expect(result).to be false
      expect(post.reload.redacted).to be false
    end

    it 'does not redact if already redacted' do
      # Redact post manually first
      redaction_service.redact(post, reason: 'manual')
      audit_logger.log_redaction(post, reason: 'manual')
      original_time = post.reload.redacted_at

      # Create 5 reports
      reporters = create_list(:user, 5)
      reporters.each do |reporter|
        report_service.create_report(post, reporter)
        audit_logger.log_report(post, reporter)
      end

      # Try to auto-redact
      result = redaction_service.auto_redact_if_threshold(post)

      expect(result).to be false
      post.reload
      expect(post.redacted_at).to eq(original_time)
    end

    it 'prevents duplicate reports from same user' do
      reporter = create(:user)

      # First report succeeds
      report_service.create_report(post, reporter)
      audit_logger.log_report(post, reporter)

      # Second report from same user fails
      expect {
        report_service.create_report(post, reporter)
      }.to raise_error(ReportService::DuplicateReportError)

      expect(post.report_count).to eq(1)
    end

    it 'prevents self-reports' do
      expect {
        report_service.create_report(post, post.author)
      }.to raise_error(ReportService::SelfReportError)

      expect(post.report_count).to eq(0)
    end

    it 'logs all actions in audit trail' do
      reporter1 = create(:user)
      reporter2 = create(:user)

      # Create reports
      report_service.create_report(post, reporter1)
      audit_logger.log_report(post, reporter1)

      report_service.create_report(post, reporter2)
      audit_logger.log_report(post, reporter2)

      # Check audit logs
      logs = ModerationAuditLog.where(post: post)
      expect(logs.count).to eq(2)
      expect(logs.pluck(:action)).to all(eq('report'))
    end

    it 'logs redaction in audit trail' do
      # Create 5 reports
      reporters = create_list(:user, 5)
      reporters.each do |reporter|
        report_service.create_report(post, reporter)
        audit_logger.log_report(post, reporter)
      end

      # Auto-redact
      if redaction_service.check_threshold(post)
        redaction_service.auto_redact_if_threshold(post)
        audit_logger.log_redaction(post, reason: 'auto')
      end

      # Check audit logs
      redaction_log = ModerationAuditLog.where(post: post, action: 'redact').last
      expect(redaction_log).to be_present
      expect(redaction_log.metadata['reason']).to eq('auto')
    end
  end
end
