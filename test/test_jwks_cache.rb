# frozen_string_literal: true

require "test_helper"

class TestJwksCache < Minitest::Test
  def setup
    @cache = OmniauthOidc::JwksCache.new(ttl: 3600)
    @jwks_uri = "https://example.com/oauth/jwks"
    @test_keys = { "keys" => [{ "kid" => "test_key", "kty" => "RSA" }] }
  end

  def teardown
    OmniauthOidc::JwksCache.clear!
  end

  def test_singleton_instance
    instance1 = OmniauthOidc::JwksCache.instance
    instance2 = OmniauthOidc::JwksCache.instance
    assert_same instance1, instance2
  end

  def test_fetch_calls_block_on_cache_miss
    block_called = false
    result = @cache.fetch(@jwks_uri) do
      block_called = true
      @test_keys
    end

    assert block_called
    assert_equal @test_keys, result
  end

  def test_fetch_uses_cache_on_hit
    # First call
    @cache.fetch(@jwks_uri) { @test_keys }

    # Second call - block should not be executed
    block_called = false
    result = @cache.fetch(@jwks_uri) do
      block_called = true
      { different: "data" }
    end

    refute block_called
    assert_equal @test_keys, result
  end

  def test_fetch_with_force_refresh
    @cache.fetch(@jwks_uri) { @test_keys }

    # Force refresh should call block again
    new_keys = { "keys" => [{ "kid" => "new_key" }] }
    result = @cache.fetch(@jwks_uri, force_refresh: true) { new_keys }

    assert_equal new_keys, result
  end

  def test_cache_expiration
    short_ttl_cache = OmniauthOidc::JwksCache.new(ttl: 0.1) # 100ms

    # First fetch
    short_ttl_cache.fetch(@jwks_uri) { @test_keys }

    # Wait for expiration
    sleep(0.2)

    # Should call block again after expiration
    block_called = false
    new_keys = { "keys" => [{ "kid" => "expired_key" }] }
    result = short_ttl_cache.fetch(@jwks_uri) do
      block_called = true
      new_keys
    end

    assert block_called
    assert_equal new_keys, result
  end

  def test_valid_check
    refute @cache.valid?(@jwks_uri)

    @cache.fetch(@jwks_uri) { @test_keys }
    assert @cache.valid?(@jwks_uri)
  end

  def test_invalidate
    @cache.fetch(@jwks_uri) { @test_keys }
    assert @cache.valid?(@jwks_uri)

    @cache.invalidate(@jwks_uri)
    refute @cache.valid?(@jwks_uri)
  end

  def test_clear_removes_all_entries
    @cache.fetch(@jwks_uri) { @test_keys }
    @cache.fetch("https://other.com/jwks") { { "other" => "keys" } }

    @cache.clear!

    refute @cache.valid?(@jwks_uri)
    refute @cache.valid?("https://other.com/jwks")
  end

  def test_ttl_accessor
    assert_equal 3600, @cache.ttl

    @cache.ttl = 7200
    assert_equal 7200, @cache.ttl
  end

  def test_thread_safety
    threads = 10.times.map do
      Thread.new do
        100.times do
          @cache.fetch(@jwks_uri) { @test_keys }
        end
      end
    end

    threads.each(&:join)

    # Should not raise any errors and cache should be valid
    assert @cache.valid?(@jwks_uri)
  end

  def test_class_level_clear
    OmniauthOidc::JwksCache.instance.fetch(@jwks_uri) { @test_keys }
    assert OmniauthOidc::JwksCache.instance.valid?(@jwks_uri)

    OmniauthOidc::JwksCache.clear!
    refute OmniauthOidc::JwksCache.instance.valid?(@jwks_uri)
  end

  def test_class_level_invalidate
    OmniauthOidc::JwksCache.instance.fetch(@jwks_uri) { @test_keys }
    assert OmniauthOidc::JwksCache.instance.valid?(@jwks_uri)

    OmniauthOidc::JwksCache.invalidate(@jwks_uri)
    refute OmniauthOidc::JwksCache.instance.valid?(@jwks_uri)
  end
end
