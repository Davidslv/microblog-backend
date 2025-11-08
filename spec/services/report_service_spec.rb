require 'rails_helper'

RSpec.describe ReportService do
  let(:post) { create(:post) }
  let(:reporter) { create(:user) }
  let(:service) { ReportService.new }

  describe '#create_report' do
    context 'with valid parameters' do
      it 'creates a report' do
        expect {
          service.create_report(post, reporter)
        }.to change { Report.count }.by(1)
      end

      it 'returns the created report' do
        report = service.create_report(post, reporter)
        expect(report).to be_a(Report)
        expect(report.post).to eq(post)
        expect(report.reporter).to eq(reporter)
      end

      it 'persists the report' do
        report = service.create_report(post, reporter)
        expect(report).to be_persisted
      end
    end

    context 'with duplicate report' do
      before do
        create(:report, post: post, reporter: reporter)
      end

      it 'raises an error' do
        expect {
          service.create_report(post, reporter)
        }.to raise_error(ReportService::DuplicateReportError, 'Post has already been reported by this user')
      end

      it 'does not create a duplicate report' do
        expect {
          begin
            service.create_report(post, reporter)
          rescue ReportService::DuplicateReportError
          end
        }.not_to change { Report.count }
      end
    end

    context 'with self-report' do
      let(:post) { create(:post, author: reporter) }

      it 'raises an error' do
        expect {
          service.create_report(post, reporter)
        }.to raise_error(ReportService::SelfReportError, 'Cannot report your own post')
      end

      it 'does not create a report' do
        expect {
          begin
            service.create_report(post, reporter)
          rescue ReportService::SelfReportError
          end
        }.not_to change { Report.count }
      end
    end

    context 'with non-existent post' do
      it 'raises an error' do
        expect {
          service.create_report(nil, reporter)
        }.to raise_error(ArgumentError, 'Post cannot be nil')
      end
    end

    context 'with non-existent reporter' do
      it 'raises an error' do
        expect {
          service.create_report(post, nil)
        }.to raise_error(ArgumentError, 'Reporter cannot be nil')
      end
    end
  end

  describe '#can_report?' do
    context 'when post can be reported' do
      it 'returns true' do
        expect(service.can_report?(post, reporter)).to be true
      end
    end

    context 'when post is already reported by same user' do
      before do
        create(:report, post: post, reporter: reporter)
      end

      it 'returns false' do
        expect(service.can_report?(post, reporter)).to be false
      end
    end

    context 'when user tries to report their own post' do
      let(:post) { create(:post, author: reporter) }

      it 'returns false' do
        expect(service.can_report?(post, reporter)).to be false
      end
    end

    context 'when different user reports same post' do
      let(:other_reporter) { create(:user) }

      before do
        create(:report, post: post, reporter: reporter)
      end

      it 'returns true' do
        expect(service.can_report?(post, other_reporter)).to be true
      end
    end
  end

  describe '#report_count' do
    it 'returns 0 for posts with no reports' do
      expect(service.report_count(post)).to eq(0)
    end

    it 'returns the correct count of reports' do
      create_list(:report, 3, post: post)
      expect(service.report_count(post)).to eq(3)
    end
  end
end

