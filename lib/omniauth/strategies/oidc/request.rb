# frozen_string_literal: true

module OmniAuth
  module Strategies
    class Oidc
      # Code request phase
      module Request
        def request_phase
          OmniauthOidc::Logging.instrument("request_phase.start", provider: name) do
            @identifier = client_options.identifier
            @secret = secret

            set_client_options_for_request_phase
            redirect authorize_uri
          end
        end

        def authorize_uri # rubocop:disable Metrics/AbcSize
          opts = request_options

          opts.merge!(options.extra_authorize_params) unless options.extra_authorize_params.empty?

          options.allow_authorize_params.each do |key|
            opts[key] = request.params[key.to_s] unless opts.key?(key)
          end

          if options.pkce
            verifier = options.pkce_verifier ? options.pkce_verifier.call : SecureRandom.hex(64)

            opts.merge!(pkce_authorize_params(verifier))
            session[session_key("pkce.verifier")] = verifier
          end

          # Add redirect_uri and extra_params to opts
          opts[:redirect_uri] = redirect_uri
          opts[:extra_params] = opts.compact

          client.authorization_uri(opts)
        end

        private

        def request_options
          {
            response_type: options.response_type,
            response_mode: options.response_mode,
            scope: scope,
            state: new_state,
            login_hint: params["login_hint"],
            ui_locales: params["ui_locales"],
            claims_locales: params["claims_locales"],
            prompt: options.prompt,
            nonce: (new_nonce if options.send_nonce),
            hd: options.hd,
            acr_values: options.acr_values
          }
        end

        def new_state
          state = if options.state.respond_to?(:call)
                    if options.state.arity == 1
                      options.state.call(env)
                    else
                      options.state.call
                    end
                  end
          session[session_key("state")] = state || SecureRandom.hex(16)
        end

        # Parse response from OIDC endpoint and set client options for request phase
        def set_client_options_for_request_phase
          client_options.host = host
          client_options.authorization_endpoint = config.authorization_endpoint
          client_options.token_endpoint = config.token_endpoint
          client_options.userinfo_endpoint = config.userinfo_endpoint
          client_options.jwks_uri = config.jwks_uri

          return unless config.respond_to?(:end_session_endpoint) && config.end_session_endpoint

          client_options.end_session_endpoint = config.end_session_endpoint
        end
      end
    end
  end
end
