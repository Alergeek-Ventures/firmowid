defmodule Firmowid.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      FirmowidWeb.Telemetry,
      Firmowid.Repo,
      {Ecto.Migrator,
        repos: Application.fetch_env!(:firmowid, :ecto_repos),
        skip: skip_migrations?()},
      {DNSCluster, query: Application.get_env(:firmowid, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Firmowid.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: Firmowid.Finch},
      # Start a worker by calling: Firmowid.Worker.start_link(arg)
      # {Firmowid.Worker, arg},
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

  defp skip_migrations?() do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") != nil
  end
end
