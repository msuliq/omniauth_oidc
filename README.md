# OmniAuth::Oidc

This gem provides an OmniAuth strategy for integrating OpenID Connect (OIDC) authentication into your Ruby on Rails application. It allows seamless login using various OIDC providers.

Developed with reference to [omniauth-openid-connect](https://github.com/jjbohn/omniauth-openid-connect) and [omniauth_openid_connect](https://github.dev/omniauth/omniauth_openid_connect).

## Installation

To install the gem run the following command in the terminal:

    $ bundle add omniauth_oidc

If bundler is not being used to manage dependencies, install the gem by executing:

    $ gem install omniauth_oidc


## Usage

To use the OmniAuth OIDC strategy, you need to configure your Rails application and set up the necessary environment variables for OIDC client credentials.

### Configuration
You have to provide Client ID, Client Secret and url for the OIDC configuration endpoint as a bare minimum for the `omniauth_oidc` to work properly.
Create an initializer file at `config/initializers/omniauth.rb`

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

With Devise

```ruby
Devise.setup do |config|
  config.omniauth :oidc, {
    name: :simple_provider,
    scope: [:openid, :email, :profile, :address],
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

The gem also supports a wide range of optional parameters for higher degree of configurability.

```ruby
# config/initializers/omniauth.rb
Rails.application.config.middleware.use OmniAuth::Builder do
  provider :oidc, {
    name: :complex_provider, # used for dynamic routing
    issuer: 'https://complexprovider.com/cdn-cgi/access/sso/oidc/23575f4602bebbd9a17dbc38d85bd1a77',
    scope: [:openid],
    response_type: 'id_token',
    require_state: true,
    response_mode: :query,
    prompt: :login,
    send_nonce: false,
    uid_field: "sub",
    pkce: false,
    client_options: {
      identifier: '23575f4602bebbd9a17dbc38d85bd1a77',
      secret: ENV['COMPLEX_PROVIDER_CLIENT_SECRET'],
      config_endpoint: 'https://complexprovider.com/cdn-cgi/access/sso/oidc/23575f4602bebbd9a17dbc38d85bd1a77/.well-known/openid-configuration',
      host: 'complexprovider.com'
      scheme: "https",
      port: 443,
      authorization_endpoint: 'https://complexprovider.com/cdn-cgi/access/sso/oidc/23575f4602bebbd9a17dbc38d85bd1a77/authorization',
      token_endpoint: 'https://complexprovider.com/cdn-cgi/access/sso/oidc/23575f4602bebbd9a17dbc38d85bd1a77/token',
      userinfo_endpoint: 'https://complexprovider.com/cdn-cgi/access/sso/oidc/23575f4602bebbd9a17dbc38d85bd1a77/userinfo',
      jwks_uri: 'https://complexprovider.com/cdn-cgi/access/sso/oidc/23575f4602bebbd9a17dbc38d85bd1a77/jwks',
      end_session_endpoint: '/signout'
    }
  }
end
```

Ensure to replace identifier, secret, configuration endpoint url and others with credentials received from your OIDC provider.

### Redirecting for Authentication

Buttons and links to initialize the authentication request can be placed on relevant pages as below:

```ruby
<%= button_to "Login with Simple Provider", "/auth/simple_provider" %>
```

### Handling Callbacks

The gem uses dyanmic routes to handle different phases, and while you can use same routes in your Rails application, for
better experience you should have a controller to process the authenticated user. Create a CallbacksController:

```ruby
# app/controllers/callbacks_controller.rb
class CallbacksController < ApplicationController
  def omniauth
    # user info received from OIDC provider will be available in `request.env['omniauth.auth']`
    auth = request.env['omniauth.auth']

    user = User.find_or_create_by(uid: auth['uid']) do |user|
      user.name = auth['info']['name']
      user.email = auth['info']['email']
    end

    session[:user_id] = user.id
    redirect_to root_path, notice: 'Successfully logged in!'
  end
end
```

### Routes

The gem uses dynamic routes when making requests to the OIDC provider endpoints. These routes follow the naming pattern
of `https://your_app.com/auth/<simple_provider>/callback`, where `<simple_provider>` is the provider name defined
within the configuration of the `omniauth.rb` initializer.

Dynamic routes are used to process responses and perform intermediary steps by the middleware, e.g. request phase,
token verification. While you can define and use same routes within your Rails app, you can modify your `routes.rb`
to perform a dynamic redirect to a another controller method. In an example below, all OIDC responses are ultimately
redirected to the `omniauth` method of the `callbacks_controller`, which is a universal method to handle authentication
with various omniauth providers:

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
as a callback redirect url.**


### Advanced Configuration
You can customize the OIDC strategy further by adding additional configuration options:

| Field                        | Description                                                                                                                                                           | Required                | Default Value                       | Example/Notes                                         |
|------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------|-------------------------|-------------------------------------|-------------------------------------------------------|
| name                         | Arbitrary string to identify OIDC provider and segregate it from other OIDC providers                                                                                 | no                      | `"oidc"`                            | `:simple_provider`                                    |
| issuer                       | Root url for the OIDC authorization server                                                                                                                            | no                      | retrived from config_endpoint       | `"https://simpleprovider.com"`                        |
| client_auth_method           | Authentication method to be used with the OIDC authorization server                                                                                                   | no                      | `:basic`                            | `"basic"`, `"jwks"`                                   |
| scope                        | OIDC scopes to be included in the server's response                                                                                                                   | `[:openid]` is required | all scopes offered by OIDC provider | `[:openid, :profile, :email]`                         |
| response_type                | OAuth2 response type expected from OIDC provider during authorization                                                                                                 | no                      | `"code"`                            | `"code"` or `"id_token"`                              |
| state                        | Value to be used for the OAuth2 state parameter on the authorization request. Can be a proc that generates a string                                                   | no                      | Random 16 character string          | `Proc.new { SecureRandom.hex(32) }`                   |
| require_state                | Boolean to indicate if state param should be verified. This is a recommendation by OIDC spec                                                                          | no                      | `true`                              | `true` or `false`                                     |
| response_mode                | The response mode per [OIDC spec](https://openid.net/specs/oauth-v2-form-post-response-mode-1_0.html)                                                                 | no                      | `nil`                               | `:query`, `:fragment`, `:form_post` or `:web_message` |
| display                      | Specifies how OIDC authorization server should display the authentication and consent UI pages to the end user                                                        | no                      | `nil`                               | `:page`, `:popup`, `:touch` or `:wap`                 |
| prompt                       | Specifies whether the OIDC authorization server prompts the end user for reauthentication and consent                                                                 | no                      | `nil`                               | `:none`, `:login`, `:consent` or `:select_account`    |
| send_scope_to_token_endpoint | Should the scope parameter be sent to the authorization token endpoint                                                                                                | no                      | `true`                              | `true` or `false`                                     |
| post_logout_redirect_uri     | Logout redirect uri to use per the [session management draft](https://openid.net/specs/openid-connect-session-1_0.html)                                               | no                      | `nil`                               | `"https://your_app.com/logout/callback"`              |
| uid_field                    | Field of the user info response to be used as a unique ID                                                                                                             | no                      | `'sub'`                             | `"sub"` or `"preferred_username"`                     |
| extra_authorize_params       | Hash of extra fixed parameters that will be merged to the authorization request                                                                                       | no                      | `{}`                                | `{"tenant" => "common"}`                              |
| allow_authorize_params       | List of allowed dynamic parameters that will be merged to the authorization request                                                                                   | no                      | `[]`                                | `[:screen_name]`                                      |
| pkce                         | Enable [PKCE flow](https://oauth.net/2/pkce/)                                                                                                                         | no                      | `false`                             | `true` or `false`                                     |
| pkce_verifier                | Specify custom PKCE verifier code                                                                                                                                     | no                      | Random 128-character string         | `Proc.new { SecureRandom.hex(64) }`                   |
| pkce_options                 | Specify custom implementation of the PKCE code challenge/method                                                                                                       | no                      | SHA256(code_challenge) in hex       | Proc to customise the code challenge generation       |
| client_options               | Hash of client options detailed below in a separate table                                                                                                             | yes                     | see below                           | see below                                             |
| jwt_secret_base64            | Specify the base64-encoded secret used to sign the JWT token for HMAC with SHA2 (e.g. HS256) signing algorithms                                                       | no                      | `client_options.secret`             | `"bXlzZWNyZXQ=\n"`                                    |
| logout_path                  | Log out is only triggered when the request path ends on this path                                                                                                     | no                      | `'/logout'`                         | '/sign_out'                                           |
| acr_values                   | Authentication Class Reference (ACR) values to be passed to the authorize_uri to enforce a specific level, see [RFC9470](https://www.rfc-editor.org/rfc/rfc9470.html) | no                      | `nil`                               | `"c1 c2"`                                             å|


Below are options for the `client_options` hash of the configuration:

| Field                  | Description                                                 | Required | Default value                 |
|------------------------|-------------------------------------------------------------|----------|-------------------------------|
| identifier             | OAuth2 client_id                                            |    yes   | `nil`                         |
| secret                 | OAuth2 client secret                                        |    yes   | `nil`                         |
| config_endpoint        | OIDC configuration endpoint                                 |    yes   | `nil`                         |
| scheme                 | http scheme to use                                          |     no   | https                         |
| host                   | host of the authorization server                            |     no   | nil                           |
| port                   | port for the authorization server                           |     no   | 443                           |
| authorization_endpoint | authorize endpoint on the authorization server              |     no   | retrived from config_endpoint |
| token_endpoint         | token endpoint on the authorization server                  |     no   | retrived from config_endpoint |
| userinfo_endpoint      | user info endpoint on the authorization server              |     no   | retrived from config_endpoint |
| jwks_uri               | jwks_uri on the authorization server                        |     no   | retrived from config_endpoint |
| end_session_endpoint   | url to call to log the user out at the authorization server |     no   | `nil`                         |

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/msuliq/omniauth_oidc. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/msuliq/omniauth_oidc/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the OmniauthOidc project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/msuliq/omniauth_oidc/blob/main/CODE_OF_CONDUCT.md).
