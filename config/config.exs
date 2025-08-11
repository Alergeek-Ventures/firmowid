# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :elixir, :time_zone_database, Tz.TimeZoneDatabase

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  firmowid: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

config :ex_aws, :s3,
  host: "localhost",
  scheme: "http://",
  port: 4566

config :ex_money,
  default_cldr_backend: Firmowid.Cldr,
  auto_start_exchange_rate_service: true,
  exchange_rates_retrieve_every: :never,
  # AV org
  open_exchange_rates_app_id: "b1c5dcca1ebd4066ae1b8c7ef0205be6",
  # open_exchange_rates_app_id: "090a91fcd9d74f32a0813ee30863f231", # test org
  # (for e.g. dev if you need it)
  exchange_rates_cache_module: Firmowid.ExchangeRates.DatabaseCache

config :firmowid, Firmowid.Cldr, locales: ["pl"]
config :firmowid, Firmowid.Currencies, rates_provider: :mock

# local mailer uses /mailbox route
config :firmowid, Firmowid.Mailer, adapter: Swoosh.Adapters.Local

config :firmowid, Firmowid.Repo,
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  migration_primary_key: [name: :id, type: :binary_id],
  migration_timestamps: [type: :utc_datetime],
  types: Firmowid.PostgrexTypes

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

config :firmowid,
  ecto_repos: [Firmowid.Repo],
  generators: [timestamp_type: :utc_datetime],
  uploads_bucket: "firmowid-uploads"

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :module]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :posthog,
  api_url: "https://eu.i.posthog.com",
  api_key: "REMOVED_POSTHOG_PROJECT_KEY"

config :tails, colors_file: Path.join(__DIR__, "../assets/tailwind.colors.json")

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.4.17",
  firmowid: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),

    # Import environment specific config. This must remain at the bottom
    # of this file so it overrides the configuration defined above.
    cd: Path.expand("../assets", __DIR__)
  ]

import_config "#{config_env()}.exs"
