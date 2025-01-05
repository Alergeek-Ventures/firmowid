# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :firmowid,
  ecto_repos: [Firmowid.Repo],
  generators: [timestamp_type: :utc_datetime],
  go_limitless_secret_id: System.get_env("GO_LIMITLESS_SECRET_ID"),
  go_limitless_secret_key: System.get_env("GO_LIMITLESS_SECRET_KEY"),
  uploads_bucket: "firmowid-uploads-dev"

config :firmowid, Firmowid.Repo,
  database: System.get_env("DB_NAME", "firmowid"),
  hostname: System.get_env("DB_HOST", "localhost"),
  username: System.get_env("DB_USER", "postgres"),
  password: System.get_env("DB_PASS", "postgres"),
  port: System.get_env("DB_PORT", "5432"),
  # url: System.get_env("DB_URL", "postgres:postgres@localhost:5432/firmowid"),
  pool_size: 5,
  stacktrace: true,
  show_sensitive_data_on_connection_error: true

# ssl: true,
# ssl_opts: [
#   verify: :verify_none
# ]

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
  access_key_id: "REMOVED_TIGRIS_ACCESS_KEY",
  secret_access_key: "REMOVED_TIGRIS_SECRET_KEY"

config :ex_aws, :s3,
  scheme: "https://",
  host: "fly.storage.tigris.dev"

config :openai,
  api_key:
    "REMOVED_OPENAI_KEY",
  organization_key: "REMOVED_OPENAI_ORGANIZATION"

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
  version: "3.4.3",
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
  queues: [bank_data: 1],
  plugins: [
    # retry orphaned jobs after 30 minutes
    {Oban.Plugins.Lifeline, rescue_after: :timer.minutes(30)},
    # remove jobs after 30 days
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 30},
    {Oban.Plugins.Cron,
     crontab: [
       # this triggers job that's lightweight and runs every hour
       # then in it, we create idempotent jobs for each day
       # for each account. it's done like this to work around
       # Fly.io suspending the machines
       {"0 * * * *", Firmowid.BankData.Worker, args: %{name: "schedule_sync"}}
     ]}
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
