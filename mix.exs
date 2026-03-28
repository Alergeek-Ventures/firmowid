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

      # TEMP: remove this once https://github.com/jeremyjh/dialyxir/issues/561 is resolved
      dialyzer: [
        flags: [:no_opaque],
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        plt_add_apps: [:mix, :ex_unit]
      ],
      usage_rules: usage_rules(),
      consolidate_protocols: Mix.env() != :dev
    ]
  end

  def cli do
    [
      preferred_envs: [check: :test]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Firmowid.Application, []},
      extra_applications: [:logger, :runtime_tools, :os_mon, :crypto]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:sourceror, "~> 1.8"},
      {:ash, "~> 3.21"},
      {:ash_postgres, "~> 2.8"},
      {:ash_phoenix, "~> 2.3"},
      {:simple_sat, "~> 0.1"},
      {:cloak_ecto, "~> 1.3.0"},
      {:x509, "~> 0.9"},
      {:argon2_elixir, "~> 4.1"},
      {:elixir_auth_google, "~> 1.6"},
      {:phoenix, "~> 1.8.0"},
      {:phoenix_ecto, "~> 4.5"},
      {:bodyguard, "~> 2.4"},
      {:ecto_sql, "~> 3.11"},
      {:tails, "~> 0.1.11"},
      {:postgrex, ">= 0.0.0"},
      {:uuid_v7, "~> 0.6.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.1.27", override: true},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
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
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"},
      {:ex_cldr, "~> 2.37"},
      {:ex_cldr_dates_times, "~> 2.5"},
      {:ex_cldr_territories, "~> 2.11"},
      {:ex_money, "~> 5.0"},
      {:timex, "~> 3.7"},
      {:faker, "~> 0.18"},
      {:req, "~> 0.5.17"},
      {:ex_aws, "~> 2.6"},
      {:ex_aws_s3, "~> 2.0"},
      {:hackney, "~> 1.9"},
      {:sweet_xml, "~> 0.6"},
      {:mime, "~> 2.0"},
      {:akin, "~> 0.2.0"},
      {:live_toast, "~> 0.8.0"},
      {:packmatic, "~> 2.0.0"},
      {:image, "~> 0.37"},
      {:briefly, "~> 0.5.0"},
      {:error_tracker, "~> 0.7"},
      {:recase, "~> 0.9.0"},
      {:oban, "~> 2.17"},
      {:ecto_psql_extras, "~> 0.6"},
      {:any_ascii, "~> 0.3.3"},
      {:multipart, "~> 0.6.0"},
      {:phoenix_analytics, "~> 0.4"},
      {:posthog, "~> 2.0"},
      {:fun_with_flags, "~> 1.13"},
      {:fun_with_flags_ui, "~> 1.0"},
      {:reverse_proxy_plug, "~> 3.0"},
      {:ecto_dev_logger, "~> 0.14"},
      {:nx, "~> 0.10"},
      {:mdex, "~> 0.7"},
      {:paradex, "~> 0.4.0"},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:openai_ex, "~> 0.9.19"},
      {:live_debugger, "~> 0.4", only: [:dev], runtime: Mix.env() == :dev},
      {:oban_web, "~> 2.11"},
      {:igniter, "~> 0.5", only: [:dev]},
      {:dotenv, "~> 3.1", only: [:dev, :test]},
      {:tidewave, "~> 0.2", only: :dev},
      {:lazy_html, ">= 0.1.0"},
      {:erlsom, "~> 1.5", only: :test},
      {:styler, "~> 1.5", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:cachex, "~> 4.0"},
      {:resend, "~> 0.4.5"},
      {:humanids, "~> 0.1.1"},
      {:websockex, "~> 0.5"},
      {:csv, "~> 3.2"},
      {:lucide_icons, "~> 2.0"},
      {:qr_code, "~> 3.2.0"},
      {:usage_rules, "~> 1.1", only: [:dev]}
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
        {:usage_rules, sub_rules: [:elixir, :otp], main: false, link: :markdown}
      ]
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "usage_rules.sync --yes", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind firmowid", "esbuild firmowid"],
      "assets.deploy": [
        "tailwind firmowid --minify",
        "esbuild firmowid --minify",
        "phx.digest"
      ]
    ]
  end
end
