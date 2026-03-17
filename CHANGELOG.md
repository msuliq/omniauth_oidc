## [Released]

## [1.0.0] - 2026-03-02

### BREAKING CHANGES
- **Dependency Replacement**: Removed `openid_connect`, `openid_config_parser`, `json-jwt`, and `httparty` runtime dependencies. Replaced with custom `Net::HTTP`-based implementation and the standard `jwt` gem. Any code that relied on these gems being transitively available will need to add them directly.
- **Internal Object Types Changed**: Response objects are now custom classes instead of OpenIDConnect library types:
  - `OpenIDConnect::Client` replaced by `OmniauthOidc::Client`
  - `OpenIDConnect::ResponseObject::IdToken` replaced by `OmniauthOidc::ResponseObjects::IdToken`
  - `OpenIDConnect::ResponseObject::UserInfo` replaced by `OmniauthOidc::ResponseObjects::UserInfo`
  - `Rack::OAuth2::AccessToken` replaced by `OmniauthOidc::ResponseObjects::AccessToken`
- **Session Keys Namespaced**: Session keys now include the provider name (e.g. `omniauth.my_provider.state` instead of `omniauth.state`). This enables multiple OIDC providers but breaks code that manually accesses session keys with the old format. Users mid-authentication during upgrade will see state mismatch errors.
- **Scope Return Type**: `scope` now returns a space-delimited String (e.g. `"openid profile email"`) instead of an Array. Code that called `.each`, `.include?`, or other Array methods on the return value will break.
- **AuthHash Construction**: Now uses OmniAuth DSL blocks (`info`, `credentials`, `extra`) consistently instead of manually building `env["omniauth.auth"]`. The `info` hash now includes all standard OIDC UserInfo fields (given_name, family_name, gender, picture, phone, website).
- **Error Classes Restructured**: Error handling uses new specific error classes under `OmniauthOidc::` namespace. `Rack::OAuth2::Client::Error` is no longer caught. `validate_client_algorithm!` now raises `OmniauthOidc::InvalidAlgorithmError` instead of `CallbackError`.
- **CallbackError Parameter Names**: `CallbackError` now accepts `error_reason:` and `error_uri:` keyword arguments (previously `reason:` and `uri:`). The old keys are still accepted for backward compatibility.

### Added
- **Custom HTTP Client** (`OmniauthOidc::HttpClient`): Net::HTTP-based client for all HTTP requests, removing external HTTP client dependencies entirely
  - GET requests follow up to 5 redirects (301, 302, 307, 308), including relative redirects
  - POST requests reject redirects to prevent credential leakage
- **Custom OIDC Client** (`OmniauthOidc::Client`): Handles authorization URI construction, token exchange, and userinfo fetching
- **Response Objects** (`OmniauthOidc::ResponseObjects`): `IdToken`, `UserInfo`, and `AccessToken` classes with method-style access to standard OIDC claims
- **Configuration Fetcher** (`OmniauthOidc::ConfigFetcher`): Fetches and parses `.well-known/openid-configuration` with retry support
- **JWK Handler** (`OmniauthOidc::JwkHandler`): JWKS parsing with proper `kid`-based key selection for providers that publish multiple signing keys (e.g. Google, Microsoft Entra ID, Auth0)
- **JWKS Caching** (`OmniauthOidc::JwksCache`): Thread-safe JWKS cache with configurable TTL (default 1 hour)
  - Automatic cache invalidation and retry on signature verification failure
  - Manual cache control via `OmniauthOidc::JwksCache.clear!` and `.invalidate(uri)`
  - Configurable via `jwks_cache_ttl` option
- **Logging & Instrumentation** (`OmniauthOidc::Logging`): Logging via Ruby Logger with optional ActiveSupport::Notifications integration
  - Configurable log levels (default: WARN)
  - Automatic sanitization of sensitive data (tokens, secrets, code verifiers)
  - Event instrumentation for config fetch, token exchange, userinfo fetch, JWKS fetch, request phase, and callback phase
- **Error Hierarchy**: Specific error classes for all failure modes
  - `TokenVerificationError`, `TokenExpiredError`, `InvalidAlgorithmError`, `InvalidSignatureError`
  - `InvalidIssuerError`, `InvalidAudienceError`, `InvalidNonceError`
  - `JwksFetchError`, `KeyNotFoundError`
  - `ConfigurationError`, `MissingConfigurationError`
- **Configuration Validation**: Required options (`identifier`, `secret`, `config_endpoint`) are validated on first request with a clear error message listing all missing fields
- **RBS Type Signatures** (`sig/omniauth_oidc.rbs`): Full type declarations for all public API classes
- **Comprehensive Test Suite**: Unit tests for HTTP client, JWK handler, JWKS cache, logging, errors, and strategy configuration

### Fixed
- **JWK kid Selection**: `keyset_for_algorithm` now selects the correct signing key by `kid` from JWKS. Previously, with multiple keys in the JWKS, verification could fail or use the wrong key.
- **Dead Code Removed**: Removed `decode` method in Verify module that referenced undefined `UrlSafeBase64` constant
- **Typo**: Fixed `client_singing_alg` to `client_signing_alg` in error messages
- **Scope Default**: Fixed default scope fallback from `[:open_id]` (typo) to `[:openid]`
- **AuthHash Consistency**: Consolidated duplicate user info fetching and AuthHash construction into OmniAuth DSL blocks
- **Removed `resolve_endpoint_from_host`**: Endpoints are now used as full URLs from the discovery document instead of being stripped to relative paths

### Changed
- **Module Loading**: Replaced `Dir.glob` with explicit `require_relative` for clarity and predictable load order
- **Dependency Constraints**: Runtime dependencies reduced to `omniauth ~> 2.1` and `jwt ~> 2.7`
- **CI Updates**: Added Ruby 4.0.1 to test matrix, updated `actions/checkout` to v6, RuboCop runs on Ruby 3.3
- **RuboCop Config**: Fixed invalid cop name `Metrics/Metrics/CyclomaticComplexity`, added `NewCops: enable`

### Migration Guide from 0.x to 1.0.0

1. **Dependencies**: Remove gems that were only used by this gem, then run `bundle install`:
   - `httparty`
   - `openid_connect`
   - `openid_config_parser`
   - `json-jwt`
2. **Session Keys**: If you manually access session keys, update to the new namespaced format: `omniauth.{provider_name}.state`, `omniauth.{provider_name}.nonce`.
3. **Scope Handling**: If your code treats `scope` as an Array, update it. `scope` now returns a space-delimited String.
4. **Error Handling**: Update rescue clauses to catch the new error classes if needed. For example:
   - `Rack::OAuth2::Client::Error` -> `OmniauthOidc::TokenError`
   - Algorithm mismatches now raise `OmniauthOidc::InvalidAlgorithmError` instead of `CallbackError`
5. **Response Objects**: If you access `access_token` or `user_info` objects directly, note they are now `OmniauthOidc::ResponseObjects::AccessToken` and `OmniauthOidc::ResponseObjects::UserInfo` respectively.
6. **Logging** (optional): Configure logging level: `OmniauthOidc::Logging.log_level = Logger::INFO`
7. **Ruby 4.0+**: Add `gem "ostruct"` to your Gemfile (removed from default gems in Ruby 4.0).

## [0.2.7] - 2024-10-11
- Dependencies update

## [0.2.6] - 2024-10-16
- Fix for callback_phase initializing twice

## [0.2.5] - 2024-10-16
- Fix for uninitialized constant Oidc in strategy.rb:163

## [0.2.4] - 2024-09-28
- Fix bug with configurable scopes

## [0.2.3] - 2024-08-04
- Update readme

## [0.2.2] - 2024-08-04
- Update dependencies, update documentation, fix end_session_uri, update other_phase

## [0.2.1] - 2024-07-21
- Update dependencies

## [0.2.0] - 2024-07-06
- Add option to fetch user info or skip it

## [0.1.1] - 2024-06-16
- Add dependabot

## [0.1.0] - 2024-06-13
- Initial release
