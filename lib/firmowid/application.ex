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
        Supervisor.child_spec({Cachex, name: :institutions}, id: :institutions_cache),
        Supervisor.child_spec({Cachex, name: :ksef}, id: :ksef_cache),
        {Finch,
         name: Firmowid.Ash.Assistant.Finch,
         pools: %{
           default: [protocols: [:http1], size: 1, count: 16]
         }},
        Firmowid.Vault,
        {Oban, Application.fetch_env!(:firmowid, Oban)},
        Firmowid.Ash.Currencies.Converter,
        {AshAuthentication.Supervisor, otp_app: :firmowid},
        {Jido, name: Jido, otp_app: :firmowid}
      ] ++
        maybe_gocardless_token_manager() ++
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

  defp maybe_gocardless_token_manager do
    if Application.get_env(:firmowid, :start_gocardless_token_manager, true) do
      [Firmowid.Ash.Finances.GoCardless.TokenManager]
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
