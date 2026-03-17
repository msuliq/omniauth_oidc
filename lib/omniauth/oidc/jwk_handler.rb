# frozen_string_literal: true

require "jwt"
require "openssl"

module OmniauthOidc
  # Handles JWK/JWKS operations for JWT verification
  class JwkHandler
    # Parsed key with its kid for matching
    KeyWithId = Struct.new(:kid, :keypair, keyword_init: true)

    def self.parse_jwks(jwks_data)
      return nil unless jwks_data

      jwks_data = JSON.parse(jwks_data) if jwks_data.is_a?(String)

      # Handle JWKS (set of keys)
      if jwks_data["keys"]
        jwks_data["keys"].filter_map { |key_data| jwk_to_key(key_data) }
      # Handle single JWK
      else
        [jwk_to_key(jwks_data)].compact
      end
    end

    def self.jwk_to_key(jwk_data)
      keypair = JWT::JWK.import(jwk_data).keypair
      kid = jwk_data["kid"] || jwk_data[:kid]
      KeyWithId.new(kid: kid, keypair: keypair)
    rescue StandardError => e
      OmniauthOidc::Logging.error("Failed to import JWK", error: e.message)
      nil
    end

    # Find the right key from JWKS based on kid (key ID)
    def self.find_key(keys, kid = nil)
      return keys.first&.keypair if kid.nil? || keys.size <= 1

      matched = keys.find { |k| k.kid == kid }
      if matched
        matched.keypair
      else
        OmniauthOidc::Logging.warn("No JWK found matching kid '#{kid}', falling back to first key")
        keys.first&.keypair
      end
    end
  end
end
