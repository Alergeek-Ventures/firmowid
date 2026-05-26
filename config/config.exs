# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

import Config

# Existing data uses UUIDv4 PKs generated before the uuid_v7 switch.
# Allow Ash to load both v4 and v7 UUIDs from the DB.
config :ash, Ash.Type.UUIDv7, match_v4_uuids?: true

config :ash,
  default_belongs_to_type: :uuid_v7,
  # TEMPORARY: Repo.put_org_id stores org context in the process dictionary.
  # Ash spawns async tasks for relationship loading which don't inherit it,
  # causing org_id loss. This disables async globally — a meaningful performance
  # trade-off (no parallel relationship loading).
  #
  # TODO: remove once Repo.put_org_id is eliminated and all multitenancy is
  # handled via Ash's attribute-based strategy (which passes tenant explicitly).
  disable_async?: true,
  include_embedded_source_by_default?: false,
  show_keysets_for_all_actions?: false,
  allow_forbidden_field_for_relationships_by_default?: true,
  default_page_type: :keyset,
  known_types: [AshMoney.Types.Money],
  policies: [no_filter_static_forbidden_reads?: false],
  keep_read_action_loads_when_loading?: false,
  default_actions_require_atomic?: true,
  read_action_after_action_hooks_in_order?: true,
  bulk_actions_default_to_errors?: true,
  transaction_rollback_on_error?: true,
  redact_sensitive_values_in_errors?: true

config :ash_oban, pro?: false

config :elixir, :time_zone_database, Tz.TimeZoneDatabase

config :esbuild,
  version: "0.28.0",
  firmowid: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{
      "NODE_PATH" => Enum.join([Path.expand("../deps", __DIR__), Mix.Project.build_path()], ":")
    }
  ]

config :ex_cldr,
  default_backend: Firmowid.Cldr,
  default_locale: "pl"

config :ex_money,
  default_cldr_backend: Firmowid.Cldr,
  auto_start_exchange_rate_service: true,
  exchange_rates_retrieve_every: :never,
  exchange_rates_cache_module: Firmowid.Ash.Currencies.DatabaseCache

config :firmowid, ChromicPDF,
  discard_stderr: false,
  no_sandbox: true

config :firmowid, Firmowid.Ash.Currencies.Converter, rates_provider: :mock
config :firmowid, Firmowid.Cldr, locales: ["pl"]

# local mailer uses /mailbox route
config :firmowid, Firmowid.Mailer, adapter: Swoosh.Adapters.Local

config :firmowid, Firmowid.Repo,
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  migration_primary_key: [name: :id, type: :binary_id],
  migration_timestamps: [type: :utc_datetime],
  types: Firmowid.PostgrexTypes

config :firmowid, FirmowidWeb.Core.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [
      html: FirmowidWeb.Infrastructure.Components.ErrorHtml,
      json: FirmowidWeb.Infrastructure.Components.ErrorJson
    ],
    layout: {FirmowidWeb.Infrastructure.Layouts, :root}
  ],
  pubsub_server: Firmowid.PubSub,
  live_view: [signing_salt: "s6RVH6WQ"]

config :firmowid, Oban,
  repo: Firmowid.Repo,
  prefix: "oban",
  engine: Oban.Engines.Basic,
  shutdown_grace_period: to_timeout(second: 25),
  queues: [
    bank_data: 1,
    requisition_checks: 1,
    invoicing: 1,
    cost_invoices: 5,
    inbound_emails: 3,
    ksef_submissions: 2,
    ksef_sessions: 5,
    ksef_fetch: 2,
    default: 1
  ],
  plugins: [
    {Oban.Plugins.Lifeline, rescue_after: to_timeout(minute: 30)},
    {Firmowid.Ash.Ksef.KsefAwarePruner, max_age: 60 * 60 * 24 * 30},
    {Oban.Plugins.Cron,
     timezone: "Europe/Warsaw",
     crontab: [
       {"0 6 1 * *", Firmowid.Ash.Billing.Workers.MonthlySnapshotDispatcher, args: %{}},
       {"0 13 * * *", Firmowid.Ash.Invoicing.Workers.MatchingWorker, args: %{name: "matching"}},
       {"0 */2 * * *", Firmowid.Ash.Ksef.Workers.FetchDispatcher, args: %{}}
     ]}
  ]

# Packmatic URL source - increase connect timeout for batch downloads
config :firmowid, Packmatic.Source.URL, timeout: 30_000

config :firmowid,
  ecto_repos: [Firmowid.Repo],
  generators: [timestamp_type: :utc_datetime],
  ash_domains: [
    Firmowid.Ash.Assistant,
    Firmowid.Ash.Analysis,
    Firmowid.Ash.Blobs,
    Firmowid.Ash.Billing,
    Firmowid.Ash.Core,
    Firmowid.Ash.Currencies,
    Firmowid.Ash.Finances,
    Firmowid.Ash.Invoicing,
    Firmowid.Ash.Payroll,
    Firmowid.Ash.Timetracker,
    Firmowid.Ash.Events,
    Firmowid.Ash.Ksef
  ]

config :jido_ai,
  model_aliases: %{
    fast: "openai:gpt-5-nano",
    capable: "openai:gpt-5-mini",
    reasoning: "openai:gpt-5"
  }

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [
    :request_id,
    :module,
    :org_id,
    :sender,
    :resend_email_id,
    :health_check,
    :user_id,
    :user_email,
    :organization_id,
    :organization_name
  ]

config :phoenix, :json_library, Jason

config :posthog,
  enable: false,
  enable_error_tracking: false

config :spark,
  formatter: [
    remove_parens?: true,
    "Ash.Resource": [
      section_order: [
        :resource,
        :code_interface,
        :actions,
        :policies,
        :pub_sub,
        :preparations,
        :changes,
        :validations,
        :multitenancy,
        :attributes,
        :relationships,
        :calculations,
        :aggregates,
        :identities
      ]
    ],
    "Ash.Domain": [section_order: [:resources, :policies, :authorization, :domain, :execution]]
  ]

config :tailwind,
  version: "4.2.4",
  firmowid: [
    args: ~w(
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

import_config "#{config_env()}.exs"
