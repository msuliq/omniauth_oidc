# frozen_string_literal: true

module OmniAuth
  module Strategies
    class Oidc
      # Token verification phase
      module Verify # rubocop:disable Metrics/ModuleLength
        HMAC_ALGORITHMS = %w[HS256 HS384 HS512].freeze

        # Algorithm assumed when neither client_signing_alg nor the discovery document names one
        DEFAULT_SIGNING_ALGORITHM = "RS256"

        # Minimum seconds between JWKS refreshes triggered by an unknown kid, so tokens with
        # made-up kids cannot be used to hammer the provider's JWKS endpoint.
        JWKS_REFRESH_MIN_INTERVAL = 60

        def secret
          base64_decoded_jwt_secret || client_options.secret
        end

        # https://tools.ietf.org/html/rfc7636#appendix-A
        def pkce_authorize_params(verifier)
          {
            code_challenge: options.pkce_options[:code_challenge].call(verifier),
            code_challenge_method: options.pkce_options[:code_challenge_method]
          }
        end

        # Looks for key defined in omniauth initializer, if none is defined
        # falls back to using jwks_uri returned by OIDC config_endpoint
        def public_key
          @public_key ||= if configured_public_key
                            configured_public_key
                          elsif config.jwks_uri
                            fetch_key
                          end
        end

        # Refetch the JWKS, at most once per JWKS_REFRESH_MIN_INTERVAL for each jwks_uri
        def public_key_with_refresh
          return public_key if configured_public_key || config.jwks_uri.nil?

          OmniauthOidc::Logging.info("Refreshing JWKS", jwks_uri: config.jwks_uri)
          @public_key = fetch_key(force_refresh: true)
        end

        private

        def fetch_key(force_refresh: false)
          OmniauthOidc::JwksCache.instance.fetch(config.jwks_uri, force_refresh: force_refresh,
                                                                  ttl: options.jwks_cache_ttl.to_i,
                                                                  min_age: JWKS_REFRESH_MIN_INTERVAL) do
            OmniauthOidc::Logging.instrument("jwks.fetch", jwks_uri: config.jwks_uri) do
              response = OmniauthOidc::HttpClient.get(config.jwks_uri)
              OmniauthOidc::JwkHandler.parse_jwks(response)
            end
          end
        rescue StandardError => e
          OmniauthOidc::Logging.error("Failed to fetch JWKS", error: e.message, jwks_uri: config.jwks_uri)
          raise OmniauthOidc::JwksFetchError, "Failed to fetch JWKS from #{config.jwks_uri}: #{e.message}"
        end

        def base64_decoded_jwt_secret
          return unless options.jwt_secret_base64

          Base64.decode64(options.jwt_secret_base64)
        end

        # An empty key lets anyone forge HS* tokens (CVE-2026-45363), so never verify with one
        def hmac_secret
          key = secret.to_s
          return key unless key.empty?

          raise OmniauthOidc::ConfigurationError, "HMAC secret for ID token verification is empty"
        end

        def verify_id_token!(id_token)
          return unless id_token

          OmniauthOidc::Logging.instrument("id_token.verify", provider: name) do
            decoded = decode_id_token(id_token)
            verify_claims!(decoded)
            decoded
          end
        end

        def verify_claims!(decoded_token)
          claims = decoded_token.raw_attributes

          # Consume the nonce before any check can fail, so it stays single use
          expected_nonce = stored_nonce

          verify_issuer!(claims)
          verify_audience!(claims)
          verify_nonce!(claims, expected_nonce)
          verify_expiration!(claims)

          decoded_token
        end

        # The discovery document is validated to always carry an issuer, so this check
        # cannot be skipped by a provider that omits it.
        def verify_issuer!(claims)
          return if claims["iss"] == config.issuer

          raise OmniauthOidc::InvalidIssuerError,
                "Issuer mismatch. Expected: #{config.issuer}, Got: #{claims["iss"]}"
        end

        def verify_audience!(claims)
          audience = claims["aud"]
          expected_aud = client_options.identifier
          return if audience_matches?(audience, expected_aud)

          raise OmniauthOidc::InvalidAudienceError,
                "Audience mismatch. Expected: #{expected_aud}, Got: #{audience}"
        end

        # The expected nonce comes only from the session. Never read it from request params:
        # the caller controls those. Nonce values are left out of messages because they end
        # up in logs.
        def verify_nonce!(claims, expected_nonce)
          if expected_nonce.nil?
            return unless nonce_required?

            raise OmniauthOidc::InvalidNonceError, "No nonce stored in the session for this login"
          end
          return if claims["nonce"] == expected_nonce

          raise OmniauthOidc::InvalidNonceError, "ID token nonce does not match the authorization request"
        end

        # OIDC Core 3.2.2.1 requires a nonce for the implicit (id_token) flow, so it is
        # always used there, regardless of send_nonce.
        def nonce_required?
          options.send_nonce || options.response_type.to_s == "id_token"
        end

        # exp is required by OIDC Core 3.1.3.7 and must be a NumericDate (RFC 7519 2).
        # Clock skew between us and the provider is tolerated up to clock_skew_leeway.
        def verify_expiration!(claims)
          exp = claims["exp"]
          raise OmniauthOidc::TokenVerificationError, "ID token is missing the exp claim" if exp.nil?
          raise OmniauthOidc::TokenVerificationError, "ID token exp claim is not a number" unless exp.is_a?(Numeric)
          return if Time.now.to_i < exp + clock_skew_leeway

          raise OmniauthOidc::TokenExpiredError, "Token expired at #{Time.at(exp)}"
        end

        def audience_matches?(audience, expected)
          return audience == expected if audience.is_a?(String)
          return audience.include?(expected) if audience.is_a?(Array)

          false
        end

        def clock_skew_leeway
          leeway = options.clock_skew_leeway
          return leeway if leeway.is_a?(Integer) && leeway >= 0

          raise OmniauthOidc::ConfigurationError,
                "clock_skew_leeway must be a non-negative Integer, got #{leeway.inspect}"
        end

        def decode_id_token(id_token)
          # First decode without verification to get the algorithm and kid
          _unverified_payload, unverified_header = JWT.decode(id_token, nil, false)
          algorithm = unverified_header["alg"].to_s

          validate_algorithm!(algorithm)

          # Get the appropriate key/secret for verification
          key = keyset_for_algorithm(algorithm, unverified_header["kid"])

          # Decode and verify
          verify_signature!(id_token, key, algorithm)
        rescue JWT::DecodeError => e
          raise OmniauthOidc::TokenVerificationError, "Invalid JWT format: #{e.message}"
        end

        def keyset_for_algorithm(algorithm, kid = nil)
          return hmac_secret if HMAC_ALGORITHMS.include?(algorithm)

          keys = public_key
          return keys unless keys.is_a?(Array)

          # The provider may have rotated its signing keys since the JWKS was cached
          keys = public_key_with_refresh if kid && keys.none? { |key| key.kid == kid }
          OmniauthOidc::JwkHandler.find_key(keys, kid)
        end

        def verify_signature!(id_token, key, algorithm)
          payload, _header = JWT.decode(
            id_token,
            key,
            true, # verify signature
            # exp is verified manually in verify_claims!
            { algorithm: algorithm, verify_expiration: false, nbf_leeway: clock_skew_leeway }
          )

          # Create our custom IdToken object
          OmniauthOidc::ResponseObjects::IdToken.new(payload.merge("algorithm" => algorithm))
        rescue JWT::VerificationError => e
          raise OmniauthOidc::InvalidSignatureError, "JWT signature verification failed: #{e.message}"
        rescue JWT::IncorrectAlgorithm => e
          raise OmniauthOidc::InvalidAlgorithmError, "Unexpected JWT algorithm: #{e.message}"
        end

        # The token header is attacker controlled, so the accepted algorithms come from
        # configuration only. "none" is never accepted.
        def validate_algorithm!(algorithm)
          allowed = allowed_signing_algorithms
          return if allowed.include?(algorithm)

          raise OmniauthOidc::InvalidAlgorithmError,
                "Received JWT is signed with #{algorithm.empty? ? "no algorithm" : algorithm}, " \
                "but only #{allowed.empty? ? "signed tokens" : allowed.join(", ")} are accepted"
        end

        # client_signing_alg when set, otherwise the algorithms the discovery document
        # advertises for ID tokens, otherwise RS256.
        def allowed_signing_algorithms
          algorithms = if options.client_signing_alg
                         [options.client_signing_alg]
                       else
                         Array(config.id_token_signing_alg_values_supported)
                       end
          algorithms = [DEFAULT_SIGNING_ALGORITHM] if algorithms.empty?

          algorithms.map(&:to_s) - ["none"]
        end

        def configured_public_key
          @configured_public_key ||= if options.client_jwk_signing_key
                                       parse_jwk_key(options.client_jwk_signing_key)
                                     elsif options.client_x509_signing_key
                                       parse_x509_key(options.client_x509_signing_key)
                                     end
        end

        def parse_x509_key(key)
          OpenSSL::X509::Certificate.new(key).public_key
        rescue OpenSSL::X509::CertificateError => e
          raise OmniauthOidc::TokenVerificationError, "Invalid X.509 certificate: #{e.message}"
        end

        def parse_jwk_key(key)
          json = key.is_a?(String) ? JSON.parse(key) : key
          OmniauthOidc::JwkHandler.parse_jwks(json)
        rescue JSON::ParserError => e
          raise OmniauthOidc::TokenVerificationError, "Invalid JWK format: #{e.message}"
        end
      end
    end
  end
end
