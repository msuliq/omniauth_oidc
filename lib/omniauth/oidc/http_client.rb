# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module OmniauthOidc
  # Simple HTTP client using Net::HTTP
  class HttpClient
    class HttpError < StandardError; end

    MAX_REDIRECTS = 5

    # Explicit timeouts in seconds. Net::HTTP defaults to 60s each, which would let a
    # hanging provider tie up the calling thread for minutes.
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 10
    WRITE_TIMEOUT = 10

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
        Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https", open_timeout: OPEN_TIMEOUT,
                                                read_timeout: READ_TIMEOUT, write_timeout: WRITE_TIMEOUT) do |http|
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
        follow_redirect(redirect_uri, headers: redirect_headers(URI.parse(url), redirect_uri, headers),
                                      redirects_remaining: redirects_remaining - 1)
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

    # Refuses HTTPS to HTTP downgrades, and drops credentials when a redirect leaves the
    # original origin, so a bearer token is never sent in cleartext or to another host.
    def self.redirect_headers(from, to, headers)
      if from.scheme == "https" && to.scheme != "https"
        raise HttpError, "Refusing to follow redirect from #{from} to non-HTTPS #{to}"
      end

      same_origin = [from.scheme, from.host, from.port] == [to.scheme, to.host, to.port]
      return headers if same_origin

      headers.reject { |key, _| key.to_s.casecmp?("Authorization") }
    end
    private_class_method :redirect_headers

    def self.parse_json_response(body)
      JSON.parse(body)
    rescue JSON::ParserError => e
      raise HttpError, "Failed to parse JSON response: #{e.message}"
    end
    private_class_method :parse_json_response
  end
end
