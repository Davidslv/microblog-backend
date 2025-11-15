require 'rails_helper'

RSpec.describe RedactionService do
  let(:post) { create(:post) }
  let(:service) { RedactionService.new }
  let(:admin) { create(:user) }

  describe '#redact' do
    context 'with valid post' do
      it 'marks post as redacted' do
        service.redact(post, reason: 'auto')
        post.reload
        expect(post.redacted).to be true
      end

      it 'sets redacted_at timestamp' do
        service.redact(post, reason: 'auto')
        post.reload
        expect(post.redacted_at).to be_present
      end

      it 'sets redaction_reason' do
        service.redact(post, reason: 'auto')
        post.reload
        expect(post.redaction_reason).to eq('auto')
      end

      it 'returns the redacted post' do
        result = service.redact(post, reason: 'auto')
        expect(result).to eq(post)
        expect(result.redacted).to be true
      end

      it 'does not redact if already redacted' do
        post.update(redacted: true, redacted_at: 1.day.ago, redaction_reason: 'manual')
        original_time = post.redacted_at

        service.redact(post, reason: 'auto')
        post.reload

        expect(post.redacted_at).to eq(original_time)
        expect(post.redaction_reason).to eq('manual')
      end

      it 'accepts admin parameter for manual redaction' do
        service.redact(post, reason: 'manual', admin: admin)
        post.reload
        expect(post.redaction_reason).to eq('manual')
      end
    end
  end

  describe '#unredact' do
    let(:redacted_post) { create(:post, :redacted) }

    context 'with valid redacted post' do
      it 'marks post as not redacted' do
        service.unredact(redacted_post)
        redacted_post.reload
        expect(redacted_post.redacted).to be false
      end

      it 'clears redacted_at' do
        service.unredact(redacted_post)
        redacted_post.reload
        expect(redacted_post.redacted_at).to be_nil
      end

      it 'clears redaction_reason' do
        service.unredact(redacted_post)
        redacted_post.reload
        expect(redacted_post.redaction_reason).to be_nil
      end

      it 'returns the unredacted post' do
        result = service.unredact(redacted_post)
        expect(result).to eq(redacted_post)
        expect(result.redacted).to be false
      end
    end

    context 'with already unredacted post' do
      it 'does not raise an error' do
        expect {
          service.unredact(post)
        }.not_to raise_error
      end

      it 'keeps post as not redacted' do
        service.unredact(post)
        post.reload
        expect(post.redacted).to be false
      end
    end
  end

  describe '#check_threshold' do
    context 'when post has less than 5 reports' do
      before do
        create_list(:report, 4, post: post)
      end

      it 'returns false' do
        expect(service.check_threshold(post)).to be false
      end
    end

    context 'when post has exactly 5 reports' do
      before do
        create_list(:report, 5, post: post)
      end

      it 'returns true' do
        expect(service.check_threshold(post)).to be true
      end
    end

    context 'when post has more than 5 reports' do
      before do
        create_list(:report, 6, post: post)
      end

      it 'returns true' do
        expect(service.check_threshold(post)).to be true
      end
    end

    context 'when post has no reports' do
      it 'returns false' do
        expect(service.check_threshold(post)).to be false
      end
    end
  end

  describe '#auto_redact_if_threshold' do
    context 'when threshold is met' do
      before do
        create_list(:report, 5, post: post)
      end

      it 'redacts the post' do
        service.auto_redact_if_threshold(post)
        post.reload
        expect(post.redacted).to be true
      end

      it 'sets redaction_reason to auto' do
        service.auto_redact_if_threshold(post)
        post.reload
        expect(post.redaction_reason).to eq('auto')
      end

      it 'returns true' do
        expect(service.auto_redact_if_threshold(post)).to be true
      end
    end

    context 'when threshold is not met' do
      before do
        create_list(:report, 4, post: post)
      end

      it 'does not redact the post' do
        service.auto_redact_if_threshold(post)
        post.reload
        expect(post.redacted).to be false
      end

      it 'returns false' do
        expect(service.auto_redact_if_threshold(post)).to be false
      end
    end

    context 'when post is already redacted' do
      let(:redacted_post) { create(:post, :redacted) }

      before do
        create_list(:report, 5, post: redacted_post)
      end

      it 'does not change redaction status' do
        original_time = redacted_post.redacted_at
        service.auto_redact_if_threshold(redacted_post)
        redacted_post.reload
        expect(redacted_post.redacted_at).to eq(original_time)
      end

      it 'returns false' do
        expect(service.auto_redact_if_threshold(redacted_post)).to be false
      end
    end
  end
end
