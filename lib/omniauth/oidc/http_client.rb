# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module OmniauthOidc
  # Simple HTTP client using Net::HTTP
  class HttpClient
    class HttpError < StandardError; end

    MAX_REDIRECTS = 5

    def self.get(url, headers: {})
      uri = URI.parse(url)
      request = Net::HTTP::Get.new(uri)
      headers.each { |key, value| request[key] = value }

      response = execute_request(uri, request)
      handle_response(response, url, headers: headers, redirects_remaining: MAX_REDIRECTS)
    end

    def self.post(url, body: nil, headers: {})
      uri = URI.parse(url)
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/x-www-form-urlencoded" unless headers["Content-Type"]
      headers.each { |key, value| request[key] = value }
      request.body = body if body

      response = execute_request(uri, request)
      handle_response(response, url)
    end

    def self.execute_request(uri, request)
      OmniauthOidc::Logging.instrument("http.request", method: request.method, uri: uri.to_s) do
        Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
          http.request(request)
        end
      end
    end
    private_class_method :execute_request

    def self.handle_response(response, url, headers: {}, redirects_remaining: 0)
      case response
      when Net::HTTPSuccess
        parse_json_response(response.body)
      when Net::HTTPRedirection
        raise HttpError, "Too many redirects for #{url}" if redirects_remaining <= 0

        location = response["location"]
        raise HttpError, "HTTP redirect from #{url} with no location header" unless location

        redirect_uri = URI.parse(location)
        # Resolve relative redirects
        redirect_uri = URI.join(url, location) unless redirect_uri.host

        OmniauthOidc::Logging.debug("Following redirect", from: url, to: redirect_uri.to_s)
        follow_redirect(redirect_uri, headers: headers, redirects_remaining: redirects_remaining - 1)
      else
        raise HttpError, "HTTP request failed: #{response.code} #{response.message} for #{url}"
      end
    end
    private_class_method :handle_response

    def self.follow_redirect(uri, headers: {}, redirects_remaining: 0)
      request = Net::HTTP::Get.new(uri)
      headers.each { |key, value| request[key] = value }

      response = execute_request(uri, request)
      handle_response(response, uri.to_s, headers: headers, redirects_remaining: redirects_remaining)
    end
    private_class_method :follow_redirect

    def self.parse_json_response(body)
      JSON.parse(body)
    rescue JSON::ParserError => e
      raise HttpError, "Failed to parse JSON response: #{e.message}"
    end
    private_class_method :parse_json_response
  end
end
