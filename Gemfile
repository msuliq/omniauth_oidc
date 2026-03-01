# frozen_string_literal: true

source "https://rubygems.org"

if Gem::Version.new(RUBY_VERSION.dup) >= Gem::Version.new("3.1")
  gem "net-imap", require: false
  gem "net-pop", require: false
  gem "net-smtp", require: false
end

gemspec

# Ruby 4.0+ compatibility
gem "ostruct" if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("4.0.0")

group :development, :test do
  gem "bundle-audit"
  gem "minitest"
  gem "rack-test"
  gem "rake"
  gem "rubocop"
  gem "webmock"
end
