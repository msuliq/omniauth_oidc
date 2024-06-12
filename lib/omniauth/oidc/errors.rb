# frozen_string_literal: true

module OmniauthOidc
  class Error < RuntimeError; end

  class MissingCodeError < Error; end

  class MissingIdTokenError < Error; end
end
