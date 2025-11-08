require 'rails_helper'

RSpec.describe ModerationPolicy, type: :policy do
  let(:user) { create(:user) }
  let(:admin) { create(:user, :admin) }
  let(:post) { create(:post, author: user) }

  describe "#can_moderate?" do
    it "returns false for regular users" do
      policy = ModerationPolicy.new(user)
      expect(policy.can_moderate?).to be false
    end

    it "returns true for admin users" do
      policy = ModerationPolicy.new(admin)
      expect(policy.can_moderate?).to be true
    end
  end

  describe "#can_redact?" do
    it "returns false for regular users" do
      policy = ModerationPolicy.new(user)
      expect(policy.can_redact?(post)).to be false
    end

    it "returns true for admin users" do
      policy = ModerationPolicy.new(admin)
      expect(policy.can_redact?(post)).to be true
    end
  end

  describe "#can_unredact?" do
    it "returns false for regular users" do
      policy = ModerationPolicy.new(user)
      expect(policy.can_unredact?(post)).to be false
    end

    it "returns true for admin users" do
      policy = ModerationPolicy.new(admin)
      expect(policy.can_unredact?(post)).to be true
    end
  end

  describe "#can_view_redacted?" do
    it "returns false for regular users" do
      policy = ModerationPolicy.new(user)
      expect(policy.can_view_redacted?).to be false
    end

    it "returns true for admin users" do
      policy = ModerationPolicy.new(admin)
      expect(policy.can_view_redacted?).to be true
    end
  end

  describe "#can_view_reports?" do
    it "returns false for regular users" do
      policy = ModerationPolicy.new(user)
      expect(policy.can_view_reports?).to be false
    end

    it "returns true for admin users" do
      policy = ModerationPolicy.new(admin)
      expect(policy.can_view_reports?).to be true
    end
  end
end

