defmodule Mix.Tasks.Dev.Down do
  @shortdoc "Stops worktree dev services and unregisters Caddy route"

  @moduledoc """
  Stops worktree development services.

  1. Reads `.env.local` for configuration
  2. Unregisters Caddy route
  3. Stops and removes Podman Compose services (including volumes)

  ## Usage

      mix dev.down

  ## Note

  This is typically called by worktrunk's `pre-remove` hook.
  """

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    # Start applications needed for HTTP requests
    Application.ensure_all_started(:req)

    env = load_env_local!()

    branch = Map.fetch!(env, "BRANCH")
    port = Map.fetch!(env, "PORT")
    db_port = Map.fetch!(env, "DB_PORT")
    s3_port = Map.fetch!(env, "S3_PORT")
    chrome_port = Map.fetch!(env, "CHROME_PORT")

    Mix.shell().info("Stopping services for branch '#{branch}'...")

    # Stop Phoenix server first
    stop_phoenix_server()

    # Unregister Caddy route
    unregister_caddy_route(branch)

    # Stop Podman Compose services
    stop_services(branch, port, db_port, s3_port, chrome_port)

    Mix.shell().info("Services stopped for branch '#{branch}'")
  end

  defp stop_phoenix_server do
    pid_file = "tmp/phoenix.pid"

    case File.read(pid_file) do
      {:ok, pid_str} ->
        pid = String.trim(pid_str)
        Mix.shell().info("Stopping Phoenix server (PID: #{pid})...")

        # Kill the process tree (Phoenix spawns child processes)
        System.cmd("pkill", ["-P", pid], stderr_to_stdout: true)
        System.cmd("kill", [pid], stderr_to_stdout: true)

        # Clean up PID file
        File.rm(pid_file)
        Mix.shell().info("Phoenix server stopped")

      {:error, :enoent} ->
        Mix.shell().info("No Phoenix PID file found (server may not be running)")
    end
  end

  defp unregister_caddy_route(branch) do
    Mix.shell().info("Unregistering Caddy route...")

    case Req.delete("https://localhost/caddy/id/#{branch}",
           connect_options: [transport_opts: [verify: :verify_none]]
         ) do
      {:ok, %{status: status}} when status in 200..299 ->
        Mix.shell().info("Caddy route unregistered")

      {:ok, _} ->
        Mix.shell().info("Warning: Caddy route not found")

      {:error, _} ->
        Mix.shell().info("Warning: Caddy not running")
    end
  end

  defp stop_services(branch, port, db_port, s3_port, chrome_port) do
    compose_env = [
      {"COMPOSE_PROJECT_NAME", "firmowid-#{branch}"},
      {"PORT", port},
      {"DB_PORT", db_port},
      {"S3_PORT", s3_port},
      {"CHROME_PORT", chrome_port}
    ]

    compose_result = podman(["compose", "-f", "local/compose.worktree.yml", "down", "-v"], compose_env)

    case compose_result do
      {output, 0} ->
        Mix.shell().info(output)
        Mix.shell().info("Podman Compose services stopped and volumes removed")

      {output, code} ->
        Mix.shell().error("Podman Compose failed (exit #{code}):")
        Mix.shell().error(output)
    end
  end

  # Run podman via distrobox-host-exec if available (for distrobox containers),
  # otherwise try podman directly.
  # Env vars are passed inline since distrobox-host-exec doesn't forward them.
  defp podman(args, env) do
    env_prefix = Enum.map(env, fn {k, v} -> "#{k}=#{v}" end)

    case System.find_executable("distrobox-host-exec") do
      nil ->
        System.cmd("podman", args, env: env, stderr_to_stdout: true)

      _path ->
        # Use env command to set variables on the host side
        System.cmd("distrobox-host-exec", ["env" | env_prefix] ++ ["podman" | args], stderr_to_stdout: true)
    end
  end

  defp load_env_local! do
    case File.read(".env.local") do
      {:ok, content} ->
        content
        |> String.split("\n", trim: true)
        |> Enum.reject(&String.starts_with?(&1, "#"))
        |> Map.new(fn line ->
          [key, value] = String.split(line, "=", parts: 2)
          {String.trim(key), String.trim(value)}
        end)

      {:error, :enoent} ->
        Mix.raise("Missing .env.local - cannot determine which services to stop")
    end
  end
end
