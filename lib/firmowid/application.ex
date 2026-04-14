defmodule Firmowid.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  alias FirmowidWeb.Core.Endpoint

  @impl true
  def start(_type, _args) do
    # Increase backtrace depth from default 8 to 64 so that stacktraces
    # from deep framework calls (Ash, Ecto) include app-level caller frames.
    # Recommended by Ash creator: https://elixirforum.com/t/62934
    :erlang.system_flag(:backtrace_depth, 64)

    Oban.Telemetry.attach_default_logger()
    Ecto.DevLogger.install(Firmowid.Repo)
    attach_sentry_logger_handler()
    Firmowid.SentryLiveViewHandler.setup()

    # Merge AshOban trigger/scheduled_action cron entries into the Oban runtime config.
    ash_oban_config =
      AshOban.config(
        Application.fetch_env!(:firmowid, :ash_domains),
        Application.fetch_env!(:firmowid, Oban),
        require?: false
      )

    Application.put_env(:firmowid, Oban, ash_oban_config)

    children =
      [
        FirmowidWeb.Core.Telemetry,
        Firmowid.Repo,
        {ChromicPDF, Application.get_env(:firmowid, ChromicPDF)},
        {Ecto.Migrator, repos: Application.fetch_env!(:firmowid, :ecto_repos)},
        {DNSCluster, query: Application.get_env(:firmowid, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Firmowid.PubSub},
        Supervisor.child_spec({Cachex, name: :currencies}, id: :currencies_cache),
        Supervisor.child_spec({Cachex, name: :ksef}, id: :ksef_cache),
        Firmowid.Ash.Finances.GoCardless.TokenManager,
        Firmowid.Vault,
        {Oban, Application.fetch_env!(:firmowid, Oban)},
        Firmowid.Ash.Invoicing.Matching.Assistant.MessagesStorage,
        Firmowid.Ash.Currencies.Converter,
        {AshAuthentication.Supervisor, otp_app: :firmowid}
      ] ++
        maybe_posthog_supervisor() ++
        [
          # Start to serve requests, typically the last entry
          Endpoint
        ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Firmowid.Supervisor]
    result = Supervisor.start_link(children, opts)

    result
  end

  defp attach_sentry_logger_handler do
    # Only attach Sentry logger handler when Sentry is configured with a DSN.
    # This prevents attempts to register the handler when Sentry is intentionally disabled.
    case Application.get_env(:sentry, :dsn) do
      nil ->
        :ok

      _dsn ->
        case :logger.add_handler(:firmowid_sentry_handler, Sentry.LoggerHandler, %{
               config: %{metadata: [:file, :line]}
             }) do
          :ok ->
            :ok

          {:error, {:already_exist, :firmowid_sentry_handler}} ->
            :ok

          {:error, {:already_exists, :firmowid_sentry_handler}} ->
            :ok

          {:error, _reason} ->
            :ok
        end
    end
  end

  defp maybe_posthog_supervisor do
    analytics_config = Application.get_env(:firmowid, :analytics, [])

    if analytics_config[:posthog_enabled] do
      # PostHog.Supervisor expects a validated config map
      # Filter out convenience options (enable, enable_error_tracking) that are only for auto-start
      posthog_config =
        :posthog
        |> Application.get_all_env()
        |> Keyword.drop([:enable, :enable_error_tracking])
        |> PostHog.Config.validate!()

      [{PostHog.Supervisor, posthog_config}]
    else
      []
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    Endpoint.config_change(changed, removed)
    :ok
  end
end
