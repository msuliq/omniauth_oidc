# frozen_string_literal: true

require "test_helper"

class TestOmniauthOidc < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::OmniauthOidc::VERSION
  end

  def test_version_is_one_zero_zero
    assert_equal "1.0.1", ::OmniauthOidc::VERSION
  end

  def test_error_hierarchy
    assert OmniauthOidc::MissingCodeError < OmniauthOidc::Error
    assert OmniauthOidc::MissingIdTokenError < OmniauthOidc::Error
    assert OmniauthOidc::TokenError < OmniauthOidc::Error
    assert OmniauthOidc::TokenVerificationError < OmniauthOidc::TokenError
    assert OmniauthOidc::ConfigurationError < OmniauthOidc::Error
  end

  def test_logging_module_exists
    assert defined?(OmniauthOidc::Logging)
    assert OmniauthOidc::Logging.respond_to?(:logger)
    assert OmniauthOidc::Logging.respond_to?(:instrument)
  end

  def test_jwks_cache_exists
    assert defined?(OmniauthOidc::JwksCache)
    instance = OmniauthOidc::JwksCache.instance
    assert instance.respond_to?(:fetch)
    assert instance.respond_to?(:clear!)
  end
end
