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

        private

        def fetch_key
          @fetch_key ||= parse_jwk_key(::Oidc.http_client.get(config.jwks_uri).body)
        end

        def base64_decoded_jwt_secret
          return unless options.jwt_secret_base64

          Base64.decode64(options.jwt_secret_base64)
        end

        def verify_id_token!(id_token)
          return unless id_token

          decode_id_token(id_token).verify!(issuer: config.issuer,
                                            client_id: client_options.identifier,
                                            nonce: params["nonce"].presence || stored_nonce)
        end

        def decode_id_token(id_token)
          decoded = JSON::JWT.decode(id_token, :skip_verification)
          algorithm = decoded.algorithm.to_sym

          validate_client_algorithm!(algorithm)

          keyset =
            case algorithm
            when :HS256, :HS384, :HS512
              secret
            else
              public_key
            end

          decoded.verify!(keyset)
          ::Oidc::ResponseObject::IdToken.new(decoded)
        rescue JSON::JWK::Set::KidNotFound
          # Workaround for https://github.com/nov/json-jwt/pull/92#issuecomment-824654949
          raise if decoded&.header&.key?("kid")

          decoded = decode_with_each_key!(id_token, keyset)

          raise unless decoded

          decoded
        end

        # Check for jwt to match defined client_signing_alg
        def validate_client_algorithm!(algorithm)
          client_signing_alg = options.client_signing_alg&.to_sym

          return unless client_signing_alg
          return if algorithm == client_signing_alg

          reason = "Received JWT is signed with #{algorithm}, but client_singing_alg is \
            configured for #{client_signing_alg}"
          raise CallbackError, error: :invalid_jwt_algorithm, reason: reason, uri: params["error_uri"]
        end

        def decode!(id_token, key)
          ::Oidc::ResponseObject::IdToken.decode(id_token, key)
        end

        def decode_with_each_key!(id_token, keyset)
          return unless keyset.is_a?(JSON::JWK::Set)

          keyset.each do |key|
            begin
              decoded = decode!(id_token, key)
            rescue JSON::JWS::VerificationFailed, JSON::JWS::UnexpectedAlgorithm, JSON::JWK::UnknownAlgorithm
              next
            end

            return decoded if decoded
          end

          nil
        end

        def stored_nonce
          session.delete("omniauth.nonce")
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
        end

        def parse_jwk_key(key)
          json = key.is_a?(String) ? JSON.parse(key) : key
          return JSON::JWK::Set.new(json["keys"]) if json.key?("keys")

          JSON::JWK.new(json)
        end

        def decode(str)
          UrlSafeBase64.decode64(str).unpack1("B*").to_i(2).to_s
        end

        def user_info
          return @user_info if @user_info

          if access_token.id_token
            decoded = decode_id_token(access_token.id_token).raw_attributes

            @user_info = ::Oidc::ResponseObject::UserInfo.new(
              access_token.userinfo!.raw_attributes.merge(decoded)
            )
          else
            @user_info = access_token.userinfo!
          end
        end
      end
    end
  end
end
