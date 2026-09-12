defmodule Mix.Tasks.Dev.Status do
  @shortdoc "Checks the health of worktree dev services"

  @moduledoc """
  Displays the worktree development environment endpoints and checks each service.

  The task only performs bounded health checks; it does not start or stop any
  services. Configuration is read from `.env.worktree` (or the defaults used by
  `mix dev.up` when that file is missing).

  ## Usage

      mix dev.status
  """

  use Mix.Task

  alias Mix.Tasks.Dev.Shared

  @timeout 500

  @impl Mix.Task
  def run(_args) do
    Application.ensure_all_started(:req)

    env = load_env()
    Shared.print_environment(env, caddy_port())

    results = [
      {"Phoenix", check_http("http://localhost:#{env["PORT"]}", &http_response?/1)},
      {
        "Tidewave",
        check_http("http://localhost:#{env["PORT"]}/tidewave/mcp", &tidewave_response?/1)
      },
      {"PostgreSQL", check_postgres(env["DB_PORT"])},
      {
        "S3",
        check_http("http://localhost:#{env["S3_PORT"]}/healthz", &success_response?/1)
      },
      {
        "Chromium",
        check_http("http://localhost:#{env["CHROME_PORT"]}/json/version", &success_response?/1)
      },
      {"LiveDebugger", check_tcp(env["DEBUGGER_PORT"])}
    ]

    print_results(results)

    if Enum.any?(results, fn {_service, result} -> result != :healthy end) do
      Mix.raise("One or more development services are unhealthy")
    end
  end

  defp load_env do
    case File.read(".env.worktree") do
      {:ok, content} ->
        Mix.shell().info("Loading configuration from .env.worktree")
        Map.merge(Shared.defaults(), Shared.parse_env(content))

      {:error, :enoent} ->
        Mix.shell().info("No .env.worktree found, using defaults (main branch setup)")
        Shared.defaults()
    end
  end

  defp print_results(results) do
    Mix.shell().info("Service health:")

    Enum.each(results, fn {service, result} ->
      case result do
        :healthy -> Mix.shell().info("  #{service}: healthy")
        {:unhealthy, reason} -> Mix.shell().error("  #{service}: unhealthy (#{reason})")
      end
    end)
  end

  defp check_http(url, response_predicate) do
    case Req.get(url,
           retry: false,
           connect_options: [timeout: @timeout],
           receive_timeout: @timeout
         ) do
      {:ok, %{status: status}} ->
        if response_predicate.(status), do: :healthy, else: {:unhealthy, "HTTP #{status}"}

      {:error, reason} ->
        {:unhealthy, format_reason(reason)}
    end
  rescue
    error -> {:unhealthy, Exception.message(error)}
  end

  defp check_postgres(port) do
    case System.cmd("pg_isready", ["-h", "localhost", "-p", to_string(port), "-t", "1"], stderr_to_stdout: true) do
      {_output, 0} -> :healthy
      {output, code} -> {:unhealthy, "exit #{code}: #{String.trim(output)}"}
    end
  rescue
    error -> {:unhealthy, Exception.message(error)}
  end

  defp check_tcp(port) do
    case :gen_tcp.connect(~c"localhost", String.to_integer(to_string(port)), [], @timeout) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        :healthy

      {:error, reason} ->
        {:unhealthy, format_reason(reason)}
    end
  rescue
    error -> {:unhealthy, Exception.message(error)}
  end

  defp http_response?(status), do: status in 100..599
  defp tidewave_response?(status), do: status == 405
  defp success_response?(status), do: status in 200..299

  defp format_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp format_reason(reason), do: inspect(reason)

  defp caddy_port do
    System.get_env("CADDY_PORT") || "8080"
  end
end
