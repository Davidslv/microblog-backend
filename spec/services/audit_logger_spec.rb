require 'rails_helper'

RSpec.describe AuditLogger do
  let(:post) { create(:post) }
  let(:user) { create(:user) }
  let(:admin) { create(:user) }
  let(:logger) { AuditLogger.new }

  describe '#log_report' do
    it 'creates an audit log entry' do
      expect {
        logger.log_report(post, user)
      }.to change { ModerationAuditLog.count }.by(1)
    end

    it 'logs with correct action' do
      logger.log_report(post, user)
      log = ModerationAuditLog.last
      expect(log.action).to eq('report')
    end

    it 'logs with correct post and user' do
      logger.log_report(post, user)
      log = ModerationAuditLog.last
      expect(log.post).to eq(post)
      expect(log.user).to eq(user)
    end

    it 'includes metadata' do
      logger.log_report(post, user, metadata: { report_id: 123 })
      log = ModerationAuditLog.last
      expect(log.metadata['report_id']).to eq(123)
    end
  end

  describe '#log_redaction' do
    it 'creates an audit log entry' do
      expect {
        logger.log_redaction(post, reason: 'auto')
      }.to change { ModerationAuditLog.count }.by(1)
    end

    it 'logs with correct action' do
      logger.log_redaction(post, reason: 'auto')
      log = ModerationAuditLog.last
      expect(log.action).to eq('redact')
    end

    it 'logs with correct post' do
      logger.log_redaction(post, reason: 'auto')
      log = ModerationAuditLog.last
      expect(log.post).to eq(post)
    end

    context 'with admin' do
      it 'logs admin if provided' do
        logger.log_redaction(post, reason: 'manual', admin: admin)
        log = ModerationAuditLog.last
        expect(log.admin).to eq(admin)
      end
    end

    it 'includes reason in metadata' do
      logger.log_redaction(post, reason: 'auto')
      log = ModerationAuditLog.last
      expect(log.metadata['reason']).to eq('auto')
    end
  end

  describe '#log_unredaction' do
    it 'creates an audit log entry' do
      expect {
        logger.log_unredaction(post, admin: admin)
      }.to change { ModerationAuditLog.count }.by(1)
    end

    it 'logs with correct action' do
      logger.log_unredaction(post, admin: admin)
      log = ModerationAuditLog.last
      expect(log.action).to eq('unredact')
    end

    it 'logs with correct post and admin' do
      logger.log_unredaction(post, admin: admin)
      log = ModerationAuditLog.last
      expect(log.post).to eq(post)
      expect(log.admin).to eq(admin)
    end
  end

  describe '#log' do
    it 'creates an audit log entry with custom action' do
      expect {
        logger.log(action: 'custom_action', post: post, user: user)
      }.to change { ModerationAuditLog.count }.by(1)
    end

    it 'logs with correct action' do
      logger.log(action: 'custom_action', post: post, user: user)
      log = ModerationAuditLog.last
      expect(log.action).to eq('custom_action')
    end

    it 'accepts optional metadata' do
      logger.log(action: 'test', post: post, metadata: { key: 'value' })
      log = ModerationAuditLog.last
      expect(log.metadata['key']).to eq('value')
    end
  end
end
