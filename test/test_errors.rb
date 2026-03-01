# frozen_string_literal: true

require "test_helper"

class TestErrors < Minitest::Test
  def test_missing_code_error_inherits_from_error
    assert OmniauthOidc::MissingCodeError < OmniauthOidc::Error
  end

  def test_missing_id_token_error_inherits_from_error
    assert OmniauthOidc::MissingIdTokenError < OmniauthOidc::Error
  end

  def test_configuration_error_inherits_from_error
    assert OmniauthOidc::ConfigurationError < OmniauthOidc::Error
  end

  def test_missing_configuration_error_inherits_from_configuration_error
    assert OmniauthOidc::MissingConfigurationError < OmniauthOidc::ConfigurationError
  end

  def test_token_error_inherits_from_error
    assert OmniauthOidc::TokenError < OmniauthOidc::Error
  end

  def test_token_verification_error_inherits_from_token_error
    assert OmniauthOidc::TokenVerificationError < OmniauthOidc::TokenError
  end

  def test_token_expired_error_inherits_from_token_error
    assert OmniauthOidc::TokenExpiredError < OmniauthOidc::TokenError
  end

  def test_invalid_algorithm_error_inherits_from_token_error
    assert OmniauthOidc::InvalidAlgorithmError < OmniauthOidc::TokenError
  end

  def test_invalid_signature_error_inherits_from_token_error
    assert OmniauthOidc::InvalidSignatureError < OmniauthOidc::TokenError
  end

  def test_invalid_issuer_error_inherits_from_token_error
    assert OmniauthOidc::InvalidIssuerError < OmniauthOidc::TokenError
  end

  def test_invalid_audience_error_inherits_from_token_error
    assert OmniauthOidc::InvalidAudienceError < OmniauthOidc::TokenError
  end

  def test_invalid_nonce_error_inherits_from_token_error
    assert OmniauthOidc::InvalidNonceError < OmniauthOidc::TokenError
  end

  def test_jwks_error_inherits_from_error
    assert OmniauthOidc::JwksError < OmniauthOidc::Error
  end

  def test_jwks_fetch_error_inherits_from_jwks_error
    assert OmniauthOidc::JwksFetchError < OmniauthOidc::JwksError
  end

  def test_key_not_found_error_inherits_from_jwks_error
    assert OmniauthOidc::KeyNotFoundError < OmniauthOidc::JwksError
  end

  def test_errors_can_be_raised_with_messages
    error = OmniauthOidc::MissingConfigurationError.new("Missing identifier")
    assert_equal "Missing identifier", error.message
  end

  def test_errors_are_runtime_errors
    error = OmniauthOidc::Error.new
    assert_kind_of RuntimeError, error
  end
end
