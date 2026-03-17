# OmniAuth::Oidc

OmniAuth strategy for OpenID Connect (OIDC) authentication. Supports multiple OIDC providers, PKCE, JWKS key rotation, and both `code` and `id_token` response types.

Minimal dependencies: only `omniauth` and `jwt` gems required. All HTTP requests use Ruby's built-in `Net::HTTP` — no Faraday, HTTParty, or other external HTTP clients.

Developed with reference to [omniauth-openid-connect](https://github.com/jjbohn/omniauth-openid-connect) and [omniauth_openid_connect](https://github.dev/omniauth/omniauth_openid_connect).

[Article on Medium](https://msuliq.medium.com/authenticating-with-omniauth-and-openid-connect-oidc-in-ruby-on-rails-applications-e136ec5b48c0) about the development of this gem.

## Installation

To install the gem run the following command in the terminal:

    $ bundle add omniauth_oidc

If bundler is not being used to manage dependencies, install the gem by executing:

    $ gem install omniauth_oidc

**Ruby 4.0+**: Add `gem "ostruct"` to your Gemfile (`ostruct` was removed from default gems in Ruby 4.0).

## Usage

To use the OmniAuth OIDC strategy, you need to configure your Rails application and set up the necessary environment variables for OIDC client credentials.

### Configuration

You must provide Client ID, Client Secret, and the URL for the OIDC configuration endpoint as a minimum for `omniauth_oidc` to work. Create an initializer file at `config/initializers/omniauth.rb`:

```ruby
# config/initializers/omniauth.rb
Rails.application.config.middleware.use OmniAuth::Builder do
  provider :oidc, {
    name: :simple_provider, # used for dynamic routing
    client_options: {
      identifier: '23575f4602bebbd9a17dbc38d85bd1a77',
      secret: ENV['SIMPLE_PROVIDER_CLIENT_SECRET'],
      config_endpoint: 'https://simpleprovider.com/cdn-cgi/access/sso/oidc/23575f4602bebbd9a17dbc38d85bd1a77/.well-known/openid-configuration'
    }
  }
end
```

With Devise:

```ruby
Devise.setup do |config|
  config.omniauth :oidc, {
    name: :simple_provider,
    scope: %w[openid email profile address],
    response_type: :code,
    uid_field: "preferred_username",
    client_options: {
      identifier: '23575f4602bebbd9a17dbc38d85bd1a77',
      secret: ENV['SIMPLE_PROVIDER_CLIENT_SECRET'],
      config_endpoint: 'https://simpleprovider.com/cdn-cgi/access/sso/oidc/23575f4602bebbd9a17dbc38d85bd1a77/.well-known/openid-configuration'
    }
  }
end
```

The gem also supports a wide range of optional parameters for a higher degree of configurability:

```ruby
# config/initializers/omniauth.rb
Rails.application.config.middleware.use OmniAuth::Builder do
  provider :oidc, {
    name: :complex_provider, # used for dynamic routing
    issuer: 'https://complexprovider.com/cdn-cgi/access/sso/oidc/23575f4602bebbd9a17dbc38d85bd1a77',
    scope: %w[openid],
    response_type: 'id_token',
    require_state: true,
    response_mode: :query,
    prompt: :login,
    send_nonce: false,
    uid_field: "sub",
    pkce: false,
    jwks_cache_ttl: 3600, # JWKS cache TTL in seconds (default: 3600)
    client_options: {
      identifier: '23575f4602bebbd9a17dbc38d85bd1a77',
      secret: ENV['COMPLEX_PROVIDER_CLIENT_SECRET'],
      config_endpoint: 'https://complexprovider.com/cdn-cgi/access/sso/oidc/23575f4602bebbd9a17dbc38d85bd1a77/.well-known/openid-configuration',
      host: 'complexprovider.com',
      scheme: "https",
      port: 443,
      authorization_endpoint: 'https://complexprovider.com/cdn-cgi/access/sso/oidc/23575f4602bebbd9a17dbc38d85bd1a77/authorization',
      token_endpoint: 'https://complexprovider.com/cdn-cgi/access/sso/oidc/23575f4602bebbd9a17dbc38d85bd1a77/token',
      userinfo_endpoint: 'https://complexprovider.com/cdn-cgi/access/sso/oidc/23575f4602bebbd9a17dbc38d85bd1a77/userinfo',
      jwks_uri: 'https://complexprovider.com/cdn-cgi/access/sso/oidc/23575f4602bebbd9a17dbc38d85bd1a77/jwks',
      end_session_endpoint: 'https://complexprovider.com/signout'
    }
  }
end
```

Ensure to replace identifier, secret, configuration endpoint URL and others with credentials received from your OIDC provider.
Please note that the gem does not accept `redirect_uri` as a configurable option. For details please see section Routes.

### Redirecting for Authentication

Buttons and links to initialize the authentication request can be placed on relevant pages as below:

```ruby
<%= button_to "Login with Simple Provider", "/auth/simple_provider" %>
```

### Handling Callbacks

The gem uses dynamic routes to handle different phases, and while you can use same routes in your Rails application, for
better experience you should have a controller to process the authenticated user. Create a CallbacksController:

```ruby
# app/controllers/callbacks_controller.rb
class CallbacksController < ApplicationController
  def omniauth
    # user info received from OIDC provider will be available in `request.env['omniauth.auth']`
    auth = request.env['omniauth.auth']

    user = User.find_or_create_by(uid: auth['uid']) do |u|
      u.name = auth['info']['name']
      u.email = auth['info']['email']
    end

    session[:user_id] = user.id
    redirect_to root_path, notice: 'Successfully logged in!'
  end
end
```

The `omniauth.auth` hash includes:

```ruby
{
  provider: :simple_provider,
  uid: "user123",
  info: {
    name: "Test User",
    email: "test@example.com",
    email_verified: true,
    nickname: "testuser",         # preferred_username
    first_name: "Test",           # given_name
    last_name: "User",            # family_name
    gender: "male",
    image: "https://example.com/avatar.jpg",  # picture
    phone: "+1234567890",         # phone_number
    urls: { website: "https://testuser.com" }
  },
  credentials: {
    id_token: "eyJ...",
    token: "access_token_value",
    refresh_token: "refresh_token_value",
    expires_in: 3600,
    scope: "openid profile email"
  },
  extra: {
    raw_info: { ... }  # full userinfo response attributes
  }
}
```

### Routes

The gem uses dynamic routes when making requests to the OIDC provider endpoints, so called `redirect_uri` which is a
non-configurable value that follows the naming pattern of `https://your_app.com/auth/<simple_provider>/callback`,
where `<simple_provider>` is the provider name defined within the configuration of the `omniauth.rb` initializer.
This represents the `redirect_uri` that will be passed with the authorization request to your OIDC provider and that
has to be registered with your OIDC provider as permitted `redirect_uri`.

Dynamic routes are used to process responses and perform intermediary steps by the middleware, e.g. request phase,
token verification. While you can define and use same routes within your Rails app, it is highly recommended to modify
your `routes.rb` to perform a dynamic redirect to another controller method so this does not cause any conflicts with
the middleware or the authorization flow.

In an example below, `auth/:provider/callback` is generalized `redirect_uri` value that is passed in the authorization
flow, while all OIDC provider responses are ultimately redirected to the `omniauth` method of the `callbacks_controller`,
which could be a "Swiss army knife" method to handle authentication or user data from various omniauth providers:

```ruby
# config/routes.rb
Rails.application.routes.draw do
  match 'auth/:provider/callback', via: :get, to: "callbacks#omniauth"
end
```

Alternatively, you can specify separate redirects for some of your OIDC providers, in case you need to handle responses
differently:

```ruby
# config/routes.rb
Rails.application.routes.draw do
  match 'auth/simple_provider/callback', via: :get, to: "callbacks#simple_provider"
  match 'auth/complex_provider/callback', via: :get, to: "callbacks#complex_provider"

  # you can add the line below if you would like the rest of the providers to be redirected to a universal `omniauth` method
  match 'auth/:provider/callback', via: :get, to: "callbacks#omniauth"
end
```

**Please note that you should register `https://your_app.com/auth/<simple_provider>/callback` with your OIDC provider
as a callback redirect URL.**

### Using Access Token Without User Info

In case your app requires only an access token and not the user information, then you can specify an optional
configuration in the omniauth initializer:

```ruby
# config/initializers/omniauth.rb
Rails.application.config.middleware.use OmniAuth::Builder do
  provider :oidc, {
    name: :simple_provider_access_token_only,
    fetch_user_info: false, # if not specified, default value of true will be applied
    client_options: {
      identifier: '23575f4602bebbd9a17dbc38d85bd1a77',
      secret: ENV['SIMPLE_PROVIDER_CLIENT_SECRET'],
      config_endpoint: 'https://simpleprovider.com/cdn-cgi/access/sso/oidc/23575f4602bebbd9a17dbc38d85bd1a77/.well-known/openid-configuration'
    }
  }
end
```

When `fetch_user_info` is `false`, user info is extracted from the ID token claims instead of calling the userinfo endpoint. If the userinfo endpoint call fails, the gem also falls back to ID token claims automatically.

### Ending Session

The gem provides two configuration options to allow ending a session simultaneously with your client application and the
OIDC provider.

To use this feature, you need to provide a `logout_path` in the options and an `end_session_endpoint` in the client
options. Here's a sample setup:

```ruby
  provider :oidc, {
    name: :simple_provider,
    client_options: {
      identifier: ENV['SIMPLE_PROVIDER_CLIENT_ID'],
      secret: ENV['SIMPLE_PROVIDER_SECRET'],
      config_endpoint: 'https://simpleprovider.com/1234567890/.well-known/openid-configuration',
      end_session_endpoint: 'https://simpleprovider.com/signout' # URL to end session with OIDC provider
    },
    logout_path: '/logout' # path in your application to end user session
  }
```

* `end_session_endpoint` is the URL to which your client app can redirect to log out the user from the OIDC provider's application. It can be dynamically fetched from the `config_endpoint` response if your OIDC provider specifies it there. Alternatively, you can explicitly provide it in the client options.

* `logout_path` is the URL in your application that can be called to terminate the current user's session.

Using these two configurations, you can ensure that when a user logs out from your application, they are also logged out
from the OIDC provider, providing a seamless logout across multiple services.

This works by calling `other_phase` on every controller request in your application. The method checks if the requested
URL matches the defined `logout_path`. If it does (i.e. current user has requested to log out from your application)
`other_phase` performs a redirect to the `end_session_endpoint` to terminate the user's session with the OIDC provider
and then it returns back to your application and concludes the request to end the current user's session.

For additional details please refer to the [OIDC specification](https://openid.net/specs/openid-connect-session-1_0-17.html#:~:text=%C2%A0TOC-,5.%C2%A0%20RP%2DInitiated%20Logout,-An%20RP%20can).

### Logging

The gem includes built-in logging with automatic sensitive data sanitization. By default, log level is set to WARN.

```ruby
# Set log level
OmniauthOidc::Logging.log_level = Logger::INFO

# Use a custom logger
OmniauthOidc::Logging.logger = Rails.logger
```

If ActiveSupport::Notifications is available (e.g. in Rails), the gem publishes instrumentation events:

- `config.fetch.omniauth_oidc` — OIDC discovery document fetch
- `token.exchange.omniauth_oidc` — authorization code to token exchange
- `userinfo.fetch.omniauth_oidc` — userinfo endpoint call
- `jwks.fetch.omniauth_oidc` — JWKS fetch
- `request_phase.start.omniauth_oidc` — authorization redirect
- `callback_phase.start.omniauth_oidc` — callback processing
- `id_token.verify.omniauth_oidc` — ID token verification

### Error Handling

The gem raises specific error classes that you can rescue in your callback handling:

| Error Class | When Raised |
|---|---|
| `OmniauthOidc::MissingConfigurationError` | Required options (`identifier`, `secret`, `config_endpoint`) are missing |
| `OmniauthOidc::ConfigurationError` | OIDC discovery endpoint fetch fails |
| `OmniauthOidc::TokenError` | Token exchange fails |
| `OmniauthOidc::TokenVerificationError` | JWT format is invalid |
| `OmniauthOidc::TokenExpiredError` | ID token `exp` claim is in the past |
| `OmniauthOidc::InvalidAlgorithmError` | JWT algorithm does not match `client_signing_alg` |
| `OmniauthOidc::InvalidSignatureError` | JWT signature verification fails |
| `OmniauthOidc::InvalidIssuerError` | ID token `iss` does not match expected issuer |
| `OmniauthOidc::InvalidAudienceError` | ID token `aud` does not match client identifier |
| `OmniauthOidc::InvalidNonceError` | ID token `nonce` does not match stored nonce |
| `OmniauthOidc::JwksFetchError` | JWKS endpoint fetch fails |

All error classes inherit from `OmniauthOidc::Error < RuntimeError`.

### Advanced Configuration

You can customize the OIDC strategy further by adding additional configuration options:

| Field                        | Description                                                                                                                                                           | Required                | Default Value                       | Example/Notes                                         |
|------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------|-------------------------|-------------------------------------|-------------------------------------------------------|
| name                         | Arbitrary string to identify OIDC provider and segregate it from other OIDC providers                                                                                 | no                      | `"oidc"`                            | `:simple_provider`                                    |
| issuer                       | Root url for the OIDC authorization server                                                                                                                            | no                      | retrieved from config_endpoint      | `"https://simpleprovider.com"`                        |
| fetch_user_info              | Fetches user information from userinfo endpoint using the access token. If false, user info is extracted from ID token claims                                          | no                      | `true`                              | `fetch_user_info: false`                              |
| client_signing_alg           | Expected JWT signing algorithm. If set, tokens signed with a different algorithm are rejected                                                                          | no                      | `nil` (any algorithm accepted)      | `"RS256"`, `"HS256"`                                  |
| scope                        | OIDC scopes to request. Accepts Array or String; always sent as a space-delimited string                                                                              | `openid` is required    | all scopes offered by OIDC provider | `%w[openid profile email]`                            |
| response_type                | OAuth2 response type expected from OIDC provider during authorization                                                                                                 | no                      | `"code"`                            | `"code"` or `"id_token"`                              |
| state                        | Value to be used for the OAuth2 state parameter on the authorization request. Can be a proc that generates a string                                                   | no                      | Random 16 character string          | `Proc.new { SecureRandom.hex(32) }`                   |
| require_state                | Boolean to indicate if state param should be verified. This is a recommendation by OIDC spec                                                                          | no                      | `true`                              | `true` or `false`                                     |
| response_mode                | The response mode per [OIDC spec](https://openid.net/specs/oauth-v2-form-post-response-mode-1_0.html)                                                                 | no                      | `nil`                               | `:query`, `:fragment`, `:form_post` or `:web_message` |
| display                      | Specifies how OIDC authorization server should display the authentication and consent UI pages to the end user                                                        | no                      | `nil`                               | `:page`, `:popup`, `:touch` or `:wap`                 |
| prompt                       | Specifies whether the OIDC authorization server prompts the end user for reauthentication and consent                                                                 | no                      | `nil`                               | `:none`, `:login`, `:consent` or `:select_account`    |
| send_nonce                   | Include a nonce in the authorization request and verify it in the ID token                                                                                            | no                      | `true`                              | `true` or `false`                                     |
| send_scope_to_token_endpoint | Should the scope parameter be sent to the authorization token endpoint                                                                                                | no                      | `true`                              | `true` or `false`                                     |
| post_logout_redirect_uri     | Logout redirect uri to use per the [session management draft](https://openid.net/specs/openid-connect-session-1_0.html)                                               | no                      | `nil`                               | `"https://your_app.com/logout/callback"`              |
| uid_field                    | Field of the user info response to be used as a unique ID                                                                                                             | no                      | `"sub"`                             | `"sub"` or `"preferred_username"`                     |
| extra_authorize_params       | Hash of extra fixed parameters that will be merged to the authorization request                                                                                       | no                      | `{}`                                | `{"tenant" => "common"}`                              |
| allow_authorize_params       | List of allowed dynamic parameters that will be merged to the authorization request                                                                                   | no                      | `[]`                                | `[:screen_name]`                                      |
| pkce                         | Enable [PKCE flow](https://oauth.net/2/pkce/)                                                                                                                         | no                      | `false`                             | `true` or `false`                                     |
| pkce_verifier                | Specify custom PKCE verifier code                                                                                                                                     | no                      | Random 128-character string         | `Proc.new { SecureRandom.hex(64) }`                   |
| pkce_options                 | Specify custom implementation of the PKCE code challenge/method                                                                                                       | no                      | SHA256(code_challenge) in hex       | Proc to customise the code challenge generation       |
| client_options               | Hash of client options detailed below in a separate table                                                                                                             | yes                     | see below                           | see below                                             |
| jwt_secret_base64            | Specify the base64-encoded secret used to sign the JWT token for HMAC with SHA2 (e.g. HS256) signing algorithms                                                       | no                      | `client_options.secret`             | `"bXlzZWNyZXQ=\n"`                                    |
| client_jwk_signing_key       | JWK or JWKS (as JSON string or Hash) for local signature verification without fetching from `jwks_uri`                                                                | no                      | `nil`                               | `'{"kty":"RSA","n":"...","e":"AQAB"}'`                |
| client_x509_signing_key      | X.509 certificate (PEM format) for local signature verification                                                                                                       | no                      | `nil`                               | PEM string                                            |
| logout_path                  | Log out is only triggered when the request path ends on this path                                                                                                     | no                      | `"/logout"`                         | `"/sign_out"`                                         |
| jwks_cache_ttl               | JWKS cache time-to-live in seconds                                                                                                                                    | no                      | `3600` (1 hour)                     | `7200`                                                |
| hd                           | Google-specific: hosted domain parameter                                                                                                                              | no                      | `nil`                               | `"example.com"`                                       |
| max_age                      | Maximum authentication age in seconds                                                                                                                                 | no                      | `nil`                               | `3600`                                                |
| acr_values                   | Authentication Class Reference (ACR) values per [RFC9470](https://www.rfc-editor.org/rfc/rfc9470.html)                                                                | no                      | `nil`                               | `"c1 c2"`                                             |

Below are options for the `client_options` hash of the configuration:

| Field                  | Description                                                 | Required | Default value                 |
|------------------------|-------------------------------------------------------------|----------|-------------------------------|
| identifier             | OAuth2 client_id                                            |    yes   | `nil`                         |
| secret                 | OAuth2 client secret                                        |    yes   | `nil`                         |
| config_endpoint        | OIDC configuration endpoint                                 |    yes   | `nil`                         |
| scheme                 | HTTP scheme to use                                          |     no   | `"https"`                     |
| host                   | Host of the authorization server                            |     no   | `nil`                         |
| port                   | Port for the authorization server                           |     no   | `443`                         |
| authorization_endpoint | Authorize endpoint on the authorization server              |     no   | retrieved from config_endpoint |
| token_endpoint         | Token endpoint on the authorization server                  |     no   | retrieved from config_endpoint |
| userinfo_endpoint      | User info endpoint on the authorization server              |     no   | retrieved from config_endpoint |
| jwks_uri               | JWKS URI on the authorization server                        |     no   | retrieved from config_endpoint |
| end_session_endpoint   | URL to call to log the user out at the authorization server |     no   | `nil`                         |

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/msuliq/omniauth_oidc. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/msuliq/omniauth_oidc/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the OmniauthOidc project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/msuliq/omniauth_oidc/blob/main/CODE_OF_CONDUCT.md).
