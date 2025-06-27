# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

# Import secret API keys for the general configuration.
import_config "api_keys/config.exs"

# Import secret API keys for the current configuration.
import_config "api_keys/#{config_env()}.exs"

config :posthog,
  api_url: "https://eu.i.posthog.com",
  api_key: read_config(:posthog)[:api_key]

config :firmowid,
  ecto_repos: [Firmowid.Repo],
  generators: [timestamp_type: :utc_datetime],
  uploads_bucket: "firmowid-uploads"

config :firmowid, Firmowid.Repo,
  url:
    System.get_env(
      "DB_URL",
      "postgresql://postgres:postgres@localhost:5433/firmowid?sslmode=prefer"
    ),
  # -- uncomment when accessing Neon-hosted DB --
  # (forces SSL,doesn't work with docker)
  # - we could probably force it, but not worth the hassle now -
  # ssl: [cacerts: :public_key.cacerts_get()],
  pool_size: 5,
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  migration_primary_key: [name: :id, type: :binary_id],
  migration_timestamps: [type: :utc_datetime]

# Configures the endpoint
config :firmowid, FirmowidWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: FirmowidWeb.ErrorHTML, json: FirmowidWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Firmowid.PubSub,
  live_view: [signing_salt: "s6RVH6WQ"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :firmowid, Firmowid.Mailer, adapter: Swoosh.Adapters.Local

config :firmowid, Firmowid.Cldr, locales: ["pl"]

config :ex_money,
  default_cldr_backend: Firmowid.Cldr,
  auto_start_exchange_rate_service: true,
  exchange_rates_retrieve_every: :never,
  open_exchange_rates_app_id: "b1c5dcca1ebd4066ae1b8c7ef0205be6"

config :ex_aws,
  access_key_id: read_config(:ex_aws)[:access_key_id],
  secret_access_key: read_config(:ex_aws)[:secret_access_key]

config :ex_aws, :s3,
  scheme: "https://",
  host: "fly.storage.tigris.dev"

config :openai,
  api_key: read_config(:openai)[:api_key],
  organization_key: read_config(:openai)[:organization_key]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  firmowid: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.4.17",
  firmowid: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

config :tails, colors_file: Path.join(File.cwd!(), "assets/tailwind.colors.json")

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# defined here because moving to firmowid/oban.ex makes dashboard misbehave :(
config :firmowid, Oban,
  repo: Firmowid.Repo,
  prefix: "oban",
  engine: Oban.Engines.Basic,
  queues: [bank_data: 1, invoicing: 1, cost_invoices: 5],
  plugins: [
    # retry orphaned jobs after 30 minutes
    {Oban.Plugins.Lifeline, rescue_after: :timer.minutes(30)},
    # remove jobs after 30 days
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 30},
    {Oban.Plugins.Cron,
     timezone: "Europe/Warsaw",
     crontab: [
       {"0 12 */2 * *", Firmowid.BankData.Worker,
        args: %{name: "dispatch_sync_jobs_for_all_bank_accounts"}},
       {"0 13 * * *", Firmowid.Invoicing.Worker, args: %{name: "matching"}}
     ]}
  ]

config :elixir, :time_zone_database, Tz.TimeZoneDatabase

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
