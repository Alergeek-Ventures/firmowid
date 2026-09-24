defmodule Mix.Tasks.Dev.Restart do
  @shortdoc "Restarts selected worktree development services"

  @moduledoc """
  Interactively restarts selected worktree development services.

  Phoenix includes Tidewave and LiveDebugger. Selecting PostgreSQL selects the
  entire environment. It is a destructive full environment reset: it runs
  `mix dev.down` followed by `mix dev.up`, including
  removal of compose volumes. Escape or `q` cancels the operation.

  ## Usage

      mix dev.restart
  """

  use Mix.Task

  alias Mix.Tasks.Dev.Shared

  @targets [
    {"Phoenix (includes Tidewave + LiveDebugger)", :phoenix},
    {"S3", :s3},
    {"Gotenberg", :gotenberg},
    {"PostgreSQL (restarts the entire environment: full down/up + volumes)", :postgresql}
  ]

  @all_targets [:phoenix, :s3, :gotenberg, :postgresql]
  @impl Mix.Task
  def run(_args) do
    Application.ensure_all_started(:req)

    case choose_targets() do
      {:ok, targets} ->
        targets = normalize_targets(targets)

        if :postgresql in targets do
          restart_database()
        else
          restart_selected(targets)
        end

      :cancelled ->
        Mix.shell().info("Restart cancelled; no services were changed.")
    end
  end

  defp choose_targets do
    @targets
    |> Esc.MultiSelect.new()
    |> Esc.MultiSelect.markers("[x] ", "[ ] ")
    |> Esc.MultiSelect.min_selections(1)
    |> Esc.MultiSelect.run()
  end

  defp normalize_targets(targets) do
    if :postgresql in targets, do: @all_targets, else: targets
  end

  defp restart_database do
    answer =
      Mix.shell().prompt("PostgreSQL restart runs mix dev.down and mix dev.up, removing all volumes. Continue? [y/N] ")

    if String.downcase(String.trim(answer)) in ["y", "yes"] do
      run_task("dev.down")
      run_task("dev.up")
      run_status()
    else
      Mix.shell().info("Restart cancelled; no services were changed.")
    end
  end

  defp restart_selected(targets) do
    env = Shared.load_env()
    compose_targets = Enum.filter(targets, &(&1 in [:s3, :gotenberg]))

    if compose_targets != [] do
      services = Enum.map(compose_targets, &Atom.to_string/1)
      Mix.shell().info("Restarting #{Enum.join(services, ", ")}...")

      result =
        Shared.podman(
          ["compose", "-f", "local/compose.yml", "restart" | services],
          Shared.compose_env(env)
        )

      case result do
        {output, 0} -> Mix.shell().info(output)
        {output, code} -> Mix.raise("Podman Compose restart failed (exit #{code}): #{output}")
      end

      Enum.each(compose_targets, fn target -> wait_for_service(target, env[port_key(target)]) end)
    end

    if :phoenix in targets do
      Mix.Tasks.Dev.Down.stop_phoenix_server()

      case Shared.wait_for_port_closed(env["PORT"]) do
        :ok ->
          :ok

        {:error, :timeout} ->
          Mix.raise("Phoenix port #{env["PORT"]} did not close before restart")
      end

      Mix.Tasks.Dev.Up.start_phoenix_server(env["PORT"])

      case Shared.wait_for_http("http://localhost:#{env["PORT"]}", &phoenix_response?/1) do
        :ok ->
          Mix.shell().info("Phoenix is ready")

        {:error, :timeout} ->
          Mix.raise("Phoenix did not return an HTTP response after 30 seconds")
      end
    end

    run_status()
  end

  defp wait_for_service(:s3, port) do
    wait_for_http_service("S3", "http://localhost:#{port}/healthz", &success_response?/1)
  end

  defp wait_for_service(:gotenberg, port) do
    wait_for_http_service(
      "Gotenberg",
      "http://localhost:#{port}/health",
      &success_response?/1
    )
  end

  defp wait_for_http_service(service, url, response?) do
    case Shared.wait_for_http(url, response?) do
      :ok -> Mix.shell().info("#{service} is ready")
      {:error, :timeout} -> Mix.raise("#{service} did not pass its health check after 30 seconds")
    end
  end

  defp phoenix_response?(status), do: status in 100..599
  defp success_response?(status), do: status in 200..299

  defp run_task(task) do
    Mix.Task.reenable(task)
    Mix.Task.run(task)
  end

  defp run_status do
    run_task("dev.status")
  end

  defp port_key(:s3), do: "S3_PORT"
  defp port_key(:gotenberg), do: "GOTENBERG_PORT"
end
