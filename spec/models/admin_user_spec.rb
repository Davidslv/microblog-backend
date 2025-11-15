require 'rails_helper'

RSpec.describe AdminUser, type: :model do
  describe "validations" do
    subject { build(:admin_user) }

    it { should validate_presence_of(:username) }
    it { should validate_uniqueness_of(:username) }
    it { should validate_length_of(:password).is_at_least(6).allow_blank }
    it { should have_secure_password }
  end

  describe "associations" do
    # AdminUser has no associations - it's a separate table
  end

  describe "uniqueness" do
    it "enforces unique usernames" do
      create(:admin_user, username: "admin1")
      duplicate = build(:admin_user, username: "admin1")
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:username]).to include("has already been taken")
    end

    it "allows different usernames" do
      create(:admin_user, username: "admin1")
      admin2 = create(:admin_user, username: "admin2")
      expect(admin2).to be_valid
    end
  end

  describe "password encryption" do
    it "encrypts the password" do
      admin = create(:admin_user, password: "password123")
      expect(admin.password_digest).not_to eq("password123")
      expect(admin.password_digest).to be_present
    end

    it "can authenticate with correct password" do
      admin = create(:admin_user, password: "password123")
      expect(admin.authenticate("password123")).to eq(admin)
    end

    it "cannot authenticate with incorrect password" do
      admin = create(:admin_user, password: "password123")
      expect(admin.authenticate("wrongpassword")).to be false
    end
  end
end
