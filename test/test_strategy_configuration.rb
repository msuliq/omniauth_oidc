# frozen_string_literal: true

require "test_helper"

class TestStrategyConfiguration < Minitest::Test
  include OmniAuthTestHelper

  def setup
    OmniauthOidc::JwksCache.clear!
    WebMock.reset!
  end

  def test_required_configuration_validation
    strategy = OmniAuth::Strategies::Oidc.new(app, client_options: {})

    stub_oidc_config_request

    error = assert_raises(OmniauthOidc::MissingConfigurationError) do
      strategy.send(:config)
    end

    assert_match(/identifier/, error.message)
    assert_match(/secret/, error.message)
    assert_match(/config_endpoint/, error.message)
  end

  def test_missing_identifier_validation
    strategy = OmniAuth::Strategies::Oidc.new(app,
                                              client_options: {
                                                secret: "secret",
                                                config_endpoint: "https://example.com/.well-known/openid-configuration"
                                              })

    error = assert_raises(OmniauthOidc::MissingConfigurationError) do
      strategy.send(:config)
    end

    assert_match(/identifier/, error.message)
  end

  def test_missing_secret_validation
    strategy = OmniAuth::Strategies::Oidc.new(app,
                                              client_options: {
                                                identifier: "test_id",
                                                config_endpoint: "https://example.com/.well-known/openid-configuration"
                                              })

    error = assert_raises(OmniauthOidc::MissingConfigurationError) do
      strategy.send(:config)
    end

    assert_match(/secret/, error.message)
  end

  def test_missing_config_endpoint_validation
    strategy = OmniAuth::Strategies::Oidc.new(app,
                                              client_options: {
                                                identifier: "test_id",
                                                secret: "secret"
                                              })

    error = assert_raises(OmniauthOidc::MissingConfigurationError) do
      strategy.send(:config)
    end

    assert_match(/config_endpoint/, error.message)
  end

  def test_config_fetch_success
    stub_oidc_config_request

    strategy = OmniAuth::Strategies::Oidc.new(app, test_strategy_options)
    config = strategy.send(:config)

    assert_equal "https://example.com", config.issuer
    assert_equal "https://example.com/oauth/authorize", config.authorization_endpoint
    assert_equal "https://example.com/oauth/token", config.token_endpoint
  end

  def test_session_key_namespacing
    strategy = OmniAuth::Strategies::Oidc.new(app, test_strategy_options.merge(name: :custom_provider))

    key = strategy.send(:session_key, "state")
    assert_equal "omniauth.custom_provider.state", key

    nonce_key = strategy.send(:session_key, "nonce")
    assert_equal "omniauth.custom_provider.nonce", nonce_key
  end

  def test_default_scope
    stub_oidc_config_request

    strategy = OmniAuth::Strategies::Oidc.new(app, test_strategy_options)
    scope = strategy.send(:scope)

    assert_equal "openid profile email", scope
  end

  def test_custom_scope
    stub_oidc_config_request

    strategy = OmniAuth::Strategies::Oidc.new(app, test_strategy_options.merge(scope: %w[openid custom]))
    scope = strategy.send(:scope)

    assert_equal "openid custom", scope
  end

  def test_uid_field_default
    strategy = OmniAuth::Strategies::Oidc.new(app, test_strategy_options)
    assert_equal "sub", strategy.options.uid_field
  end

  def test_uid_field_custom
    strategy = OmniAuth::Strategies::Oidc.new(app, test_strategy_options.merge(uid_field: "email"))
    assert_equal "email", strategy.options.uid_field
  end

  def test_jwks_cache_ttl_default
    strategy = OmniAuth::Strategies::Oidc.new(app, test_strategy_options)
    assert_equal 3600, strategy.options.jwks_cache_ttl
  end

  def test_jwks_cache_ttl_custom
    strategy = OmniAuth::Strategies::Oidc.new(app, test_strategy_options.merge(jwks_cache_ttl: 7200))
    assert_equal 7200, strategy.options.jwks_cache_ttl
  end

  def test_pkce_disabled_by_default
    strategy = OmniAuth::Strategies::Oidc.new(app, test_strategy_options)
    refute strategy.options.pkce
  end

  def test_pkce_can_be_enabled
    strategy = OmniAuth::Strategies::Oidc.new(app, test_strategy_options.merge(pkce: true))
    assert strategy.options.pkce
  end

  def test_send_nonce_enabled_by_default
    strategy = OmniAuth::Strategies::Oidc.new(app, test_strategy_options)
    assert strategy.options.send_nonce
  end

  def test_fetch_user_info_enabled_by_default
    strategy = OmniAuth::Strategies::Oidc.new(app, test_strategy_options)
    assert strategy.options.fetch_user_info
  end
end
