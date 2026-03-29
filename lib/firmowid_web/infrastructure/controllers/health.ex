defmodule FirmowidWeb.Infrastructure.Controllers.Health do
  @moduledoc false
  use FirmowidWeb, :controller

  require Logger

  def check(conn, _params) do
    checks = %{
      database: check_database(),
      oban: check_oban()
    }

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

  defp check_database do
    case Firmowid.Repo.query("SELECT 1", [], skip_organization_id: true) do
      {:ok, _} ->
        %{status: "ok", message: "Database connection successful"}

      {:error, reason} ->
        Logger.error("Database health check failed: #{inspect(reason)}")
        %{status: "error", message: "Database query failed", error: inspect(reason)}
    end
  end

  defp check_oban do
    # Verify Oban supervisor is actually running by querying queue state
    _queue_state = Oban.check_queue(Firmowid.Oban, queue: :default)
    %{status: "ok", message: "Oban is running"}
  rescue
    error ->
      Logger.error("Oban health check failed: #{inspect(error)}")
      %{status: "error", message: "Oban is not running", error: inspect(error)}
  end
end
