# frozen_string_literal: true

module OmniauthOidc
  # Thread-safe cache with a per-entry TTL.
  #
  # Reads take a short global lock only. Fetches run under a per-key lock, so a
  # slow or hanging upstream for one key never blocks cache hits for other keys,
  # and concurrent misses for the same key trigger a single fetch.
  class TtlCache
    Entry = Struct.new(:value, :fetched_at, keyword_init: true)

    attr_reader :ttl

    def initialize(ttl:, name: "TTL")
      @ttl = ttl
      @name = name
      @entries = {}
      @locks = {}
      @mutex = Mutex.new
    end

    # Returns the cached value for key, calling the block to fetch it on a miss.
    #
    # ttl:           seconds an entry stays valid (defaults to the cache TTL)
    # force_refresh: fetch even if the entry is still valid
    # min_age:       with force_refresh, reuse an entry fetched less than this many
    #                seconds ago. Rate limits refreshes that callers can trigger.
    def fetch(key, force_refresh: false, ttl: nil, min_age: 0, &block)
      ttl ||= @ttl
      entry = read(key)
      return hit(key, entry) if !force_refresh && younger_than?(entry, ttl)

      lock_for(key).synchronize do
        # Another thread may have fetched while this one waited for the lock
        entry = read(key)
        return hit(key, entry) if younger_than?(entry, force_refresh ? min_age : ttl)

        Logging.info("#{@name} cache miss, fetching", key: key, force_refresh: force_refresh)
        value = block.call
        @mutex.synchronize { @entries[key] = Entry.new(value: value, fetched_at: Time.now) }
        value
      end
    end

    def valid?(key)
      younger_than?(read(key), @ttl)
    end

    def invalidate(key)
      @mutex.synchronize { @entries.delete(key) }
      Logging.debug("#{@name} cache invalidated", key: key)
    end

    def clear!
      @mutex.synchronize { @entries.clear }
      Logging.debug("#{@name} cache cleared")
    end

    def ttl=(value)
      @mutex.synchronize { @ttl = value }
    end

    private

    def read(key)
      @mutex.synchronize { @entries[key] }
    end

    def hit(key, entry)
      Logging.debug("#{@name} cache hit", key: key)
      entry.value
    end

    def younger_than?(entry, seconds)
      !entry.nil? && Time.now - entry.fetched_at < seconds
    end

    def lock_for(key)
      @mutex.synchronize { @locks[key] ||= Mutex.new }
    end
  end
end
