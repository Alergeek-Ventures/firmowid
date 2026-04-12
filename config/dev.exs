import Config

alias FirmowidWeb.Core.Endpoint

config :ash, policies: [show_policy_breakdowns?: true]

config :ash_authentication, debug_authentication_failures?: true

config :firmowid, ChromicPDF, chrome_address: {"localhost", 9222}

config :firmowid, Endpoint,
  http: [port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:firmowid, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:firmowid, ~w(--watch)]}
  ],
  live_reload: [
    patterns: [
      ~r"priv/static/(?!uploads/).*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"priv/gettext/.*(po)$",
      ~r"lib/firmowid_web/(controllers|live|components)/.*(ex|heex)$"
    ]
  ]

config :firmowid, Endpoint, secret_key_base: "REMOVED_PHOENIX_SECRET_KEY_BASE"

# Database (port 5433 matches local/compose.yml)
config :firmowid, Firmowid.Repo,
  url: "postgresql://postgres:postgres@localhost:5433/firmowid",
  pool_size: 5,
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  log: false

# Vault key for Cloak encryption (32 bytes, base64 encoded)
# This is a cryptographically random dev key that matches runtime.exs dev_vault_key.
# Previous key was a human-readable string ("this is a 32 byte key!!") which
# could cause issues when migrating encrypted data between environments.
config :firmowid, Firmowid.Vault,
  ciphers: [
    default:
      {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V1", key: Base.decode64!("REMOVED_DEV_VAULT_KEY")}
  ]

config :firmowid, :analytics, posthog_enabled: false
config :firmowid, :ksef, base_url: "https://api-test.ksef.mf.gov.pl/v2/"

config :firmowid, :s3,
  host: "localhost",
  scheme: "http://",
  port: 4566,
  region: "us-east-1",
  access_key_id: "test",
  secret_access_key: "test"

config :firmowid,
  uploads_bucket: "firmowid-uploads"

# LiveDebugger default port (overridable via DEBUGGER_PORT in .env.local for worktrees)
config :live_debugger,
  ip: {127, 0, 0, 1},
  port: 4007

# Do not include metadata nor timestamps in development logs
config :logger, :console, format: "[$level] $message\n"

config :phoenix, :plug_init_mode, :runtime
config :phoenix, :stacktrace_depth, 20

# Include HEEx debug annotations as HTML comments in rendered markup
# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  debug_heex_annotations: true,
  enable_expensive_runtime_checks: true

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false
