import Config

# Only load dotenv in dev/test
if config_env() in [:dev, :test] do
  Dotenv.load!()
end

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/firmowid start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :firmowid, FirmowidWeb.Endpoint, server: true
end

# import_config/1 is not enabled for this configuration file.
# Some configuration files do not allow importing other files as they are often copied to external systems

# The secret key base is used to sign/encrypt cookies and other secrets.
# A default value is used in config/dev.exs and config/test.exs but you
# want to use a different value for prod and you most likely don't want
# to check this value into version control, so we use an environment
# variable instead.
secret_key_base =
  System.get_env("SECRET_KEY_BASE") ||
    raise """
    environment variable SECRET_KEY_BASE is missing.
    You can generate one by calling: mix phx.gen.secret
    """

config :firmowid, FirmowidWeb.Endpoint, secret_key_base: secret_key_base

config :firmowid,
  go_limitless_secret_id: System.get_env("GO_LIMITLESS_SECRET_ID"),
  go_limitless_secret_key: System.get_env("GO_LIMITLESS_SECRET_KEY"),
  reducto_api_key: System.get_env("REDUCTO_API_KEY"),
  openai_api_key: System.get_env("OPENAI_API_KEY"),
  resend_api_key: System.get_env("RESEND_API_KEY"),
  resend_webhook_secret: System.get_env("RESEND_WEBHOOK_SECRET"),
  google_client_id: System.get_env("GOOGLE_CLIENT_ID"),
  google_client_secret: System.get_env("GOOGLE_CLIENT_SECRET")

if config_env() != :test do
  config :firmowid, Firmowid.Repo,
    url: System.get_env("DATABASE_URL"),
    pool_size: String.to_integer(System.get_env("POOL_SIZE", "5"))
end

config :ex_aws, :s3,
  host: System.get_env("S3_HOST", "localhost"),
  scheme: System.get_env("S3_SCHEME", "http://"),
  port: String.to_integer(System.get_env("S3_PORT", "4566"))

# S3 configuration (defaults suitable for local development with localstack)
config :ex_aws,
  # empty strings because ex_aws will complain
  access_key_id: System.get_env("AWS_ACCESS_KEY_ID", ""),
  secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY", "")

# Open Exchange Rates API for currency conversion (optional)
config :ex_money,
  open_exchange_rates_app_id: System.get_env("OPEN_EXCHANGE_RATES_APP_ID")

# PostHog analytics (optional)
# Only configure when API host is present to avoid overriding test config
if System.get_env("POSTHOG_API_URL") do
  config :posthog,
    api_key: System.get_env("POSTHOG_API_KEY"),
    api_host: System.get_env("POSTHOG_API_URL")
end

# ChromicPDF configuration for external Chrome container
# Set CHROME_ADDRESS to point to Chrome DevTools Protocol endpoint
# Format: "hostname:port" (e.g., "localhost:9222" or "chrome:9222")
if config_env() != :test do
  chrome_address = System.get_env("CHROME_ADDRESS")

  if chrome_address do
    [host, port] = String.split(chrome_address, ":")

    config :firmowid, ChromicPDF, chrome_address: {host, String.to_integer(port)}
  end
end

# Sentry error tracking (optional)
config :sentry,
  dsn: System.get_env("SENTRY_DSN")

if config_env() == :prod do
  # SSL configuration for database connection
  # Configure via DATABASE_SSL_CA_CERT environment variable
  # Example: /etc/ssl/certs/ca-certificate.crt
  database_ssl_config =
    case System.get_env("DATABASE_SSL_CA_CERT") do
      nil ->
        # No SSL or rely on DATABASE_URL sslmode parameter
        false

      "" ->
        # Empty string means no SSL config
        false

      cert_path ->
        [
          verify: :verify_peer,
          cacertfile: cert_path,
          server_name_indication: :disable,
          customize_hostname_check: [
            match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
          ]
        ]
    end

  # configures Swoosh SMTP client
  # SendGrid is only used in production and requires an API key
  config :firmowid, Firmowid.Mailer,
    adapter: Resend.Swoosh.Adapter,
    api_key: System.get_env("RESEND_API_KEY")

  if database_ssl_config do
    config :firmowid, Firmowid.Repo, ssl: database_ssl_config
  end

  # PHX_HOST depends on the machine you deploy to, so you need to set it in runtime
  # also only production uses https
  config :firmowid, FirmowidWeb.Endpoint,
    url: [
      host: System.get_env("PHX_HOST") || raise("PHX_HOST environment variable is not set"),
      port: 443,
      scheme: "https"
    ],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: String.to_integer(System.get_env("PORT", "4000"))
    ]
end
