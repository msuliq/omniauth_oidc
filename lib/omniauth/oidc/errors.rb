# frozen_string_literal: true

module OmniauthOidc
  class Error < RuntimeError; end

  # Authentication flow errors
  class MissingCodeError < Error; end
  class MissingIdTokenError < Error; end

  # Configuration errors
  class ConfigurationError < Error; end
  class MissingConfigurationError < ConfigurationError; end

  # Token/JWT errors
  class TokenError < Error; end
  class TokenVerificationError < TokenError; end
  class TokenExpiredError < TokenError; end
  class InvalidAlgorithmError < TokenError; end
  class InvalidSignatureError < TokenError; end
  class InvalidIssuerError < TokenError; end
  class InvalidAudienceError < TokenError; end
  class InvalidNonceError < TokenError; end

  # JWKS errors
  class JwksError < Error; end
  class JwksFetchError < JwksError; end
  class KeyNotFoundError < JwksError; end
end
