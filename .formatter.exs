[
  import_deps: [
    :ash_authentication_oauth2_server,
    :ash_ai,
    :ash,
    :ash_authentication,
    :ash_authentication_phoenix,
    :ash_postgres,
    :ash_events,
    :ash_oban,
    :ash_state_machine,
    :reactor,
    :ecto,
    :ecto_sql,
    :phoenix,
    :phoenix_live_view
  ],
  subdirectories: ["priv/*/migrations"],
  plugins: [Phoenix.LiveView.HTMLFormatter, Spark.Formatter, Styler],
  inputs: [
    "*.{heex,ex,exs}",
    "{config,lib,test}/**/*.{heex,ex,exs}",
    "scripts/*.exs",
    "priv/*/seeds.exs"
  ],
  attribute_formatters: %{class: CanonicalTailwind}
]
