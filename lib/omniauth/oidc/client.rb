# frozen_string_literal: true

require "base64"

module OmniauthOidc
  # Custom OIDC client using Net::HTTP
  class Client
    attr_accessor :identifier, :secret, :authorization_endpoint, :token_endpoint, :userinfo_endpoint,
                  :host, :redirect_uri

    def initialize(options = {})
      @identifier = options[:identifier] || options["identifier"]
      @secret = options[:secret] || options["secret"]
      @authorization_endpoint = options[:authorization_endpoint] || options["authorization_endpoint"]
      @token_endpoint = options[:token_endpoint] || options["token_endpoint"]
      @userinfo_endpoint = options[:userinfo_endpoint] || options["userinfo_endpoint"]
      @redirect_uri = options[:redirect_uri] || options["redirect_uri"]
    end

    def authorization_uri(params = {})
      uri = URI.parse(authorization_endpoint)
      query_params = {
        client_id: identifier,
        response_type: params[:response_type] || "code",
        scope: params[:scope] || "openid profile email",
        redirect_uri: params[:redirect_uri] || @redirect_uri,
        state: params[:state],
        nonce: params[:nonce]
      }.compact

      # Add PKCE parameters if provided
      query_params[:code_challenge] = params[:code_challenge] if params[:code_challenge]
      query_params[:code_challenge_method] = params[:code_challenge_method] if params[:code_challenge_method]

      # Add any additional params
      query_params.merge!(params[:extra_params]) if params[:extra_params]

      uri.query = URI.encode_www_form(query_params)
      uri.to_s
    end

    def access_token!(params = {}) # rubocop:disable Metrics/MethodLength
      body_params = {
        grant_type: "authorization_code",
        code: params[:code],
        redirect_uri: params[:redirect_uri] || @redirect_uri,
        client_id: identifier,
        client_secret: secret
      }

      # Add PKCE verifier if provided
      body_params[:code_verifier] = params[:code_verifier] if params[:code_verifier]

      OmniauthOidc::Logging.instrument("token.exchange", code: "[FILTERED]") do
        response = HttpClient.post(
          token_endpoint,
          body: URI.encode_www_form(body_params),
          headers: {
            "Content-Type" => "application/x-www-form-urlencoded",
            "Accept" => "application/json"
          }
        )

        ResponseObjects::AccessToken.new(response)
      end
    rescue HttpClient::HttpError => e
      raise OmniauthOidc::TokenError, "Token exchange failed: #{e.message}"
    end

    def userinfo!(access_token)
      OmniauthOidc::Logging.instrument("userinfo.fetch", endpoint: userinfo_endpoint) do
        response = HttpClient.get(
          userinfo_endpoint,
          headers: {
            "Authorization" => "Bearer #{access_token}",
            "Accept" => "application/json"
          }
        )

        ResponseObjects::UserInfo.new(response)
      end
    rescue HttpClient::HttpError => e
      raise OmniauthOidc::TokenError, "Failed to fetch user info: #{e.message}"
    end
  end
end
