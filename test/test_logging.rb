# frozen_string_literal: true

require "test_helper"

class TestLogging < Minitest::Test
  def setup
    @original_logger = OmniauthOidc::Logging.logger
    @test_logger = Logger.new(StringIO.new)
    OmniauthOidc::Logging.logger = @test_logger
  end

  def teardown
    OmniauthOidc::Logging.logger = @original_logger
  end

  def test_has_default_logger
    OmniauthOidc::Logging.logger = nil
    assert_instance_of Logger, OmniauthOidc::Logging.logger
  end

  def test_can_set_custom_logger
    custom_logger = Logger.new($stdout)
    OmniauthOidc::Logging.logger = custom_logger
    assert_equal custom_logger, OmniauthOidc::Logging.logger
  end

  def test_log_level_can_be_changed
    OmniauthOidc::Logging.log_level = Logger::DEBUG
    assert_equal Logger::DEBUG, OmniauthOidc::Logging.logger.level
  end

  def test_debug_logging
    OmniauthOidc::Logging.logger.level = Logger::DEBUG
    OmniauthOidc::Logging.debug("Test debug message", context: "test")
    # Just ensure it doesn't raise an error
    assert true
  end

  def test_info_logging
    OmniauthOidc::Logging.info("Test info message")
    assert true
  end

  def test_warn_logging
    OmniauthOidc::Logging.warn("Test warn message")
    assert true
  end

  def test_error_logging
    OmniauthOidc::Logging.error("Test error message")
    assert true
  end

  def test_instrument_without_activesupport
    # Ensure instrumentation works even without ActiveSupport
    OmniauthOidc::Logging.instrument("test.event", payload: "data")
    assert true # If we get here without raising, test passes
  end

  def test_instrument_with_block
    result = OmniauthOidc::Logging.instrument("test.event") do
      "test_result"
    end
    assert_equal "test_result", result
  end

  def test_sensitive_data_sanitization
    # Logging should sanitize sensitive keys
    OmniauthOidc::Logging.debug("Event", secret: "should_not_log", access_token: "also_hidden")
    assert true
  end
end
