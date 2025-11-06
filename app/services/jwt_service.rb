class JwtService
  SECRET_KEY = Rails.application.credentials.secret_key_base || Rails.application.secret_key_base || 'development-secret-key-change-in-production'
  ALGORITHM = 'HS256'
  EXPIRATION_TIME = 24.hours

  def self.encode(payload)
    payload = payload.dup
    payload[:exp] = EXPIRATION_TIME.from_now.to_i
    JWT.encode(payload, SECRET_KEY, ALGORITHM)
  end

  def self.decode(token)
    decoded = JWT.decode(token, SECRET_KEY, true, { algorithm: ALGORITHM })[0]
    HashWithIndifferentAccess.new(decoded)
  rescue JWT::DecodeError, JWT::ExpiredSignature, JWT::VerificationError
    nil
  end

  def self.valid?(token)
    decode(token).present?
  end
end

