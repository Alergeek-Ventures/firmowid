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
  version: "0.27.4",
  firmowid: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Enum.join([Path.expand("../deps", __DIR__), Mix.Project.build_path()], ":")}
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
    layout: false
  ],
  pubsub_server: Firmowid.PubSub,
  live_view: [signing_salt: "s6RVH6WQ"]

config :firmowid, Oban,
  repo: Firmowid.Repo,
  prefix: "oban",
  engine: Oban.Engines.Basic,
  queues: [
    bank_data: 1,
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
       {"0 13 * * *", Firmowid.Ash.Invoicing.Workers.MatchingWorker, args: %{name: "matching"}},
       {"0 */2 * * *", Firmowid.Ash.Ksef.Workers.FetchDispatcher, args: %{}}
     ]}
  ]

# Packmatic URL source - increase connect timeout for batch downloads
config :firmowid, Packmatic.Source.URL, timeout: 30_000

config :firmowid, :ksef,
  base_url: "https://api-test.ksef.mf.gov.pl/v2/",
  qr_code_base_url: "https://qr-test.ksef.mf.gov.pl"

config :firmowid,
  ecto_repos: [Firmowid.Repo],
  generators: [timestamp_type: :utc_datetime],
  ash_domains: [
    Firmowid.Ash.Analysis,
    Firmowid.Ash.Blobs,
    Firmowid.Ash.Core,
    Firmowid.Ash.Currencies,
    Firmowid.Ash.Finances,
    Firmowid.Ash.Invoicing,
    Firmowid.Ash.Payroll,
    Firmowid.Ash.Timetracker,
    Firmowid.Ash.Events,
    Firmowid.Ash.Ksef
  ]

config :fun_with_flags, :cache_bust_notifications,
  enabled: true,
  adapter: FunWithFlags.Notifications.PhoenixPubSub,
  client: Firmowid.PubSub

config :fun_with_flags, :persistence,
  adapter: FunWithFlags.Store.Persistent.Ecto,
  repo: Firmowid.Repo

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :module, :org_id, :sender, :resend_email_id]

config :phoenix, :json_library, Jason

# Disable PostHog auto-start - we control it via application.ex based on POSTHOG_ENABLED env var
config :posthog, enable: false

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
  version: "4.2.2",
  firmowid: [
    args: ~w(
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

import_config "#{config_env()}.exs"
