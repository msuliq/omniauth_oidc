# frozen_string_literal: true

module OmniAuth
  module Strategies
    class Oidc
      # Callback phase - handles OIDC provider response
      module Callback # rubocop:disable Metrics/ModuleLength
        def callback_phase
          OmniauthOidc::Logging.instrument("callback_phase.start", provider: name) do
            handle_callback_errors do
              validate_callback_params!
              next missing_response_type_failure unless params.key?(configured_response_type)

              options.issuer = issuer if options.issuer.nil? || options.issuer.empty?

              client.redirect_uri = redirect_uri

              if configured_response_type == "id_token"
                handle_id_token_response
              else
                handle_code_response
              end
              verify_subject!

              super
            end
          end
        end

        private

        def handle_callback_errors
          yield
        rescue CallbackError => e
          OmniauthOidc::Logging.error("Callback error", error: e.error, reason: e.error_reason)
          fail!(e.error, e)
        rescue OmniauthOidc::ConfigurationError, OmniauthOidc::JwksError => e
          OmniauthOidc::Logging.error("Provider setup error", error: e.class.name, message: e.message)
          fail!(e.is_a?(OmniauthOidc::JwksError) ? :jwks_error : :configuration_error, e)
        rescue OmniauthOidc::TokenError => e
          OmniauthOidc::Logging.error("Token error", error: e.class.name, message: e.message)
          fail!(:token_error, e)
        rescue OmniauthOidc::HttpClient::HttpError => e
          OmniauthOidc::Logging.error("HTTP error", message: e.message)
          fail!(:http_error, e)
        rescue ::Timeout::Error, ::Errno::ETIMEDOUT => e
          OmniauthOidc::Logging.error("Timeout error", message: e.message)
          fail!(:timeout, e)
        rescue ::SocketError => e
          OmniauthOidc::Logging.error("Connection error", message: e.message)
          fail!(:failed_to_connect, e)
        end

        def validate_callback_params!
          error = params["error_reason"] || params["error"]
          error_description = params["error_description"] || params["error_reason"]
          invalid_state = (options.require_state && params["state"].to_s.empty?) || params["state"] != stored_state

          if error
            raise CallbackError, error: params["error"], error_reason: error_description,
                                 error_uri: params["error_uri"]
          end
          raise CallbackError, error: :csrf_detected, error_reason: "Invalid 'state' parameter" if invalid_state
        end

        def missing_response_type_failure
          error_attrs = RESPONSE_TYPE_EXCEPTIONS[configured_response_type]
          fail!(error_attrs[:key], error_attrs[:exception_class].new(params["error"]))
        end

        def handle_code_response
          # Get access token via token exchange
          @access_token = fetch_access_token

          # Verify the ID token from the token response once, and reuse the result below
          @verified_id_token = verify_id_token!(@access_token.id_token)

          # Fetch and set user info
          @user_info = fetch_user_info
        end

        def handle_id_token_response
          # For id_token response type, extract user data directly from the verified token
          # to_s: a bare "?id_token" param is nil and must fail verification, not skip it
          @verified_id_token = verify_id_token!(params["id_token"].to_s)
          @user_info = OmniauthOidc::ResponseObjects::UserInfo.new(@verified_id_token.raw_attributes)

          # Create a minimal access token structure for credentials
          @access_token = OmniauthOidc::ResponseObjects::AccessToken.new(
            id_token: params["id_token"],
            access_token: nil,
            refresh_token: nil,
            expires_in: nil,
            scope: nil
          )
        end

        def fetch_access_token
          OmniauthOidc::Logging.instrument("token.exchange", provider: name) do
            token_request_params = {
              code: authorization_code,
              redirect_uri: redirect_uri
            }

            # The verifier comes only from the session. Request params are attacker controlled.
            token_request_params[:code_verifier] = stored_pkce_verifier if options.pkce

            set_client_options_for_callback_phase

            client.access_token!(token_request_params)
          end
        end

        def stored_pkce_verifier
          verifier = session.delete(session_key("pkce.verifier"))
          return verifier unless verifier.to_s.empty?

          raise OmniauthOidc::TokenError, "No PKCE code verifier stored in the session for this login"
        end

        def fetch_user_info
          return minimal_user_info_from_token unless options.fetch_user_info

          userinfo_data = OmniauthOidc::Logging.instrument("userinfo.fetch", provider: name) do
            client.userinfo!(@access_token.access_token).raw_attributes
          end
          return OmniauthOidc::ResponseObjects::UserInfo.new(userinfo_data) unless @verified_id_token

          id_token_claims = @verified_id_token.raw_attributes
          # OIDC Core 5.3.4: UserInfo values must not be used unless its sub matches the ID token
          unless userinfo_data["sub"] == id_token_claims["sub"]
            OmniauthOidc::Logging.error("UserInfo sub does not match ID token sub, using ID token claims only")
            return minimal_user_info_from_token
          end

          OmniauthOidc::ResponseObjects::UserInfo.new(id_token_claims.merge(userinfo_data))
        rescue StandardError => e
          OmniauthOidc::Logging.warn("Failed to fetch userinfo, falling back to ID token", error: e.message)
          minimal_user_info_from_token
        end

        def minimal_user_info_from_token
          return empty_user_info unless @verified_id_token

          OmniauthOidc::ResponseObjects::UserInfo.new(@verified_id_token.raw_attributes)
        end

        # A login without a subject must never complete: a nil uid can match the wrong local account
        def verify_subject!
          return unless uid.to_s.empty?

          raise OmniauthOidc::TokenVerificationError, "Neither the ID token nor UserInfo provided a subject (sub)"
        end

        def empty_user_info
          OmniauthOidc::ResponseObjects::UserInfo.new({})
        end

        def configured_response_type
          @configured_response_type ||= options.response_type.to_s
        end

        # Parse response from OIDC endpoint and set client options for callback phase
        def set_client_options_for_callback_phase
          client.host = host
          client.redirect_uri = redirect_uri
          client.authorization_endpoint = config.authorization_endpoint
          client.token_endpoint = config.token_endpoint
          client.userinfo_endpoint = config.userinfo_endpoint
        end

        # Accessor for OmniAuth DSL blocks
        def user_info
          @user_info
        end

        # Accessor for OmniAuth DSL blocks
        def access_token
          @access_token
        end
      end
    end
  end
end
