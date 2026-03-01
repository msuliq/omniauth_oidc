# frozen_string_literal: true

require "test_helper"

class TestJwkHandler < Minitest::Test
  def setup
    @rsa_key1 = OpenSSL::PKey::RSA.generate(2048)
    @rsa_key2 = OpenSSL::PKey::RSA.generate(2048)
  end

  def jwk_data_for(key, kid:)
    jwk = JWT::JWK.new(key)
    # Simulate real JWKS JSON (string keys) as returned by JSON.parse
    data = jwk.export.transform_keys(&:to_s)
    data["kid"] = kid
    data
  end

  def test_parse_jwks_with_single_key
    jwks = { "keys" => [jwk_data_for(@rsa_key1, kid: "key1")] }

    keys = OmniauthOidc::JwkHandler.parse_jwks(jwks)
    assert_equal 1, keys.size
    assert_equal "key1", keys.first.kid
    assert_instance_of OpenSSL::PKey::RSA, keys.first.keypair
  end

  def test_parse_jwks_with_multiple_keys
    jwks = {
      "keys" => [
        jwk_data_for(@rsa_key1, kid: "key1"),
        jwk_data_for(@rsa_key2, kid: "key2")
      ]
    }

    keys = OmniauthOidc::JwkHandler.parse_jwks(jwks)
    assert_equal 2, keys.size
    assert_equal "key1", keys[0].kid
    assert_equal "key2", keys[1].kid
  end

  def test_parse_jwks_from_json_string
    jwks = { "keys" => [jwk_data_for(@rsa_key1, kid: "key1")] }

    keys = OmniauthOidc::JwkHandler.parse_jwks(jwks.to_json)
    assert_equal 1, keys.size
    assert_equal "key1", keys.first.kid
  end

  def test_parse_jwks_returns_nil_for_nil
    assert_nil OmniauthOidc::JwkHandler.parse_jwks(nil)
  end

  def test_find_key_with_matching_kid
    keys = [
      OmniauthOidc::JwkHandler::KeyWithId.new(kid: "key1", keypair: @rsa_key1),
      OmniauthOidc::JwkHandler::KeyWithId.new(kid: "key2", keypair: @rsa_key2)
    ]

    result = OmniauthOidc::JwkHandler.find_key(keys, "key2")
    assert_equal @rsa_key2, result
  end

  def test_find_key_returns_first_when_no_kid
    keys = [
      OmniauthOidc::JwkHandler::KeyWithId.new(kid: "key1", keypair: @rsa_key1),
      OmniauthOidc::JwkHandler::KeyWithId.new(kid: "key2", keypair: @rsa_key2)
    ]

    result = OmniauthOidc::JwkHandler.find_key(keys, nil)
    assert_equal @rsa_key1, result
  end

  def test_find_key_returns_first_when_single_key
    keys = [
      OmniauthOidc::JwkHandler::KeyWithId.new(kid: "key1", keypair: @rsa_key1)
    ]

    result = OmniauthOidc::JwkHandler.find_key(keys, "nonexistent")
    assert_equal @rsa_key1, result
  end

  def test_find_key_falls_back_to_first_when_kid_not_found
    keys = [
      OmniauthOidc::JwkHandler::KeyWithId.new(kid: "key1", keypair: @rsa_key1),
      OmniauthOidc::JwkHandler::KeyWithId.new(kid: "key2", keypair: @rsa_key2)
    ]

    result = OmniauthOidc::JwkHandler.find_key(keys, "nonexistent")
    assert_equal @rsa_key1, result
  end
end
