# frozen_string_literal: true

module OmniauthOidc
  # Fetches and parses OpenID Connect configuration from .well-known endpoint
  class ConfigFetcher
    DEFAULT_CACHE_TTL = 3600 # 1 hour in seconds

    # Discovery fields the gem reads. Missing ones return nil instead of raising NoMethodError.
    STANDARD_FIELDS = %i[
      issuer authorization_endpoint token_endpoint userinfo_endpoint jwks_uri
      end_session_endpoint scopes_supported id_token_signing_alg_values_supported
    ].freeze

    # Fields without which the gem cannot verify tokens or start a login
    REQUIRED_FIELDS = %i[issuer authorization_endpoint].freeze

    CACHE = TtlCache.new(ttl: DEFAULT_CACHE_TTL, name: "Discovery")
    private_constant :CACHE

    # Config object with dynamic attribute access for OIDC discovery fields
    class Config
      def initialize(attributes = {})
        @attributes = attributes
      end

      STANDARD_FIELDS.each do |field|
        define_method(field) { self[field] }
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
          config = Config.new(deep_symbolize_keys(response))
        rescue OmniauthOidc::HttpClient::HttpError => e
          retries += 1
          retry if retries < max_retries
          raise OmniauthOidc::ConfigurationError, "Failed to fetch OIDC configuration: #{e.message}"
        rescue StandardError => e
          raise OmniauthOidc::ConfigurationError, "Failed to fetch OIDC configuration: #{e.message}"
        end

        validate!(config, endpoint_url)
        config
      end

      # Fetches the discovery document, reusing it across requests for ttl seconds.
      # Failed fetches are not cached. A ttl of 0 disables caching.
      def fetch_cached(endpoint_url, ttl: DEFAULT_CACHE_TTL)
        CACHE.fetch(endpoint_url, ttl: ttl) { fetch(endpoint_url) }
      end

      def clear_cache!
        CACHE.clear!
      end

      private

      def validate!(config, endpoint_url)
        missing = REQUIRED_FIELDS.reject { |field| config[field].is_a?(String) && !config[field].empty? }
        return if missing.empty?

        raise OmniauthOidc::ConfigurationError,
              "OIDC configuration from #{endpoint_url} is missing required fields: #{missing.join(", ")}"
      end

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
