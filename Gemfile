# frozen_string_literal: true

source "https://rubygems.org"

if Gem::Version.new(RUBY_VERSION.dup) >= Gem::Version.new("3.1")
  gem "net-imap", require: false
  gem "net-pop", require: false
  gem "net-smtp", require: false
end

gemspec

group :development, :test do
  gem "bundle-audit"
  gem "minitest"
  gem "rake"
  gem "rubocop"
  gem "webmock"
end
