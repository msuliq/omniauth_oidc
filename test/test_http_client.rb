# frozen_string_literal: true

require "test_helper"

class TestHttpClient < Minitest::Test
  def setup
    WebMock.reset!
  end

  def test_get_success
    stub_request(:get, "https://example.com/data")
      .to_return(status: 200, body: '{"key":"value"}', headers: { "Content-Type" => "application/json" })

    result = OmniauthOidc::HttpClient.get("https://example.com/data")
    assert_equal({ "key" => "value" }, result)
  end

  def test_post_success
    stub_request(:post, "https://example.com/token")
      .to_return(status: 200, body: '{"access_token":"abc"}', headers: { "Content-Type" => "application/json" })

    result = OmniauthOidc::HttpClient.post("https://example.com/token", body: "grant_type=authorization_code")
    assert_equal({ "access_token" => "abc" }, result)
  end

  def test_get_follows_redirects
    stub_request(:get, "https://example.com/old")
      .to_return(status: 302, headers: { "Location" => "https://example.com/new" })
    stub_request(:get, "https://example.com/new")
      .to_return(status: 200, body: '{"redirected":true}', headers: { "Content-Type" => "application/json" })

    result = OmniauthOidc::HttpClient.get("https://example.com/old")
    assert_equal({ "redirected" => true }, result)
  end

  def test_get_follows_multiple_redirects
    stub_request(:get, "https://example.com/a")
      .to_return(status: 301, headers: { "Location" => "https://example.com/b" })
    stub_request(:get, "https://example.com/b")
      .to_return(status: 302, headers: { "Location" => "https://example.com/c" })
    stub_request(:get, "https://example.com/c")
      .to_return(status: 200, body: '{"found":true}', headers: { "Content-Type" => "application/json" })

    result = OmniauthOidc::HttpClient.get("https://example.com/a")
    assert_equal({ "found" => true }, result)
  end

  def test_get_raises_on_too_many_redirects
    (1..6).each do |i|
      stub_request(:get, "https://example.com/r#{i}")
        .to_return(status: 302, headers: { "Location" => "https://example.com/r#{i + 1}" })
    end

    error = assert_raises(OmniauthOidc::HttpClient::HttpError) do
      OmniauthOidc::HttpClient.get("https://example.com/r1")
    end
    assert_match(/Too many redirects/, error.message)
  end

  def test_post_does_not_follow_redirects
    stub_request(:post, "https://example.com/token")
      .to_return(status: 302, headers: { "Location" => "https://example.com/other" })

    error = assert_raises(OmniauthOidc::HttpClient::HttpError) do
      OmniauthOidc::HttpClient.post("https://example.com/token", body: "data")
    end
    assert_match(/Too many redirects/, error.message)
  end

  def test_get_follows_relative_redirect
    stub_request(:get, "https://example.com/old")
      .to_return(status: 302, headers: { "Location" => "/new" })
    stub_request(:get, "https://example.com/new")
      .to_return(status: 200, body: '{"relative":true}', headers: { "Content-Type" => "application/json" })

    result = OmniauthOidc::HttpClient.get("https://example.com/old")
    assert_equal({ "relative" => true }, result)
  end

  def test_get_raises_on_http_error
    stub_request(:get, "https://example.com/fail")
      .to_return(status: 500, body: "Internal Server Error")

    error = assert_raises(OmniauthOidc::HttpClient::HttpError) do
      OmniauthOidc::HttpClient.get("https://example.com/fail")
    end
    assert_match(/500/, error.message)
  end

  def test_get_raises_on_invalid_json
    stub_request(:get, "https://example.com/bad")
      .to_return(status: 200, body: "not json", headers: { "Content-Type" => "application/json" })

    error = assert_raises(OmniauthOidc::HttpClient::HttpError) do
      OmniauthOidc::HttpClient.get("https://example.com/bad")
    end
    assert_match(/Failed to parse JSON/, error.message)
  end
end
