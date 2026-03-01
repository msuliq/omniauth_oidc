# frozen_string_literal: true

module OmniauthOidc
  # Thread-safe JWKS cache with configurable TTL and force refresh capability
  class JwksCache
    DEFAULT_TTL = 3600 # 1 hour in seconds

    CacheEntry = Struct.new(:keys, :fetched_at, keyword_init: true)

    class << self
      def instance
        @instance ||= new
      end

      # Clear all cached keys (useful for testing)
      def clear!
        instance.clear!
      end

      # Force refresh a specific JWKS URI on next access
      def invalidate(jwks_uri)
        instance.invalidate(jwks_uri)
      end
    end

    def initialize(ttl: DEFAULT_TTL)
      @ttl = ttl
      @cache = {}
      @mutex = Mutex.new
    end

    # Fetch JWKS, using cache if valid
    def fetch(jwks_uri, force_refresh: false, &block)
      @mutex.synchronize do
        entry = @cache[jwks_uri]

        if !force_refresh && entry && !expired?(entry)
          Logging.debug("JWKS cache hit", jwks_uri: jwks_uri)
          return entry.keys
        end

        Logging.info("JWKS cache miss, fetching", jwks_uri: jwks_uri, force_refresh: force_refresh)
        keys = block.call
        @cache[jwks_uri] = CacheEntry.new(keys: keys, fetched_at: Time.now)
        keys
      end
    end

    # Check if a specific URI's cache is valid
    def valid?(jwks_uri)
      @mutex.synchronize do
        entry = @cache[jwks_uri]
        entry && !expired?(entry)
      end
    end

    # Invalidate a specific URI's cache
    def invalidate(jwks_uri)
      @mutex.synchronize do
        @cache.delete(jwks_uri)
        Logging.debug("JWKS cache invalidated", jwks_uri: jwks_uri)
      end
    end

    # Clear entire cache
    def clear!
      @mutex.synchronize do
        @cache.clear
        Logging.debug("JWKS cache cleared")
      end
    end

    # Get current TTL
    attr_reader :ttl

    # Update TTL (affects future expiration checks)
    def ttl=(value)
      @mutex.synchronize do
        @ttl = value
      end
    end

    private

    def expired?(entry)
      Time.now - entry.fetched_at > @ttl
    end
  end
end
