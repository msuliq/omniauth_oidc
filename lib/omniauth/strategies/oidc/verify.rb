# frozen_string_literal: true

module OmniAuth
  module Strategies
    class Oidc
      # Token verification phase
      module Verify # rubocop:disable Metrics/ModuleLength
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

        # Force refresh JWKS cache and retry verification
        def public_key_with_refresh
          OmniauthOidc::Logging.info("Force refreshing JWKS cache")
          OmniauthOidc::JwksCache.invalidate(config.jwks_uri)
          @public_key = nil
          @fetch_key = nil
          public_key
        end

        private

        def fetch_key
          @fetch_key ||= OmniauthOidc::JwksCache.instance.fetch(config.jwks_uri) do
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

        def verify_id_token!(id_token)
          return unless id_token

          OmniauthOidc::Logging.instrument("id_token.verify", provider: name) do
            decoded = decode_id_token(id_token)
            verify_claims!(decoded)
            decoded
          end
        end

        def verify_claims!(decoded_token) # rubocop:disable Metrics/MethodLength
          claims = decoded_token.raw_attributes

          # Verify issuer
          if config.issuer && claims["iss"] != config.issuer
            raise OmniauthOidc::InvalidIssuerError,
                  "Issuer mismatch. Expected: #{config.issuer}, Got: #{claims["iss"]}"
          end

          # Verify audience
          audience = claims["aud"]
          expected_aud = client_options.identifier
          unless audience_matches?(audience, expected_aud)
            raise OmniauthOidc::InvalidAudienceError,
                  "Audience mismatch. Expected: #{expected_aud}, Got: #{audience}"
          end

          # Verify nonce if present
          expected_nonce = params["nonce"].presence || stored_nonce
          if expected_nonce && claims["nonce"] != expected_nonce
            raise OmniauthOidc::InvalidNonceError,
                  "Nonce mismatch. Expected: #{expected_nonce}, Got: #{claims["nonce"]}"
          end

          # Verify expiration
          if claims["exp"] && Time.at(claims["exp"].to_i) < Time.now
            raise OmniauthOidc::TokenExpiredError,
                  "Token expired at #{Time.at(claims["exp"].to_i)}"
          end

          decoded_token
        end

        def audience_matches?(audience, expected)
          return audience == expected if audience.is_a?(String)
          return audience.include?(expected) if audience.is_a?(Array)

          false
        end

        def decode_id_token(id_token)
          # First decode without verification to get the algorithm and kid
          _unverified_payload, unverified_header = JWT.decode(id_token, nil, false)
          algorithm = unverified_header["alg"]
          kid = unverified_header["kid"]

          validate_client_algorithm!(algorithm.to_sym)

          # Get the appropriate key/secret for verification
          key = keyset_for_algorithm(algorithm.to_sym, kid)

          # Decode and verify
          verify_signature!(id_token, key, algorithm)
        rescue JWT::DecodeError => e
          raise OmniauthOidc::TokenVerificationError, "Invalid JWT format: #{e.message}"
        end

        def keyset_for_algorithm(algorithm, kid = nil)
          case algorithm
          when :HS256, :HS384, :HS512
            secret
          else
            keys = public_key
            if keys.is_a?(Array)
              OmniauthOidc::JwkHandler.find_key(keys, kid)
            else
              keys
            end
          end
        end

        def verify_signature!(id_token, key, algorithm)
          # Use jwt gem to decode and verify
          payload, _header = JWT.decode(
            id_token,
            key,
            true, # verify signature
            {
              algorithm: algorithm,
              verify_expiration: false # We verify this manually in verify_claims!
            }
          )

          # Create our custom IdToken object
          OmniauthOidc::ResponseObjects::IdToken.new(payload.merge("algorithm" => algorithm))
        rescue JWT::VerificationError => e
          # Try refreshing JWKS cache and retry once
          if key.is_a?(Array) && !@signature_retry_attempted
            @signature_retry_attempted = true
            OmniauthOidc::Logging.warn("Signature verification failed, refreshing JWKS and retrying")
            refreshed_key = public_key_with_refresh
            return verify_signature!(id_token, refreshed_key, algorithm)
          end
          raise OmniauthOidc::InvalidSignatureError, "JWT signature verification failed: #{e.message}"
        rescue JWT::IncorrectAlgorithm => e
          raise OmniauthOidc::InvalidAlgorithmError, "Unexpected JWT algorithm: #{e.message}"
        end

        # Check for jwt to match defined client_signing_alg
        def validate_client_algorithm!(algorithm)
          client_signing_alg = options.client_signing_alg&.to_sym

          return unless client_signing_alg
          return if algorithm == client_signing_alg

          reason = "Received JWT is signed with #{algorithm}, but client_signing_alg is " \
                   "configured for #{client_signing_alg}"
          raise OmniauthOidc::InvalidAlgorithmError, reason
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
