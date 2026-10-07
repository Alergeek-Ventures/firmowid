defmodule FirmowidWeb.Infrastructure.Controllers.Health do
  @moduledoc false
  use FirmowidWeb, :controller

  alias Firmowid.Ash.Invoicing.Services.GotenbergClient
  alias Firmowid.ErrorKind

  require Logger

  @default_checks [:database, :oban, :gotenberg]

  @doc "Returns the health status of the database, Oban and Gotenberg checks."
  @spec check(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def check(conn, _params) do
    checks =
      :firmowid
      |> Application.get_env(:health_checks, @default_checks)
      |> Map.new(fn name -> {name, run_check(name)} end)

    all_healthy = Enum.all?(checks, fn {_key, %{status: status}} -> status == "ok" end)

    status_code = if all_healthy, do: 200, else: 502

    response = %{
      status: if(all_healthy, do: "healthy", else: "unhealthy"),
      timestamp: DateTime.to_iso8601(DateTime.utc_now()),
      checks: checks
    }

    conn
    |> put_status(status_code)
    |> json(response)
  end

  defp run_check(:database), do: check_database()
  defp run_check(:oban), do: check_oban()
  defp run_check(:gotenberg), do: check_gotenberg()

  defp check_gotenberg do
    case GotenbergClient.health() do
      :ok ->
        %{status: "ok", message: "Gotenberg is running"}

      {:error, reason} ->
        Logger.error("Gotenberg health check failed",
          health_check: true,
          error_kind: ErrorKind.classify(reason)
        )

        %{status: "error", message: "Gotenberg is not running"}
    end
  end

  defp check_database do
    case Firmowid.Repo.query("SELECT 1", [], skip_organization_id: true) do
      {:ok, _} ->
        %{status: "ok", message: "Database connection successful"}

      {:error, reason} ->
        Logger.error("Database health check failed",
          health_check: true,
          error_kind: ErrorKind.classify(reason)
        )

        %{status: "error", message: "Database query failed"}
    end
  end

  defp check_oban do
    # Verify Oban supervisor is actually running by querying queue state
    _queue_state = Oban.check_queue(Firmowid.Oban, queue: :default)
    %{status: "ok", message: "Oban is running"}
  rescue
    error ->
      Logger.error("Oban health check failed",
        health_check: true,
        error_kind: ErrorKind.classify(error)
      )

      %{status: "error", message: "Oban is not running"}
  end
end
