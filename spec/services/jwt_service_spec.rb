require 'rails_helper'

RSpec.describe JwtService do
  let(:user) { create(:user) }
  let(:payload) { { user_id: user.id } }

  describe ".encode" do
    it "encodes a payload into a JWT token" do
      token = JwtService.encode(payload)

      expect(token).to be_a(String)
      expect(token.split('.').length).to eq(3) # JWT has 3 parts
    end

    it "includes expiration time in token" do
      token = JwtService.encode(payload)
      decoded = JwtService.decode(token)

      expect(decoded[:exp]).to be_present
      expect(decoded[:exp]).to be > Time.now.to_i
    end

    it "includes user_id in token" do
      token = JwtService.encode(payload)
      decoded = JwtService.decode(token)

      expect(decoded[:user_id]).to eq(user.id)
    end
  end

  describe ".decode" do
    it "decodes a valid JWT token" do
      token = JwtService.encode(payload)
      decoded = JwtService.decode(token)

      expect(decoded).to be_a(HashWithIndifferentAccess)
      expect(decoded[:user_id]).to eq(user.id)
    end

    it "returns nil for invalid token" do
      decoded = JwtService.decode("invalid.token.here")

      expect(decoded).to be_nil
    end

    it "returns nil for expired token" do
      # Create token with past expiration
      expired_payload = payload.dup
      expired_payload[:exp] = 1.hour.ago.to_i
      token = JWT.encode(expired_payload, JwtService::SECRET_KEY, JwtService::ALGORITHM)

      decoded = JwtService.decode(token)

      expect(decoded).to be_nil
    end

    it "returns nil for tampered token" do
      token = JwtService.encode(payload)
      tampered_token = token[0..-5] + "XXXX"

      decoded = JwtService.decode(tampered_token)

      expect(decoded).to be_nil
    end
  end

  describe ".valid?" do
    it "returns true for valid token" do
      token = JwtService.encode(payload)

      expect(JwtService.valid?(token)).to be true
    end

    it "returns false for invalid token" do
      expect(JwtService.valid?("invalid.token")).to be false
    end

    it "returns false for expired token" do
      expired_payload = payload.dup
      expired_payload[:exp] = 1.hour.ago.to_i
      token = JWT.encode(expired_payload, JwtService::SECRET_KEY, JwtService::ALGORITHM)

      expect(JwtService.valid?(token)).to be false
    end
  end
end
