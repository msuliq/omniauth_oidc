# frozen_string_literal: true

require "base64"
require "timeout"
require "net/http"
require "open-uri"
require "omniauth"
require "forwardable"
require "jwt"
require "ostruct"
require "openssl"

# Explicit requires instead of Dir glob for clarity and load order control
require_relative "oidc/request"
require_relative "oidc/callback"
require_relative "oidc/verify"

module OmniAuth
  module Strategies
    # OIDC strategy for OmniAuth
    class Oidc
      include OmniAuth::Strategy
      include Request
      include Callback
      include Verify

      extend Forwardable

      RESPONSE_TYPE_EXCEPTIONS = {
        "id_token" => { exception_class: OmniauthOidc::MissingIdTokenError, key: :missing_id_token }.freeze,
        "code" => { exception_class: OmniauthOidc::MissingCodeError, key: :missing_code }.freeze
      }.freeze

      REQUIRED_OPTIONS = %i[identifier secret config_endpoint].freeze

      def_delegator :request, :params

      option :name, :oidc                                   # to separate each oidc provider available in the app
      option(:client_options, identifier: nil,              # client id, required
                              secret: nil,                  # client secret, required
                              host: nil,                    # oidc provider host, optional
                              scheme: "https",              # connection scheme, optional
                              port: 443,                    # connection port, optional
                              config_endpoint: nil,         # all data will be fetched from here, required
                              authorization_endpoint: nil,  # optional
                              token_endpoint: nil,          # optional
                              userinfo_endpoint: nil,       # optional
                              jwks_uri: nil,                # optional
                              end_session_endpoint: nil)    # optional

      option :issuer
      option :client_signing_alg
      option :jwt_secret_base64
      option :client_jwk_signing_key
      option :client_x509_signing_key
      option :scope, nil
      option :response_type, "code" # ['code', 'id_token']
      option :require_state, true
      option :state
      option :response_mode # [:query, :fragment, :form_post, :web_message]
      option :display, nil # [:page, :popup, :touch, :wap]
      option :prompt, nil # [:none, :login, :consent, :select_account]
      option :hd, nil
      option :max_age
      option :ui_locales
      option :id_token_hint
      option :acr_values
      option :send_nonce, true
      option :fetch_user_info, true
      option :send_scope_to_token_endpoint, true
      option :client_auth_method
      option :post_logout_redirect_uri
      option :extra_authorize_params, {}
      option :allow_authorize_params, []
      option :uid_field, "sub"
      option :pkce, false
      option :pkce_verifier, nil
      option :pkce_options, {
        code_challenge: proc { |verifier|
          Base64.urlsafe_encode64(Digest::SHA2.digest(verifier), padding: false)
        },
        code_challenge_method: "S256"
      }

      option :logout_path, "/logout"

      # JWKS cache configuration
      option :jwks_cache_ttl, 3600 # 1 hour default

      def uid
        user_info.raw_attributes[options.uid_field.to_sym] || user_info.sub
      end

      info do
        {
          name: user_info.name,
          email: user_info.email,
          email_verified: user_info.email_verified,
          nickname: user_info.preferred_username,
          first_name: user_info.given_name,
          last_name: user_info.family_name,
          gender: user_info.gender,
          image: user_info.picture,
          phone: user_info.phone_number,
          urls: { website: user_info.website }
        }
      end

      extra do
        { raw_info: user_info.raw_attributes }
      end

      credentials do
        {
          id_token: access_token&.id_token,
          token: access_token&.access_token,
          refresh_token: access_token&.refresh_token,
          expires_in: access_token&.expires_in,
          scope: access_token&.scope
        }
      end

      # Initialize our custom OIDC Client with options
      def client
        @client ||= begin
          set_client_endpoints
          OmniauthOidc::Client.new(
            identifier: client_options.identifier,
            secret: client_options.secret,
            authorization_endpoint: client_options.authorization_endpoint,
            token_endpoint: client_options.token_endpoint,
            userinfo_endpoint: client_options.userinfo_endpoint,
            redirect_uri: redirect_uri
          )
        end
      end

      def set_client_endpoints
        client_options.authorization_endpoint ||= config.authorization_endpoint
        client_options.token_endpoint ||= config.token_endpoint
        client_options.userinfo_endpoint ||= config.userinfo_endpoint
        client_options.jwks_uri ||= config.jwks_uri
        client_options.end_session_endpoint ||= config.end_session_endpoint
      end

      # Config is built from the json response from the OIDC config endpoint
      def config
        validate_configuration!

        @config ||= OmniauthOidc::Logging.instrument("config.fetch", config_endpoint: client_options.config_endpoint) do
          OmniauthOidc::ConfigFetcher.fetch(client_options.config_endpoint)
        end
      end

      # Detects if current request is for the logout url and makes a redirect to end session with OIDC provider
      def other_phase
        if logout_path_pattern.match?(request.url)
          options.issuer = issuer if options.issuer.to_s.empty?

          return redirect(end_session_uri) if end_session_uri
        end
        call_app!
      end

      # URL to end authenticated user's session with OIDC provider
      def end_session_uri
        return unless end_session_endpoint_is_valid?

        end_session_uri = URI(client_options.end_session_endpoint)
        end_session_uri.query = encoded_post_logout_redirect_uri
        end_session_uri.to_s
      end

      private

      def validate_configuration!
        missing = []
        missing << :identifier if client_options.identifier.to_s.empty?
        missing << :secret if client_options.secret.to_s.empty?
        missing << :config_endpoint if client_options.config_endpoint.to_s.empty?

        return if missing.empty?

        raise OmniauthOidc::MissingConfigurationError,
              "Missing required configuration: #{missing.join(", ")}"
      end

      def issuer
        @issuer ||= config.issuer
      end

      def host
        @host ||= URI.parse(config.issuer).host
      end

      # By default Returns all scopes supported by the OIDC provider
      def scope
        value = options.scope || config.scopes_supported || [:openid]
        value.is_a?(Array) ? value.join(" ") : value
      end

      def authorization_code
        params["code"]
      end

      def client_options
        options.client_options
      end

      # Session key helpers with provider namespacing
      def session_key(suffix)
        "omniauth.#{name}.#{suffix}"
      end

      def stored_state
        session.delete(session_key("state"))
      end

      def new_nonce
        session[session_key("nonce")] = SecureRandom.hex(16)
      end

      def stored_nonce
        session.delete(session_key("nonce"))
      end

      def script_name
        return "" if @env.nil?

        super
      end

      def session
        return {} if @env.nil?

        super
      end

      def redirect_uri
        "#{request.base_url}/auth/#{name}/callback"
      end

      def encoded_post_logout_redirect_uri
        return unless options.post_logout_redirect_uri

        URI.encode_www_form(
          post_logout_redirect_uri: options.post_logout_redirect_uri
        )
      end

      def end_session_endpoint_is_valid?
        client_options.end_session_endpoint &&
          client_options.end_session_endpoint =~ URI::DEFAULT_PARSER.make_regexp
      end

      def logout_path_pattern
        @logout_path_pattern ||= /\A#{Regexp.quote(request.base_url)}#{options.logout_path}/
      end

      # Override for the CallbackError class
      class CallbackError < StandardError
        attr_accessor :error, :error_reason, :error_uri

        def initialize(data)
          super
          self.error = data[:error]
          self.error_reason = data[:error_reason] || data[:reason]
          self.error_uri = data[:error_uri] || data[:uri]
        end

        def message
          [error, error_reason, error_uri].compact.join(" | ")
        end
      end
    end
  end
end

OmniAuth.config.add_camelization "OmniauthOidc", "OmniAuthOidc"
