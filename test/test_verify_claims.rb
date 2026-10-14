# frozen_string_literal: true

require "test_helper"

class TestVerifyClaims < Minitest::Test
  include OmniAuthTestHelper

  NONCE_KEY = "omniauth.oidc.nonce"

  def setup
    stub_oidc_config_request
  end

  def test_valid_claims_pass
    strategy = build_strategy(session_nonce: "test_nonce")

    assert strategy.send(:verify_claims!, id_token)
  end

  def test_issuer_mismatch_raises
    strategy = build_strategy(session_nonce: "test_nonce")

    assert_raises(OmniauthOidc::InvalidIssuerError) do
      strategy.send(:verify_claims!, id_token("iss" => "https://evil.example"))
    end
  end

  def test_audience_mismatch_raises
    strategy = build_strategy(session_nonce: "test_nonce")

    assert_raises(OmniauthOidc::InvalidAudienceError) do
      strategy.send(:verify_claims!, id_token("aud" => "another_client"))
    end
  end

  def test_nonce_mismatch_raises_without_leaking_values
    strategy = build_strategy(session_nonce: "session_nonce")

    error = assert_raises(OmniauthOidc::InvalidNonceError) do
      strategy.send(:verify_claims!, id_token("nonce" => "other_nonce"))
    end
    refute_includes error.message, "session_nonce"
    refute_includes error.message, "other_nonce"
  end

  def test_nonce_from_request_params_is_ignored
    strategy = build_strategy(session_nonce: "session_nonce", params: { "nonce" => "attacker_nonce" })

    assert_raises(OmniauthOidc::InvalidNonceError) do
      strategy.send(:verify_claims!, id_token("nonce" => "attacker_nonce"))
    end
  end

  def test_nonce_is_consumed_from_session
    strategy = build_strategy(session_nonce: "test_nonce")
    strategy.send(:verify_claims!, id_token)

    assert_nil strategy.send(:session)[NONCE_KEY]
  end

  def test_nonce_is_consumed_even_when_an_earlier_check_fails
    strategy = build_strategy(session_nonce: "test_nonce")

    assert_raises(OmniauthOidc::InvalidIssuerError) do
      strategy.send(:verify_claims!, id_token("iss" => "https://evil.example"))
    end
    assert_nil strategy.send(:session)[NONCE_KEY]
  end

  def test_missing_session_nonce_raises_when_send_nonce_is_on
    strategy = build_strategy

    assert_raises(OmniauthOidc::InvalidNonceError) do
      strategy.send(:verify_claims!, id_token)
    end
  end

  def test_missing_session_nonce_passes_when_send_nonce_is_off
    strategy = build_strategy(send_nonce: false)

    assert strategy.send(:verify_claims!, id_token)
  end

  def test_missing_session_nonce_raises_for_id_token_flow_even_with_send_nonce_off
    strategy = build_strategy(send_nonce: false, response_type: "id_token")

    assert_raises(OmniauthOidc::InvalidNonceError) do
      strategy.send(:verify_claims!, id_token)
    end
  end

  def test_missing_exp_raises
    strategy = build_strategy(session_nonce: "test_nonce")
    token = id_token
    token.raw_attributes.delete("exp")

    error = assert_raises(OmniauthOidc::TokenVerificationError) do
      strategy.send(:verify_claims!, token)
    end
    assert_match(/missing the exp claim/, error.message)
  end

  def test_non_numeric_exp_raises
    strategy = build_strategy(session_nonce: "test_nonce")

    error = assert_raises(OmniauthOidc::TokenVerificationError) do
      strategy.send(:verify_claims!, id_token("exp" => { "not" => "a number" }))
    end
    assert_match(/not a number/, error.message)
  end

  def test_exp_within_default_leeway_passes
    strategy = build_strategy(session_nonce: "test_nonce")

    assert strategy.send(:verify_claims!, id_token("exp" => Time.now.to_i - 30))
  end

  def test_exp_beyond_default_leeway_raises
    strategy = build_strategy(session_nonce: "test_nonce")

    assert_raises(OmniauthOidc::TokenExpiredError) do
      strategy.send(:verify_claims!, id_token("exp" => Time.now.to_i - 120))
    end
  end

  def test_exp_with_zero_leeway_raises
    strategy = build_strategy(session_nonce: "test_nonce", clock_skew_leeway: 0)

    assert_raises(OmniauthOidc::TokenExpiredError) do
      strategy.send(:verify_claims!, id_token("exp" => Time.now.to_i - 1))
    end
  end

  def test_invalid_clock_skew_leeway_raises_configuration_error
    [-1, "60", nil].each do |leeway|
      strategy = build_strategy(session_nonce: "test_nonce", clock_skew_leeway: leeway)

      assert_raises(OmniauthOidc::ConfigurationError, "leeway #{leeway.inspect}") do
        strategy.send(:verify_claims!, id_token)
      end
    end
  end

  def test_nbf_within_leeway_decodes
    strategy = build_strategy(client_signing_alg: "HS256")

    decoded = strategy.send(:decode_id_token, hs256_token("nbf" => Time.now.to_i + 30))

    assert_equal "user123", decoded.sub
  end

  def test_nbf_beyond_leeway_raises
    strategy = build_strategy(client_signing_alg: "HS256")

    assert_raises(OmniauthOidc::TokenVerificationError) do
      strategy.send(:decode_id_token, hs256_token("nbf" => Time.now.to_i + 120))
    end
  end

  private

  def build_strategy(session_nonce: nil, params: {}, **options)
    strategy = OmniAuth::Strategies::Oidc.new(app, strategy_options.merge(options))
    session = {}
    session[NONCE_KEY] = session_nonce if session_nonce
    env = Rack::MockRequest.env_for("/auth/oidc/callback", params: params, "rack.session" => session)
    strategy.instance_variable_set(:@env, env)
    strategy
  end

  def id_token(overrides = {})
    OmniauthOidc::ResponseObjects::IdToken.new(id_token_claims(overrides))
  end

  def hs256_token(overrides = {})
    generate_test_id_token(overrides, key: "test_client_secret", algorithm: "HS256", kid: nil)
  end
end
