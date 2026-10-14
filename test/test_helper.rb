# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "omniauth_oidc"

require "minitest/autorun"
require "webmock/minitest"
require "rack/test"

# Disable real HTTP requests
WebMock.disable_net_connect!(allow_localhost: true)

# Keep test output readable; test_logging installs its own logger
OmniAuth.config.logger = Logger.new(IO::NULL)
OmniauthOidc::Logging.logger = Logger.new(IO::NULL)

# Temporarily replaces a singleton method. Used instead of minitest/mock, which
# minitest 6 moved into a separate gem.
module SingletonStub
  def with_singleton_stub(object, method_name, implementation)
    original = object.method(method_name)
    object.define_singleton_method(method_name, &implementation)
    yield
  ensure
    object.define_singleton_method(method_name, original)
  end
end

module OmniAuthTestHelper # rubocop:disable Metrics/ModuleLength
  # Generated once: RSA key generation is slow
  TEST_RSA_KEY = OpenSSL::PKey::RSA.new(2048)
  TEST_KID = "test_key_id"

  # Discovery and JWKS caches are process-wide, so reset them between tests
  def before_setup
    super
    OmniauthOidc::JwksCache.clear!
    OmniauthOidc::ConfigFetcher.clear_cache!
    WebMock.reset!
  end

  def app(**overrides)
    opts = strategy_options.merge(overrides)
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

  def strategy_options
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

  def mock_jwks(key: TEST_RSA_KEY, kid: TEST_KID)
    { "keys" => [JWT::JWK.new(key, kid: kid).export.merge(use: "sig")] }
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

  def id_token_claims(overrides = {})
    {
      "iss" => "https://example.com",
      "sub" => "user123",
      "aud" => "test_client_id",
      "exp" => Time.now.to_i + 3600,
      "iat" => Time.now.to_i,
      "nonce" => "test_nonce"
    }.merge(overrides)
  end

  def generate_test_id_token(claims = {}, key: TEST_RSA_KEY, algorithm: "RS256", kid: TEST_KID)
    JWT.encode(id_token_claims(claims), key, algorithm, kid ? { kid: kid } : {})
  end

  def stub_oidc_config_request(config = mock_oidc_config)
    stub_request(:get, "https://example.com/.well-known/openid-configuration")
      .to_return(status: 200, body: config.to_json, headers: { "Content-Type" => "application/json" })
  end

  def stub_jwks_request(jwks = mock_jwks)
    stub_request(:get, "https://example.com/oauth/jwks")
      .to_return(status: 200, body: jwks.to_json, headers: { "Content-Type" => "application/json" })
  end

  def stub_token_request(response_body = {}, id_token_claims: {})
    default_response = {
      "access_token" => "test_access_token",
      "token_type" => "Bearer",
      "expires_in" => 3600,
      "refresh_token" => "test_refresh_token",
      "id_token" => generate_test_id_token(id_token_claims),
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
