# frozen_string_literal: true

module OmniauthOidc
  # Fetches and parses OpenID Connect configuration from .well-known endpoint
  class ConfigFetcher
    # Config object with dynamic attribute access for OIDC discovery fields
    class Config
      def initialize(attributes = {})
        @attributes = attributes
      end

      def [](key)
        @attributes[key.to_sym] || @attributes[key.to_s]
      end

      def []=(key, value)
        @attributes[key.to_sym] = value
        @attributes[key.to_s] = value
      end

      def respond_to_missing?(method_name, include_private = false)
        setter = method_name.to_s.end_with?("=")
        key = setter ? method_name.to_s.chomp("=") : method_name.to_s
        setter || @attributes.key?(key.to_sym) || @attributes.key?(key) || super
      end

      private

      def method_missing(method_name, *args)
        name = method_name.to_s

        if name.end_with?("=")
          key = name.chomp("=")
          @attributes[key.to_sym] = args.first
          @attributes[key] = args.first
        elsif @attributes.key?(name.to_sym)
          @attributes[name.to_sym]
        elsif @attributes.key?(name)
          @attributes[name]
        else
          super
        end
      end
    end

    class << self
      def fetch(endpoint_url, max_retries: 3)
        retries = 0
        begin
          response = OmniauthOidc::HttpClient.get(endpoint_url)
          symbolized_config = deep_symbolize_keys(response)
          Config.new(symbolized_config)
        rescue OmniauthOidc::HttpClient::HttpError => e
          retries += 1
          retry if retries < max_retries
          raise OmniauthOidc::ConfigurationError, "Failed to fetch OIDC configuration: #{e.message}"
        rescue StandardError => e
          raise OmniauthOidc::ConfigurationError, "Failed to fetch OIDC configuration: #{e.message}"
        end
      end

      private

      # Recursively converts keys of a hash to symbols while retaining the original string keys
      def deep_symbolize_keys(hash)
        result = {}
        hash.each do |key, value|
          sym_key = key.to_sym
          result[sym_key] = value.is_a?(Hash) ? deep_symbolize_keys(value) : value
          result[key] = result[sym_key] # Add the string key as well
        end
        result
      end
    end
  end
end
