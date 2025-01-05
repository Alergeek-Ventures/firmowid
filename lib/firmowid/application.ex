defmodule Firmowid.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    Oban.Telemetry.attach_default_logger()

    children = [
      FirmowidWeb.Telemetry,
      Firmowid.Repo,
      ChromicPDF,
      {Ecto.Migrator, repos: Application.fetch_env!(:firmowid, :ecto_repos)},
      {DNSCluster, query: Application.get_env(:firmowid, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Firmowid.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: Firmowid.Finch},
      Firmowid.BankData.TokenManager,
      Firmowid.Documents.Reducto,
      {Oban, Application.fetch_env!(:firmowid, Oban)},
      # Start to serve requests, typically the last entry
      FirmowidWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Firmowid.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    FirmowidWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
