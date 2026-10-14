# frozen_string_literal: true

require "test_helper"

class TestConfigFetcher < Minitest::Test
  include OmniAuthTestHelper

  CONFIG_URL = "https://example.com/.well-known/openid-configuration"

  def test_fetch_returns_config
    stub_oidc_config_request

    config = OmniauthOidc::ConfigFetcher.fetch(CONFIG_URL)

    assert_equal "https://example.com", config.issuer
  end

  def test_missing_or_null_issuer_raises
    [mock_oidc_config.reject { |key, _| key == "issuer" }, mock_oidc_config.merge("issuer" => nil)].each do |doc|
      stub_oidc_config_request(doc)

      error = assert_raises(OmniauthOidc::ConfigurationError) { OmniauthOidc::ConfigFetcher.fetch(CONFIG_URL) }
      assert_match(/missing required fields: issuer/, error.message)
    end
  end

  def test_missing_authorization_endpoint_raises
    stub_oidc_config_request(mock_oidc_config.reject { |key, _| key == "authorization_endpoint" })

    assert_raises(OmniauthOidc::ConfigurationError) { OmniauthOidc::ConfigFetcher.fetch(CONFIG_URL) }
  end

  def test_missing_optional_fields_return_nil
    optional = %w[userinfo_endpoint end_session_endpoint]
    stub_oidc_config_request(mock_oidc_config.reject { |key, _| optional.include?(key) })

    config = OmniauthOidc::ConfigFetcher.fetch(CONFIG_URL)

    assert_nil config.userinfo_endpoint
    assert_nil config.end_session_endpoint
    assert_nil config.id_token_signing_alg_values_supported
  end

  def test_fetch_cached_reuses_document
    stub_oidc_config_request

    2.times { OmniauthOidc::ConfigFetcher.fetch_cached(CONFIG_URL) }

    assert_requested :get, CONFIG_URL, times: 1
  end

  def test_fetch_cached_with_zero_ttl_refetches
    stub_oidc_config_request

    2.times { OmniauthOidc::ConfigFetcher.fetch_cached(CONFIG_URL, ttl: 0) }

    assert_requested :get, CONFIG_URL, times: 2
  end

  def test_failed_fetch_is_not_cached
    stub_request(:get, CONFIG_URL).to_return(
      { status: 200, body: mock_oidc_config.merge("issuer" => nil).to_json },
      { status: 200, body: mock_oidc_config.to_json }
    )

    assert_raises(OmniauthOidc::ConfigurationError) { OmniauthOidc::ConfigFetcher.fetch_cached(CONFIG_URL) }
    assert_equal "https://example.com", OmniauthOidc::ConfigFetcher.fetch_cached(CONFIG_URL).issuer
  end
end
