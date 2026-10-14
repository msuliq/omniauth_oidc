# frozen_string_literal: true

module OmniauthOidc
  # Process-wide JWKS cache with configurable TTL and force refresh capability
  class JwksCache < TtlCache
    DEFAULT_TTL = 3600 # 1 hour in seconds
    INSTANCE_MUTEX = Mutex.new
    private_constant :INSTANCE_MUTEX

    class << self
      def instance
        @instance || INSTANCE_MUTEX.synchronize { @instance ||= new }
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
      super(ttl: ttl, name: "JWKS")
    end
  end
end
