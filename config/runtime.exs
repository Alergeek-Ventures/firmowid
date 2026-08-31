import Config

alias FirmowidWeb.Core.Endpoint

if config_env() in [:dev, :test] do
  Firmowid.Config.LocalEnv.load!()
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

ksef_env =
  System.get_env("KSEF_ENV") ||
    raise "KSEF_ENV environment variable is required (allowed: test | prod)"

if ksef_env not in ["test", "prod"] do
  raise "KSEF_ENV must be one of: test, prod"
end

default_ksef_base_url =
  if ksef_env == "prod",
    do: "https://api.ksef.mf.gov.pl/v2/",
    else: "https://api-test.ksef.mf.gov.pl/v2/"

default_ksef_qr_code_base_url =
  if ksef_env == "prod", do: "https://qr.ksef.mf.gov.pl", else: "https://qr-test.ksef.mf.gov.pl"

config :firmowid, Endpoint, secret_key_base: secret_key_base

config :firmowid, Firmowid.Vault,
  ciphers: [
    default: {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V1", key: vault_key}
  ]

config :firmowid, :ksef,
  base_url: default_ksef_base_url,
  qr_code_base_url: default_ksef_qr_code_base_url

config :firmowid,
  go_limitless_secret_id: System.get_env("GO_LIMITLESS_SECRET_ID"),
  go_limitless_secret_key: System.get_env("GO_LIMITLESS_SECRET_KEY"),
  reducto_api_key: System.get_env("REDUCTO_API_KEY") || Application.get_env(:firmowid, :reducto_api_key),
  openai_api_key: System.get_env("OPENAI_API_KEY") || Application.get_env(:firmowid, :openai_api_key),
  resend_api_key: System.get_env("RESEND_API_KEY"),
  resend_webhook_secret: System.get_env("RESEND_WEBHOOK_SECRET"),
  google_client_id: System.get_env("GOOGLE_CLIENT_ID"),
  # use DATABASE_URL if set
  google_client_secret: System.get_env("GOOGLE_CLIENT_SECRET")

# OAuth2 AS access-token signing secret. Prefer a dedicated env var in prod;
# fall back to SECRET_KEY_BASE so existing deploys keep working.
config :firmowid,
  oauth2_signing_secret: System.get_env("OAUTH2_SIGNING_SECRET") || secret_key_base

config :req_llm,
  openai_api_key: System.get_env("OPENAI_API_KEY") || Application.get_env(:firmowid, :openai_api_key)

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
# For real AWS S3, set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY
s3_base = [
  region: System.get_env("AWS_REGION", "us-east-1"),
  access_key_id: System.get_env("AWS_ACCESS_KEY_ID", ""),
  secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY", "")
]

s3_config =
  if System.get_env("S3_PORT") do
    s3_base ++
      [
        host: System.get_env("S3_HOST", "localhost"),
        scheme: System.get_env("S3_SCHEME", "http://"),
        port: String.to_integer(System.get_env("S3_PORT"))
      ]
  else
    s3_base
  end

# Open Exchange Rates API for currency conversion (optional)
config :ex_money,
  open_exchange_rates_app_id: System.get_env("OPEN_EXCHANGE_RATES_APP_ID")

config :firmowid, :s3, s3_config

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
#   POSTHOG_API_HOST - PostHog API host, defaults to "https://i.alergeek.workers.dev"
#   SENTRY_ENVIRONMENT - Sentry environment name, defaults to "production" in prod
posthog_enabled = System.get_env("POSTHOG_ENABLED", "false") == "true"

sentry_environment =
  System.get_env("SENTRY_ENVIRONMENT") ||
    if config_env() == :prod, do: "production", else: to_string(config_env())

sentry_release = System.get_env("SENTRY_RELEASE") || System.get_env("SOURCE_COMMIT")

defmodule RuntimeSentry do
  @moduledoc false

  def validate(nil, _), do: nil
  def validate("disabled", _), do: nil

  def validate(val, name) when is_binary(val) do
    case URI.parse(val) do
      %URI{scheme: scheme, host: host, userinfo: userinfo, path: path}
      when scheme in ["http", "https"] and is_binary(host) and is_binary(userinfo) and
             path not in [nil, "", "/"] ->
        val

      _ ->
        raise "Invalid Sentry DSN in #{name}: #{val}. Provide a valid DSN or the exact token 'disabled'."
    end
  end

  def validate(val, name),
    do: raise("Invalid Sentry DSN in #{name}: #{inspect(val)}. Provide a valid DSN or the exact token 'disabled'.")
end

# Pre-validate frontend and server DSNs
frontend_raw =
  System.get_env(
    "SENTRY_FRONTEND_DSN",
    "https://a2fd6c45d207e5d5b3079064e79d1339@o4511195748630528.ingest.de.sentry.io/4511195751317584"
  )

frontend_sentry = RuntimeSentry.validate(frontend_raw, "SENTRY_FRONTEND_DSN")
server_sentry = RuntimeSentry.validate(System.get_env("SENTRY_DSN"), "SENTRY_DSN")

# If the raw env was the explicit disable token, remove it from process env
# so Sentry's own config fill-in-from-env won't pick it up.
if System.get_env("SENTRY_DSN") == "disabled" do
  System.delete_env("SENTRY_DSN")
end

if posthog_enabled do
  posthog_api_key =
    System.get_env("POSTHOG_API_KEY") ||
      raise "POSTHOG_API_KEY is required when POSTHOG_ENABLED=true"

  posthog_api_host = System.get_env("POSTHOG_API_HOST", "https://i.alergeek.workers.dev")

  config :firmowid, :frontend_observability,
    posthog_enabled: true,
    posthog_api_key: posthog_api_key,
    posthog_api_host: posthog_api_host,
    sentry_dsn: frontend_sentry,
    sentry_environment: sentry_environment,
    sentry_release: sentry_release || ""

  config :posthog,
    enable: true,
    enable_error_tracking: false,
    api_key: posthog_api_key,
    api_host: posthog_api_host
else
  config :firmowid, :frontend_observability,
    posthog_enabled: false,
    posthog_api_key: "",
    posthog_api_host: "",
    sentry_dsn: frontend_sentry,
    sentry_environment: sentry_environment,
    sentry_release: sentry_release || ""

  config :posthog,
    enable: false,
    enable_error_tracking: false
end

# server-side Sentry DSN
config :sentry,
  dsn: server_sentry,
  environment_name: sentry_environment,
  release: sentry_release

# Phoenix HTTP port - only override if PORT is set (worktree)
if config_env() == :dev and System.get_env("PORT") do
  port = String.to_integer(System.get_env("PORT"))

  config :firmowid, Endpoint,
    http: [port: port],
    url: [host: "localhost", port: port]
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
    adapter: Firmowid.Ash.Invoicing.Services.ResendAdapter,
    api_key: System.get_env("RESEND_API_KEY")

  if database_ssl_config do
    config :firmowid, Firmowid.Repo, ssl: database_ssl_config
  end

  # PHX_HOST depends on the machine you deploy to, so we use https
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
