import Config

# Only load dotenv in dev/test when .env files exist (skip in CI)
# Load both .env and .env.local (worktree-specific overrides)
alias FirmowidWeb.Core.Endpoint

if config_env() in [:dev, :test] and File.exists?(".env") do
  files = if File.exists?(".env.local"), do: [".env", ".env.local"], else: [".env"]
  Dotenv.load!(files)
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
  config :firmowid, Endpoint, server: true
end

# import_config/1 is not enabled for this configuration file.
# Some configuration files do not allow importing other files as they are often copied to external systems

# The secret key base is used to sign/encrypt cookies and other secrets.
# A default value is used in config/dev.exs and config/test.exs but you
# want to use a different value for prod and you most likely don't want
# to check this value into version control, so we use an environment
# variable instead.
#
# Dev/test default: safe to use for local development only
dev_secret_key_base = "REMOVED_PHOENIX_SECRET_KEY_BASE"
# Dev/test default vault key (32 bytes, base64 encoded)
dev_vault_key = "REMOVED_DEV_VAULT_KEY"

secret_key_base =
  if config_env() == :prod do
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """
  else
    System.get_env("SECRET_KEY_BASE", dev_secret_key_base)
  end

vault_key =
  if config_env() == :prod do
    "CLOAK_VAULT_KEY" |> System.get_env() |> Base.decode64!()
  else
    "CLOAK_VAULT_KEY" |> System.get_env(dev_vault_key) |> Base.decode64!()
  end

config :firmowid, Endpoint, secret_key_base: secret_key_base

config :firmowid, Firmowid.Vault,
  ciphers: [
    default: {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V1", key: vault_key}
  ]

config :firmowid,
  go_limitless_secret_id: System.get_env("GO_LIMITLESS_SECRET_ID"),
  go_limitless_secret_key: System.get_env("GO_LIMITLESS_SECRET_KEY"),
  reducto_api_key: System.get_env("REDUCTO_API_KEY"),
  openai_api_key: System.get_env("OPENAI_API_KEY"),
  resend_api_key: System.get_env("RESEND_API_KEY"),
  resend_webhook_secret: System.get_env("RESEND_WEBHOOK_SECRET"),
  google_client_id: System.get_env("GOOGLE_CLIENT_ID"),
  google_client_secret: System.get_env("GOOGLE_CLIENT_SECRET")

# use DATABASE_URL if set
if System.get_env("DATABASE_URL") do
  database_url = System.get_env("DATABASE_URL")

  # For test env, replace the database name in the URL
  # (setting a separate `database:` key doesn't override the URL)
  database_url =
    if config_env() == :test do
      test_db = "firmowid_test#{System.get_env("MIX_TEST_PARTITION")}"

      # Replace database name in URL: postgresql://user:pass@host:port/dbname -> postgresql://user:pass@host:port/test_dbname
      String.replace(database_url, ~r{/[^/]+$}, "/#{test_db}")
    else
      database_url
    end

  repo_config = [
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE", "5"))
  ]

  config :firmowid, Firmowid.Repo, repo_config
else
  :ok
end

# S3 configuration
# S3_PORT: local dev/worktree (uses localhost)
# S3_HOST/S3_SCHEME/S3_PORT: prod with custom S3-compatible endpoint
# For real AWS S3, just set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY
if System.get_env("S3_PORT") do
  config :ex_aws, :s3,
    host: System.get_env("S3_HOST", "localhost"),
    scheme: System.get_env("S3_SCHEME", "http://"),
    port: String.to_integer(System.get_env("S3_PORT"))
end

# AWS credentials (required for S3 in prod)
config :ex_aws,
  access_key_id: System.get_env("AWS_ACCESS_KEY_ID", ""),
  secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY", "")

# Open Exchange Rates API for currency conversion (optional)
config :ex_money,
  open_exchange_rates_app_id: System.get_env("OPEN_EXCHANGE_RATES_APP_ID")

# S3 bucket for uploads
# ChromicPDF - configure remote Chrome connection
# CHROME_ADDRESS: "host:port" format for prod (e.g., "chromium:9222")
# CHROME_PORT: port only, uses localhost (for local dev/worktree)
config :firmowid,
  uploads_bucket: System.get_env("S3_BUCKET", "firmowid-uploads")

cond do
  chrome_port = System.get_env("CHROME_PORT") ->
    config :firmowid, ChromicPDF, chrome_address: {"localhost", String.to_integer(chrome_port)}

  chrome_address = System.get_env("CHROME_ADDRESS") ->
    [host, port] = String.split(chrome_address, ":")
    config :firmowid, ChromicPDF, chrome_address: {host, String.to_integer(port)}

  true ->
    :ok
end

# Analytics configuration
# Env vars:
#   POSTHOG_ENABLED - enable PostHog analytics, defaults to "false"
#   POSTHOG_API_KEY - PostHog project API key (required if PostHog enabled)
#   POSTHOG_API_HOST - PostHog API host, defaults to "https://eu.i.posthog.com"
posthog_enabled = System.get_env("POSTHOG_ENABLED", "false") == "true"
sentry_release = System.get_env("SENTRY_RELEASE") || System.get_env("SOURCE_COMMIT")

config :firmowid, :analytics, posthog_enabled: posthog_enabled

if posthog_enabled do
  posthog_api_key =
    System.get_env("POSTHOG_API_KEY") ||
      raise "POSTHOG_API_KEY is required when POSTHOG_ENABLED=true"

  posthog_api_host = System.get_env("POSTHOG_API_HOST", "https://eu.i.posthog.com")

  config :firmowid, :frontend_observability,
    posthog_enabled: true,
    posthog_api_key: posthog_api_key,
    posthog_api_host: posthog_api_host,
    sentry_dsn: System.get_env("SENTRY_FRONTEND_DSN", ""),
    sentry_environment: System.get_env("SENTRY_FRONTEND_ENV", to_string(config_env())),
    sentry_release: sentry_release || ""

  config :posthog,
    api_key: posthog_api_key,
    api_host: posthog_api_host
else
  config :firmowid, :frontend_observability,
    posthog_enabled: false,
    posthog_api_key: "",
    posthog_api_host: "",
    sentry_dsn: System.get_env("SENTRY_FRONTEND_DSN", ""),
    sentry_environment: System.get_env("SENTRY_FRONTEND_ENV", to_string(config_env())),
    sentry_release: sentry_release || ""
end

config :sentry, release: sentry_release

# Phoenix HTTP port - only override if PORT is set (worktree)
if config_env() == :dev and System.get_env("PORT") do
  config :firmowid, Endpoint, http: [port: String.to_integer(System.get_env("PORT"))]
end

# LiveDebugger port - only override if DEBUGGER_PORT is set (worktree)
if config_env() == :dev and System.get_env("DEBUGGER_PORT") do
  config :live_debugger, port: String.to_integer(System.get_env("DEBUGGER_PORT"))
end

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
  config :firmowid, Endpoint,
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
