require 'rails_helper'

RSpec.describe Report, type: :model do
  describe 'associations' do
    it { should belong_to(:post) }
    it { should belong_to(:reporter).class_name('User') }
  end

  describe 'validations' do
    let(:post) { create(:post) }
    let(:reporter) { create(:user) }

    it 'requires a post' do
      report = build(:report, post: nil, reporter: reporter)
      expect(report).not_to be_valid
      expect(report.errors[:post]).to be_present
    end

    it 'requires a reporter' do
      report = build(:report, post: post, reporter: nil)
      expect(report).not_to be_valid
      expect(report.errors[:reporter]).to be_present
    end
  end

  describe 'uniqueness' do
    let(:post) { create(:post) }
    let(:reporter) { create(:user) }

    it 'prevents duplicate reports from same reporter on same post' do
      create(:report, post: post, reporter: reporter)

      duplicate_report = build(:report, post: post, reporter: reporter)
      expect(duplicate_report).not_to be_valid
      expect(duplicate_report.errors[:post_id]).to be_present
    end

    it 'allows different reporters to report the same post' do
      reporter1 = create(:user)
      reporter2 = create(:user)

      create(:report, post: post, reporter: reporter1)
      second_report = build(:report, post: post, reporter: reporter2)

      expect(second_report).to be_valid
    end

    it 'allows same reporter to report different posts' do
      post1 = create(:post)
      post2 = create(:post)

      create(:report, post: post1, reporter: reporter)
      second_report = build(:report, post: post2, reporter: reporter)

      expect(second_report).to be_valid
    end
  end

  describe 'scopes' do
    let(:post) { create(:post) }
    let(:reporter1) { create(:user) }
    let(:reporter2) { create(:user) }

    before do
      create(:report, post: post, reporter: reporter1, created_at: 2.days.ago)
      create(:report, post: post, reporter: reporter2, created_at: 1.day.ago)
    end

    describe '.for_post' do
      it 'returns all reports for a specific post' do
        other_post = create(:post)
        create(:report, post: other_post, reporter: reporter1)

        expect(Report.for_post(post).count).to eq(2)
      end
    end

    describe '.by_reporter' do
      it 'returns all reports by a specific reporter' do
        other_post = create(:post)
        create(:report, post: other_post, reporter: reporter1)

        expect(Report.by_reporter(reporter1).count).to eq(2)
      end
    end

    describe '.recent' do
      it 'orders reports by created_at descending' do
        reports = Report.recent
        expect(reports.first.created_at).to be > reports.last.created_at
      end
    end
  end
end
