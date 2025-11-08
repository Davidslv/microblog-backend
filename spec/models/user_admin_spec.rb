require 'rails_helper'

RSpec.describe UserAdmin, type: :model do
  describe "associations" do
    it { should belong_to(:user).required }
  end

  describe "validations" do
    it "requires a user" do
      admin = UserAdmin.new
      expect(admin).not_to be_valid
      expect(admin.errors[:user]).to be_present
    end

    it "enforces uniqueness of user_id" do
      user = create(:user)
      create(:user_admin, user: user)

      duplicate = UserAdmin.new(user: user)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:user_id]).to include("has already been taken")
    end

    it "allows different users to have admin records" do
      user1 = create(:user)
      user2 = create(:user)

      admin1 = create(:user_admin, user: user1)
      admin2 = create(:user_admin, user: user2)

      expect(admin1).to be_valid
      expect(admin2).to be_valid
    end
  end

  describe "cascade behavior" do
    it "is destroyed when user is destroyed" do
      user = create(:user)
      admin = create(:user_admin, user: user)

      user.destroy

      expect(UserAdmin.find_by(id: admin.id)).to be_nil
    end
  end
end

