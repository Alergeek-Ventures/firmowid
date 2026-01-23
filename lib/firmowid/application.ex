defmodule Firmowid.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    Oban.Telemetry.attach_default_logger()
    Ecto.DevLogger.install(Firmowid.Repo)

    children =
      [
        FirmowidWeb.Telemetry,
        Firmowid.Repo,
        {ChromicPDF, Application.get_env(:firmowid, ChromicPDF)},
        {Ecto.Migrator, repos: Application.fetch_env!(:firmowid, :ecto_repos)},
        {DNSCluster, query: Application.get_env(:firmowid, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Firmowid.PubSub},
        Supervisor.child_spec({Cachex, name: :currencies}, id: :currencies_cache),
        Supervisor.child_spec({Cachex, name: :ksef}, id: :ksef_cache),
        Firmowid.BankData.TokenManager,
        Firmowid.Vault,
        Firmowid.Oban,
        Firmowid.Invoicing.Matching.Assistant.MessagesStorage,
        Firmowid.Currencies
      ] ++
        maybe_posthog_supervisor() ++
        [
          # Start to serve requests, typically the last entry
          FirmowidWeb.Endpoint
        ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Firmowid.Supervisor]
    Supervisor.start_link(children, opts)
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
    FirmowidWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
