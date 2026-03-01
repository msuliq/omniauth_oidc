# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "omniauth_oidc"

require "minitest/autorun"
require "webmock/minitest"
require "rack/test"

# Disable real HTTP requests
WebMock.disable_net_connect!(allow_localhost: true)

module OmniAuthTestHelper # rubocop:disable Metrics/ModuleLength
  def app
    opts = test_strategy_options
    Rack::Builder.new do
      use OmniAuth::Test::PhonySession
      use OmniAuth::Builder do
        provider :oidc, opts
      end
      run lambda { |env|
        [200, { "Content-Type" => "text/plain" }, [env["omniauth.auth"].to_json]]
      }
    end.to_app
  end

  def test_strategy_options
    {
      name: :oidc,
      client_options: {
        identifier: "test_client_id",
        secret: "test_client_secret",
        config_endpoint: "https://example.com/.well-known/openid-configuration",
        scheme: "https",
        host: "example.com",
        port: 443
      },
      issuer: "https://example.com"
    }
  end

  def mock_oidc_config
    {
      "issuer" => "https://example.com",
      "authorization_endpoint" => "https://example.com/oauth/authorize",
      "token_endpoint" => "https://example.com/oauth/token",
      "userinfo_endpoint" => "https://example.com/oauth/userinfo",
      "jwks_uri" => "https://example.com/oauth/jwks",
      "end_session_endpoint" => "https://example.com/oauth/logout",
      "scopes_supported" => %w[openid profile email],
      "response_types_supported" => %w[code id_token],
      "grant_types_supported" => ["authorization_code"]
    }
  end

  def mock_jwks
    {
      "keys" => [
        {
          "kty" => "RSA",
          "use" => "sig",
          "kid" => "test_key_id",
          "n" => "xGOr-H7A-PWGdN6bFJcS1AHj8SQj1LQJ0jZFqvTZ7bJC7dPCOZqZ4dBIp5Z2N_kPQ7cO8CqL5Qg0ZJYzV8bQw",
          "e" => "AQAB"
        }
      ]
    }
  end

  def mock_user_info
    {
      "sub" => "user123",
      "name" => "Test User",
      "email" => "test@example.com",
      "email_verified" => true,
      "preferred_username" => "testuser",
      "given_name" => "Test",
      "family_name" => "User",
      "gender" => "male",
      "picture" => "https://example.com/avatar.jpg",
      "phone_number" => "+1234567890",
      "website" => "https://testuser.com"
    }
  end

  def generate_test_id_token(claims = {})
    default_claims = {
      "iss" => "https://example.com",
      "sub" => "user123",
      "aud" => "test_client_id",
      "exp" => Time.now.to_i + 3600,
      "iat" => Time.now.to_i,
      "nonce" => "test_nonce"
    }
    JSON::JWT.new(default_claims.merge(claims)).to_s
  end

  def stub_oidc_config_request
    stub_request(:get, "https://example.com/.well-known/openid-configuration")
      .to_return(status: 200, body: mock_oidc_config.to_json, headers: { "Content-Type" => "application/json" })
  end

  def stub_jwks_request
    stub_request(:get, "https://example.com/oauth/jwks")
      .to_return(status: 200, body: mock_jwks.to_json, headers: { "Content-Type" => "application/json" })
  end

  def stub_token_request(response_body = {})
    default_response = {
      "access_token" => "test_access_token",
      "token_type" => "Bearer",
      "expires_in" => 3600,
      "refresh_token" => "test_refresh_token",
      "id_token" => generate_test_id_token,
      "scope" => "openid profile email"
    }

    stub_request(:post, "https://example.com/oauth/token")
      .to_return(
        status: 200,
        body: default_response.merge(response_body).to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  def stub_userinfo_request(user_data = nil)
    stub_request(:get, "https://example.com/oauth/userinfo")
      .to_return(
        status: 200,
        body: (user_data || mock_user_info).to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end
end
