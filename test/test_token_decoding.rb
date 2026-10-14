# frozen_string_literal: true

require "test_helper"

class TestTokenDecoding < Minitest::Test
  include OmniAuthTestHelper
  include SingletonStub

  Oidc = OmniAuth::Strategies::Oidc
  JWKS_URL = "https://example.com/oauth/jwks"

  def test_rs256_token_signed_by_jwks_key_decodes
    stub_oidc_config_request
    stub_jwks_request

    decoded = build_strategy.send(:decode_id_token, generate_test_id_token)

    assert_equal "user123", decoded.sub
  end

  def test_unsigned_alg_none_token_is_rejected
    stub_oidc_config_request
    stub_jwks_request

    assert_raises(OmniauthOidc::InvalidAlgorithmError) do
      build_strategy.send(:decode_id_token, unsigned_token)
    end
  end

  def test_alg_none_is_rejected_even_when_advertised_or_configured
    stub_oidc_config_request(mock_oidc_config.merge("id_token_signing_alg_values_supported" => %w[none]))
    stub_jwks_request

    assert_raises(OmniauthOidc::InvalidAlgorithmError) do
      build_strategy.send(:decode_id_token, unsigned_token)
    end
    assert_raises(OmniauthOidc::InvalidAlgorithmError) do
      build_strategy(client_signing_alg: "none").send(:decode_id_token, unsigned_token)
    end
  end

  def test_hs256_is_rejected_when_not_configured_or_advertised
    stub_oidc_config_request

    assert_raises(OmniauthOidc::InvalidAlgorithmError) do
      build_strategy.send(:decode_id_token, hs256_token("test_client_secret"))
    end
  end

  def test_hs256_is_accepted_when_advertised_by_discovery
    stub_oidc_config_request(mock_oidc_config.merge("id_token_signing_alg_values_supported" => %w[RS256 HS256]))

    decoded = build_strategy.send(:decode_id_token, hs256_token("test_client_secret"))

    assert_equal "user123", decoded.sub
  end

  def test_client_signing_alg_overrides_discovery
    stub_oidc_config_request(mock_oidc_config.merge("id_token_signing_alg_values_supported" => %w[RS256 HS256]))
    stub_jwks_request

    assert_raises(OmniauthOidc::InvalidAlgorithmError) do
      build_strategy(client_signing_alg: "RS256").send(:decode_id_token, hs256_token("test_client_secret"))
    end
  end

  def test_empty_hmac_secret_is_refused
    stub_oidc_config_request

    ["", "!!!"].each do |encoded_secret|
      strategy = build_strategy(client_signing_alg: "HS256", jwt_secret_base64: encoded_secret)

      assert_raises(OmniauthOidc::ConfigurationError, "jwt_secret_base64 #{encoded_secret.inspect}") do
        strategy.send(:decode_id_token, hs256_token("any_secret"))
      end
    end
  end

  def test_unknown_kid_refreshes_jwks_after_key_rotation
    stub_oidc_config_request
    rotated_key = OpenSSL::PKey::RSA.new(2048)
    stub_request(:get, JWKS_URL).to_return(
      { status: 200, body: mock_jwks.to_json },
      { status: 200, body: mock_jwks(key: rotated_key, kid: "rotated").to_json }
    )
    build_strategy.send(:decode_id_token, generate_test_id_token)

    later = Time.now + Oidc::Verify::JWKS_REFRESH_MIN_INTERVAL + 1
    decoded = with_singleton_stub(Time, :now, proc { later }) do
      build_strategy.send(:decode_id_token, generate_test_id_token({}, key: rotated_key, kid: "rotated"))
    end

    assert_equal "user123", decoded.sub
    assert_requested :get, JWKS_URL, times: 2
  end

  def test_unknown_kid_refresh_is_rate_limited
    stub_oidc_config_request
    stub_jwks_request
    build_strategy.send(:decode_id_token, generate_test_id_token)

    3.times do
      assert_raises(OmniauthOidc::InvalidSignatureError) do
        build_strategy.send(:decode_id_token, generate_test_id_token({}, key: OpenSSL::PKey::RSA.new(2048),
                                                                         kid: "made_up"))
      end
    end
    assert_requested :get, JWKS_URL, times: 1
  end

  def test_jwks_cache_ttl_option_is_honored
    stub_oidc_config_request
    stub_jwks_request

    2.times { build_strategy(jwks_cache_ttl: 0).send(:decode_id_token, generate_test_id_token) }

    assert_requested :get, JWKS_URL, times: 2
  end

  private

  def build_strategy(**options)
    strategy = Oidc.new(app, strategy_options.merge(options))
    strategy.instance_variable_set(:@env, Rack::MockRequest.env_for("/auth/oidc/callback", "rack.session" => {}))
    strategy
  end

  def hs256_token(secret)
    generate_test_id_token({}, key: secret, algorithm: "HS256", kid: nil)
  end

  def unsigned_token
    encode = ->(part) { Base64.urlsafe_encode64(part.to_json, padding: false) }
    "#{encode.call({ "alg" => "none", "typ" => "JWT" })}.#{encode.call(id_token_claims)}."
  end
end
