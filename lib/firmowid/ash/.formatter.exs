[
  import_deps: [
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
    :phoenix
  ],
  plugins: [Spark.Formatter, Styler],
  inputs: ["**/*.{ex,exs}"]
]
