defmodule Firmowid.MixProject do
  use Mix.Project

  def project do
    [
      app: :firmowid,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),

      # TEMP: remove this once https://github.com/jeremyjh/dialyxir/issues/561 is resolved
      dialyzer: [
        flags: [:no_opaque]
      ]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Firmowid.Application, []},
      extra_applications: [:logger, :runtime_tools, :os_mon, :posthog]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:argon2_elixir, "~> 4.1"},
      {:phoenix, "~> 1.7.14"},
      {:phoenix_ecto, "~> 4.5"},
      {:bodyguard, "~> 2.4"},
      {:ecto_sql, "~> 3.11"},
      {:tails, "~> 0.1.11"},
      {:postgrex, ">= 0.0.0"},
      {:uuidv7, "~> 1.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.0.0", override: true},
      {:floki, ">= 0.30.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.3", runtime: Mix.env() == :dev},
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
      {:gettext, "~> 0.20"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"},
      {:ex_cldr, "~> 2.37"},
      {:ex_money, "~> 5.0"},
      {:timex, "~> 3.7"},
      {:faker, "~> 0.18"},
      {:req, "~> 0.5.2"},
      {:ex_aws, "~> 2.5.5"},
      {:ex_aws_s3, "~> 2.0"},
      {:hackney, "~> 1.9"},
      {:sweet_xml, "~> 0.6"},
      {:mime, "~> 2.0"},
      {:akin, "~> 0.2.0"},
      {:openai, "~> 0.6.2"},
      {:live_toast, "~> 0.8.0"},
      {:packmatic, "~> 1.2.0"},
      {:image, "~> 0.37"},
      {:briefly, "~> 0.5.0"},
      {:sentry, "~> 11.0.1"},
      {:recase, "~> 0.8.0"},
      {:oban, "~> 2.17"},
      {:oban_live_dashboard, "~> 0.2.1"},
      {:ecto_psql_extras, "~> 0.6"},
      {:any_ascii, "~> 0.3.2"},
      {:multipart, "~> 0.4.0"},
      {:posthog, "~> 1.1.0"},
      {:reverse_proxy_plug, "~> 3.0"},
      {:ecto_dev_logger, "~> 0.14"},
      {:nx, "~> 0.10"},
      {:mdex, "~> 0.7"},
      {:paradex, "~> 0.4.0"},
      {:sobelow, "~> 0.13", only: [:dev], runtime: Mix.env() == :dev},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: Mix.env() == :dev},
      {:live_debugger, "~> 0.3.0", only: [:dev], runtime: Mix.env() == :dev}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
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
