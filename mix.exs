defmodule Firmowid.MixProject do
  use Mix.Project

  def project do
    [
      app: :firmowid,
      version: "0.1.0",
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader],
      test_paths: ["lib"],
      test_pattern: "*_test.exs",
      test_coverage: [tool: ExCoveralls],
      licenses: ["AGPL-3.0-or-later"],

      # TEMP: remove this once https://github.com/jeremyjh/dialyxir/issues/561 is resolved
      dialyzer: [
        flags: [:no_opaque],
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        plt_add_apps: [:mix, :ex_unit, :esc]
      ],
      usage_rules: usage_rules(),
      consolidate_protocols: Mix.env() != :dev
    ]
  end

  def cli do
    [
      preferred_envs: [
        check: :test,
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.html": :test,
        "coveralls.json": :test,
        "coveralls.xml": :test,
        "coveralls.cobertura": :test,
        "coveralls.lcov": :test
      ]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Firmowid.Application, []},
      extra_applications: [:logger, :runtime_tools, :os_mon, :crypto, :sentry]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:ash_authentication_oauth2_server, "~> 0.3.1"},
      {:ash_ai, "~> 1.0.3"},
      {:sourceror, "~> 1.8"},
      {:ash, "~> 3.33.1"},
      {:ash_postgres, "~> 2.13.1"},
      {:ash_phoenix, "~> 2.3"},
      {:ash_oban, "~> 0.8.7"},
      {:ash_jido, "== 1.0.1"},
      {:ash_authentication, "~> 5.0.0-rc"},
      {:assent, "~> 0.3.0"},
      {:nimble_totp, "~> 1.0"},
      {:ash_authentication_phoenix, "~> 3.0.0-rc"},
      {:ash_state_machine, "~> 0.2.12"},
      {:ash_events, "~> 0.7"},
      {:simple_sat, "~> 0.1"},
      {:cloak_ecto, "~> 1.3.0"},
      {:x509, "~> 0.9"},
      {:argon2_elixir, "~> 4.1"},
      {:phoenix, "~> 1.8.0"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.14.0"},
      {:postgrex, ">= 0.0.0"},
      {:uuid_v7, "~> 0.6.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.2.1"},
      {:phoenix_live_dashboard, "~> 0.9.0"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.4", runtime: Mix.env() == :dev},
      {:tz, "~> 0.28"},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       runtime: false,
       depth: 1},
      {:swoosh, "~> 1.6"},
      {:chromic_pdf, "~> 1.17"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 1.0", override: true},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.3.0"},
      {:bandit, "~> 1.5"},
      {:ex_cldr, "~> 2.37"},
      {:ex_cldr_dates_times, "~> 2.5"},
      {:ex_cldr_territories, "~> 2.11"},
      {:ash_money, "~> 0.2.6"},
      {:ex_money, "~> 6.2.1"},
      {:ex_money_sql, "~> 2.1.0"},
      {:req, "~> 0.7.3", override: true},
      {:req_s3, "~> 0.2.3"},
      {:sign_core, "~> 0.1.4"},
      {:sweet_xml, "~> 0.6"},
      {:mime, "~> 2.0"},
      {:akin, "~> 0.2.0"},
      {:live_toast, "~> 0.10.0"},
      {:packmatic, "~> 2.0.0"},
      {:image, "~> 0.37"},
      {:briefly, "~> 0.5.0"},
      {:sentry, "~> 13.0"},
      {:recase, "~> 0.9.0"},
      {:oban, "~> 2.21"},
      {:ecto_psql_extras, "~> 0.6"},
      {:any_ascii, "~> 0.3.3"},
      {:multipart, "~> 0.6.0"},
      {:posthog, "~> 2.15.0"},
      {:ecto_dev_logger, "~> 0.14"},
      {:nx, "~> 0.10"},
      {:mdex, "~> 0.7"},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:openai_ex, "~> 0.9.19"},
      {:req_llm, "~> 1.22.0"},
      {:live_debugger, "~> 1.0", only: [:dev], runtime: Mix.env() == :dev},
      {:oban_web, "~> 2.11"},
      {:igniter, "~> 0.5", only: [:dev]},
      {:tidewave, "~> 0.2", only: :dev},
      {:lazy_html, ">= 0.1.0"},
      {:erlsom, "~> 1.5", only: [:dev, :test]},
      {:styler, "~> 1.5", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ash_credo, "~> 0.12", only: [:dev, :test], runtime: false},
      {:credo_naming, "~> 2.1", only: [:dev, :test], runtime: false},
      {:ex_slop, "~> 0.4.0", only: [:dev, :test], runtime: false},
      {:ex_dna, "~> 1.5.1", only: [:dev, :test], runtime: false},
      {:cachex, "~> 4.0"},
      {:resend, "~> 1.0.0-rc.3"},
      {:humanids, "~> 0.2.0"},
      {:websockex, "~> 0.5"},
      {:jido, "~> 2.2"},
      {:jido_ai, "~> 2.1"},
      {:csv, "~> 3.2"},
      {:lucide_icons, "~> 2.0"},
      {:eqrcode, "~> 0.2.1"},
      {:usage_rules, "~> 1.2.8", only: [:dev]},
      {:canonical_tailwind, "~> 0.1", only: [:dev, :test], runtime: false},
      {:depscheck, "~> 1.0.11", only: [:dev, :test], runtime: false},
      {:esc, "~> 0.9", runtime: false}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp usage_rules do
    [
      file: "AGENTS.md",
      usage_rules: [
        {"phoenix:ecto", link: :markdown},
        {"phoenix:html", link: :markdown},
        {"phoenix:liveview", link: :markdown},
        {"phoenix:phoenix", link: :markdown},
        {:ash,
         sub_rules: [
           :actions,
           :aggregates,
           :authorization,
           :calculations,
           :code_interfaces,
           :code_structure,
           :data_layers,
           :exist_expressions,
           :generating_code,
           :migrations,
           :query_filter,
           :querying_data,
           :relationships,
           :testing
         ],
         link: :markdown},
        {"ash_postgres", link: :markdown},
        {:usage_rules, sub_rules: [:elixir, :otp], main: false, link: :markdown}
      ]
    ]
  end

  defp aliases do
    [
      "localize.setup": ["localize.download_locales pl"],
      setup: [
        "deps.get",
        "localize.setup",
        "db.setup",
        "usage_rules.sync --yes",
        "assets.setup",
        "assets.build"
      ],
      "db.setup": ["ash.setup", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ash_postgres.drop --force --force-drop", "db.setup"],
      test: ["ash_postgres.drop --force --force-drop --quiet", "ash.setup --quiet", "test"],
      "assets.setup": ["cmd npm ci --prefix assets", "esbuild.install --if-missing"],
      "assets.build": ["tailwind firmowid", "esbuild firmowid"],
      "assets.deploy": [
        "tailwind firmowid --minify",
        "esbuild firmowid --minify",
        "phx.digest"
      ],
      "assets.sentry.deploy": [
        "tailwind firmowid --minify",
        "esbuild firmowid --minify --sourcemap=external",
        "phx.digest"
      ],
      "assets.licenses": ["cmd npm run licenses:check --prefix assets"]
    ]
  end
end
