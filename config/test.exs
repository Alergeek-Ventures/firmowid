import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :argon2_elixir, t_cost: 1, m_cost: 8

config :ash, policies: [show_policy_breakdowns?: true]

config :firmowid, ChromicPDF, on_demand: true

# In test we don't send emails
config :firmowid, Firmowid.Mailer, adapter: Swoosh.Adapters.Test

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
#
# CI uses DATABASE_URL, local dev can use individual params or set DATABASE_URL
config :firmowid, Firmowid.Repo,
  username: System.get_env("POSTGRES_USER", "postgres"),
  password: System.get_env("POSTGRES_PASSWORD", "postgres"),
  hostname: System.get_env("POSTGRES_HOST", "localhost"),
  database: "firmowid_test#{System.get_env("MIX_TEST_PARTITION")}",
  port: String.to_integer(System.get_env("DB_PORT", "5433")),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 15,
  queue_target: 5_000,
  queue_interval: 10_000,
  ownership_timeout: 300_000

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :firmowid, FirmowidWeb.Core.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  server: false

config :firmowid, Oban, testing: :inline

# stubs for request testing (for now bank_data mostly)
config :firmowid, :bank_data_api_client,
  bank_data_institutions: [
    plug: {Req.Test, :bank_data_institutions}
  ],
  bank_data_institution: [
    plug: {Req.Test, :bank_data_institution}
  ],
  bank_data_requisition: [
    plug: {Req.Test, :bank_data_requisition}
  ],
  bank_data_account: [
    plug: {Req.Test, :bank_data_account}
  ],
  bank_data_transactions: [
    plug: {Req.Test, :bank_data_transactions}
  ]

config :firmowid, :openai_api_key, "test-openai-api-key"
config :firmowid, :reducto_api_key, "test-reducto-api-key"

config :firmowid, :s3,
  scheme: System.get_env("S3_SCHEME", "http://"),
  host: System.get_env("S3_HOST", "localhost"),
  port: String.to_integer(System.get_env("S3_PORT", "4566")),
  region: System.get_env("AWS_REGION", "us-east-1"),
  access_key_id: System.get_env("AWS_ACCESS_KEY_ID", "test"),
  secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY", "test")

config :firmowid, :start_gocardless_token_manager, false

# Keep expected warning noise out of CI test logs.
config :logger, level: :error

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

config :req_llm, openai_api_key: "test-openai-api-key"

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false
