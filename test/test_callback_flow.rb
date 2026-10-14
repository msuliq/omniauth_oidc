# frozen_string_literal: true

require "test_helper"

# Drives the request and callback phases through Rack, as a host app would
class TestCallbackFlow < Minitest::Test
  include OmniAuthTestHelper
  include Rack::Test::Methods

  TOKEN_URL = "https://example.com/oauth/token"

  def setup
    @request_validation_phase = OmniAuth.config.request_validation_phase
    OmniAuth.config.request_validation_phase = nil
    @app_options = {}
  end

  def teardown
    OmniAuth.config.request_validation_phase = @request_validation_phase
  end

  def app
    super(**@app_options)
  end

  def test_code_flow_succeeds_and_sends_pkce_verifier_from_session
    stub_provider
    authorize_params = start_login

    stub_token_request({}, id_token_claims: { "nonce" => authorize_params["nonce"] })
    get "/auth/oidc/callback", code: "auth_code", state: authorize_params["state"], code_verifier: "attacker"

    assert_equal "user123", auth_hash["uid"]
    assert_requested(:post, TOKEN_URL) do |req|
      verifier = URI.decode_www_form(req.body).to_h["code_verifier"]
      verifier != "attacker" && pkce_challenge(verifier) == authorize_params["code_challenge"]
    end
  end

  def test_callback_fails_without_pkce_verifier_in_session
    stub_provider
    stub_token_request

    get "/auth/oidc/callback", { code: "auth_code", state: "s", code_verifier: "attacker" },
        "rack.session" => { "omniauth.oidc.state" => "s", "omniauth.oidc.nonce" => "test_nonce" }

    assert_failure "token_error"
    assert_not_requested :post, TOKEN_URL
  end

  def test_userinfo_with_different_sub_is_ignored
    stub_provider(userinfo: mock_user_info.merge("sub" => "someone_else", "email" => "evil@example.com"))
    authorize_params = start_login

    stub_token_request({}, id_token_claims: { "nonce" => authorize_params["nonce"] })
    get "/auth/oidc/callback", code: "auth_code", state: authorize_params["state"]

    assert_equal "user123", auth_hash["uid"]
    refute_equal "evil@example.com", auth_hash.dig("info", "email")
  end

  def test_missing_code_fails_once_without_token_request
    stub_provider
    authorize_params = start_login

    get "/auth/oidc/callback", state: authorize_params["state"]

    assert_failure "missing_code"
    assert_not_requested :post, TOKEN_URL
  end

  def test_discovery_without_issuer_fails_gracefully
    stub_oidc_config_request(mock_oidc_config.merge("issuer" => nil))

    post "/auth/oidc"

    assert_failure "configuration_error"
  end

  def test_login_without_subject_fails
    @app_options = { pkce: false, send_nonce: false, fetch_user_info: false }
    stub_provider
    stub_token_request({ "id_token" => nil })

    get "/auth/oidc/callback", { code: "auth_code", state: "s" }, "rack.session" => { "omniauth.oidc.state" => "s" }

    assert_failure "token_error"
  end

  def test_id_token_flow_with_empty_id_token_param_fails
    @app_options = { response_type: "id_token" }
    stub_provider

    get "/auth/oidc/callback?id_token&state=s", {}, "rack.session" => { "omniauth.oidc.state" => "s" }

    assert_failure "token_error"
  end

  def test_discovery_document_is_fetched_once_across_requests
    stub_provider
    2.times { start_login }

    assert_requested :get, "https://example.com/.well-known/openid-configuration", times: 1
  end

  private

  def stub_provider(userinfo: nil)
    stub_oidc_config_request
    stub_jwks_request
    stub_userinfo_request(userinfo)
  end

  # Runs the request phase and returns the authorization request params
  def start_login
    post "/auth/oidc"
    assert_equal 302, last_response.status
    URI.decode_www_form(URI(last_response.location).query).to_h
  end

  def auth_hash
    assert_equal 200, last_response.status, last_response.location
    JSON.parse(last_response.body)
  end

  def assert_failure(message)
    assert_equal 302, last_response.status
    assert_includes last_response.location, "/auth/failure?message=#{message}"
  end

  def pkce_challenge(verifier)
    Base64.urlsafe_encode64(Digest::SHA256.digest(verifier.to_s), padding: false)
  end
end
