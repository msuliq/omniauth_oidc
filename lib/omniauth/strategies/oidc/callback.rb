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

              options.issuer = issuer if options.issuer.nil? || options.issuer.empty?

              verify_id_token!(params["id_token"]) if configured_response_type == "id_token"

              client.redirect_uri = redirect_uri

              if configured_response_type == "id_token"
                handle_id_token_response
              else
                handle_code_response
              end

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

        def validate_callback_params! # rubocop:disable Naming/PredicateMethod
          error = params["error_reason"] || params["error"]
          error_description = params["error_description"] || params["error_reason"]
          invalid_state = (options.require_state && params["state"].to_s.empty?) || params["state"] != stored_state

          if error
            raise CallbackError, error: params["error"], error_reason: error_description,
                                 error_uri: params["error_uri"]
          end
          raise CallbackError, error: :csrf_detected, error_reason: "Invalid 'state' parameter" if invalid_state

          valid_response_type?
        end

        def handle_code_response
          # Get access token via token exchange
          @access_token = fetch_access_token

          # Verify the ID token from the token response
          verify_id_token!(@access_token.id_token) if @access_token.id_token

          # Fetch and set user info
          @user_info = fetch_user_info
        end

        def handle_id_token_response
          # For id_token response type, extract user data directly from the token
          decoded_token = decode_id_token(params["id_token"])
          @user_info = OmniauthOidc::ResponseObjects::UserInfo.new(decoded_token.raw_attributes)

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

            if options.pkce
              token_request_params[:code_verifier] =
                params["code_verifier"] || session.delete(session_key("pkce.verifier"))
            end

            set_client_options_for_callback_phase

            client.access_token!(token_request_params)
          end
        end

        def fetch_user_info
          return minimal_user_info_from_token unless options.fetch_user_info

          OmniauthOidc::Logging.instrument("userinfo.fetch", provider: name) do
            # Use our custom client to fetch userinfo
            userinfo_data = client.userinfo!(@access_token.access_token).raw_attributes

            # Merge with ID token claims if available
            if @access_token.id_token
              id_token_claims = decode_id_token(@access_token.id_token).raw_attributes
              userinfo_data = id_token_claims.merge(userinfo_data)
            end

            OmniauthOidc::ResponseObjects::UserInfo.new(userinfo_data)
          end
        rescue StandardError => e
          OmniauthOidc::Logging.warn("Failed to fetch userinfo, falling back to ID token", error: e.message)
          minimal_user_info_from_token
        end

        def minimal_user_info_from_token
          return empty_user_info unless @access_token&.id_token

          decoded = decode_id_token(@access_token.id_token)
          OmniauthOidc::ResponseObjects::UserInfo.new(decoded.raw_attributes)
        end

        def empty_user_info
          OmniauthOidc::ResponseObjects::UserInfo.new({})
        end

        def valid_response_type?
          return true if params.key?(configured_response_type)

          error_attrs = RESPONSE_TYPE_EXCEPTIONS[configured_response_type]
          fail!(error_attrs[:key], error_attrs[:exception_class].new(params["error"]))

          false
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
