# frozen_string_literal: true

require "logger"

module OmniauthOidc
  # Logging module providing both Ruby Logger and ActiveSupport::Notifications support
  module Logging
    class << self
      attr_writer :logger

      def logger
        @logger ||= default_logger
      end

      def log_level=(level)
        logger.level = level
      end

      def instrument(event_name, payload = {}, &block)
        full_event_name = "#{event_name}.omniauth_oidc"

        # Always log the event
        log_event(event_name, payload)

        # Use ActiveSupport::Notifications if available
        if defined?(ActiveSupport::Notifications)
          ActiveSupport::Notifications.instrument(full_event_name, payload, &block)
        elsif block
          yield payload
        end
      end

      def debug(message, context = {})
        log(:debug, message, context)
      end

      def info(message, context = {})
        log(:info, message, context)
      end

      def warn(message, context = {})
        log(:warn, message, context)
      end

      def error(message, context = {})
        log(:error, message, context)
      end

      private

      def default_logger
        Logger.new($stdout).tap do |log|
          log.progname = "OmniauthOidc"
          log.level = Logger::WARN # Default to WARN to avoid noise
        end
      end

      def log(level, message, context)
        formatted_message = context.empty? ? message : "#{message} #{context.inspect}"
        logger.send(level, formatted_message)
      end

      def log_event(event_name, payload)
        # Log at debug level for instrumentation events
        sanitized_payload = sanitize_payload(payload)
        debug("Event: #{event_name}", sanitized_payload)
      end

      def sanitize_payload(payload)
        # Remove sensitive data from logs
        sensitive_keys = %i[secret client_secret access_token id_token refresh_token code_verifier]
        payload.reject { |k, _| sensitive_keys.include?(k.to_sym) }
      end
    end
  end
end
