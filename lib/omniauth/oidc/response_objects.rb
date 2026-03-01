# frozen_string_literal: true

module OmniauthOidc
  # Simple response objects to replace OpenIDConnect::ResponseObject classes
  module ResponseObjects
    # Represents an OIDC ID Token with claims
    class IdToken
      attr_reader :raw_attributes

      def initialize(attributes = {})
        @raw_attributes = attributes.is_a?(Hash) ? attributes : attributes.to_h
      end

      def sub
        raw_attributes["sub"]
      end

      def iss
        raw_attributes["iss"]
      end

      def aud
        raw_attributes["aud"]
      end

      def exp
        raw_attributes["exp"]
      end

      def iat
        raw_attributes["iat"]
      end

      def nonce
        raw_attributes["nonce"]
      end

      # Allow method-style access to claims
      def method_missing(method_name, *args)
        return raw_attributes[method_name.to_s] if raw_attributes.key?(method_name.to_s)

        super
      end

      def respond_to_missing?(method_name, include_private = false)
        raw_attributes.key?(method_name.to_s) || super
      end
    end

    # Represents OIDC UserInfo response
    class UserInfo
      attr_reader :raw_attributes

      def initialize(attributes = {})
        @raw_attributes = attributes.is_a?(Hash) ? attributes : attributes.to_h
      end

      # Standard OIDC claims
      def sub
        raw_attributes["sub"]
      end

      def name
        raw_attributes["name"]
      end

      def given_name
        raw_attributes["given_name"]
      end

      def family_name
        raw_attributes["family_name"]
      end

      def middle_name
        raw_attributes["middle_name"]
      end

      def nickname
        raw_attributes["nickname"]
      end

      def preferred_username
        raw_attributes["preferred_username"]
      end

      def profile
        raw_attributes["profile"]
      end

      def picture
        raw_attributes["picture"]
      end

      def website
        raw_attributes["website"]
      end

      def email
        raw_attributes["email"]
      end

      def email_verified
        raw_attributes["email_verified"]
      end

      def gender
        raw_attributes["gender"]
      end

      def birthdate
        raw_attributes["birthdate"]
      end

      def zoneinfo
        raw_attributes["zoneinfo"]
      end

      def locale
        raw_attributes["locale"]
      end

      def phone_number
        raw_attributes["phone_number"]
      end

      def phone_number_verified
        raw_attributes["phone_number_verified"]
      end

      def address
        raw_attributes["address"]
      end

      def updated_at
        raw_attributes["updated_at"]
      end

      # Allow method-style access to custom claims
      def method_missing(method_name, *args)
        return raw_attributes[method_name.to_s] if raw_attributes.key?(method_name.to_s)

        super
      end

      def respond_to_missing?(method_name, include_private = false)
        raw_attributes.key?(method_name.to_s) || super
      end
    end

    # Represents an OAuth2 Access Token
    class AccessToken
      attr_reader :access_token, :token_type, :expires_in, :refresh_token, :scope, :id_token

      def initialize(attributes = {})
        @access_token = attributes["access_token"] || attributes[:access_token]
        @token_type = attributes["token_type"] || attributes[:token_type]
        @expires_in = attributes["expires_in"] || attributes[:expires_in]
        @refresh_token = attributes["refresh_token"] || attributes[:refresh_token]
        @scope = attributes["scope"] || attributes[:scope]
        @id_token = attributes["id_token"] || attributes[:id_token]
      end

      def to_h
        {
          "access_token" => access_token,
          "token_type" => token_type,
          "expires_in" => expires_in,
          "refresh_token" => refresh_token,
          "scope" => scope,
          "id_token" => id_token
        }.compact
      end
    end
  end
end
