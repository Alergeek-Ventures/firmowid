defmodule Mix.Tasks.Dev.Up do
  @shortdoc "Sets up worktree dev environment (env, services, db, caddy)"

  @moduledoc """
  Sets up a complete worktree development environment.

  1. Verifies .env exists (copied by `wt step copy-ignored`)
  2. Generates .env.local with port configuration
  3. Starts Podman Compose services (Postgres, Localstack, Chromium)
  4. Runs mix setup (ecto.create, ecto.migrate, assets)
  5. Registers Caddy route for `{branch}.firmowid.localhost`
  6. Starts Phoenix server in background

  ## Usage

      mix dev.up --branch BRANCH --port PORT --db-port DB_PORT --s3-port S3_PORT --chrome-port CHROME_PORT --debugger-port DEBUGGER_PORT

  ## Prerequisites

  - .env file must exist (automatically copied by worktrunk via .worktreeinclude)
  - Caddy must be running with admin API on localhost/caddy
  - Podman must be available
  """

  use Mix.Task

  @switches [
    branch: :string,
    port: :integer,
    db_port: :integer,
    s3_port: :integer,
    chrome_port: :integer,
    debugger_port: :integer
  ]

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: @switches)

    branch = Keyword.fetch!(opts, :branch)
    port = Keyword.fetch!(opts, :port)
    db_port = Keyword.fetch!(opts, :db_port)
    s3_port = Keyword.fetch!(opts, :s3_port)
    chrome_port = Keyword.fetch!(opts, :chrome_port)
    debugger_port = Keyword.fetch!(opts, :debugger_port)

    # Start applications needed for HTTP requests
    Application.ensure_all_started(:req)

    # Step 1: Verify .env exists (should be copied by `wt step copy-ignored`)
    verify_env_exists()

    # Step 2: Generate .env.local
    generate_env_local(branch, port, db_port, s3_port, chrome_port, debugger_port)

    # Step 3: Start Podman Compose services
    start_services(branch, port, db_port, s3_port, chrome_port)

    # Step 4: Run mix setup
    run_setup()

    # Step 5: Register Caddy route
    register_caddy_route(branch, port)

    # Step 6: Start Phoenix server in background
    start_phoenix_server()

    Mix.shell().info("")
    Mix.shell().info("Environment ready:")
    Mix.shell().info("  Phoenix:   https://#{branch}.firmowid.localhost (or localhost:#{port})")
    Mix.shell().info("  Tidewave:  https://localhost:#{port}/tidewave/mcp")
    Mix.shell().info("  Postgres:  localhost:#{db_port}")
    Mix.shell().info("  S3:        localhost:#{s3_port}")
    Mix.shell().info("  Chromium:  localhost:#{chrome_port}")
    Mix.shell().info("  Debugger:  localhost:#{debugger_port}")
    Mix.shell().info("")
    Mix.shell().info("Logs: tail -f tmp/phoenix.log")
    Mix.shell().info("Stop: mix dev.down")
  end

  defp verify_env_exists do
    if File.exists?(".env") do
      Mix.shell().info(".env found (copied by worktrunk)")
    else
      Mix.raise("""
      .env file not found!

      This file should be copied automatically by `wt step copy-ignored` during worktree creation.
      If you're setting up manually, copy .env from the main worktree first.
      """)
    end
  end

  defp generate_env_local(branch, port, db_port, s3_port, chrome_port, debugger_port) do
    Mix.shell().info("Generating .env.local...")

    content = """
    PORT=#{port}
    DB_PORT=#{db_port}
    S3_PORT=#{s3_port}
    CHROME_PORT=#{chrome_port}
    DEBUGGER_PORT=#{debugger_port}
    BRANCH=#{branch}
    DATABASE_URL=postgresql://postgres:postgres@localhost:#{db_port}/firmowid

    # AWS credentials for localstack (required by ex_aws)
    AWS_ACCESS_KEY_ID=test
    AWS_SECRET_ACCESS_KEY=test
    """

    File.write!(".env.local", content)
    Mix.shell().info("Generated .env.local for branch '#{branch}'")

    # Generate .opencode.port for opencode MCP config
    File.write!(".opencode.port", to_string(port))
    Mix.shell().info("Generated .opencode.port for opencode MCP")
  end

  defp start_services(branch, port, db_port, s3_port, chrome_port) do
    Mix.shell().info("Starting Podman Compose services...")

    compose_env = [
      {"COMPOSE_PROJECT_NAME", "firmowid-#{branch}"},
      {"PORT", to_string(port)},
      {"DB_PORT", to_string(db_port)},
      {"S3_PORT", to_string(s3_port)},
      {"CHROME_PORT", to_string(chrome_port)}
    ]

    compose_result =
      podman(["compose", "-f", "local/compose.worktree.yml", "up", "-d"], compose_env)

    case compose_result do
      {output, 0} ->
        Mix.shell().info(output)
        Mix.shell().info("Podman Compose services started")

      {output, code} ->
        Mix.shell().error("Podman Compose failed (exit #{code}):")
        Mix.shell().error(output)
        exit({:shutdown, code})
    end

    # Wait for postgres to be ready
    Mix.shell().info("Waiting for Postgres to be ready...")
    wait_for_postgres(db_port)
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

  defp wait_for_postgres(port, attempts \\ 30) do
    case System.cmd("pg_isready", ["-h", "localhost", "-p", to_string(port)], stderr_to_stdout: true) do
      {_, 0} ->
        Mix.shell().info("Postgres is ready")

      {_, _} when attempts > 0 ->
        Process.sleep(1000)
        wait_for_postgres(port, attempts - 1)

      {output, _} ->
        Mix.raise("Postgres not ready after 30 seconds: #{output}")
    end
  end

  defp run_setup do
    Mix.shell().info("Running mix setup...")

    # Shell out to avoid Hex version conflicts when running in a fresh worktree
    case System.cmd("mix", ["setup"], stderr_to_stdout: true, into: IO.stream(:stdio, :line)) do
      {_, 0} ->
        Mix.shell().info("Setup complete")

      {_, code} ->
        Mix.raise("mix setup failed with exit code #{code}")
    end
  end

  defp start_phoenix_server do
    Mix.shell().info("Starting Phoenix server in background...")

    # Ensure tmp directory exists
    File.mkdir_p!("tmp")

    # Start Phoenix server in background, redirect output to log file
    pid_file = "tmp/phoenix.pid"
    log_file = "tmp/phoenix.log"

    # Use nohup + shell to properly background the process
    spawn(fn ->
      System.cmd(
        "sh",
        ["-c", "nohup mix phx.server > #{log_file} 2>&1 & echo $! > #{pid_file}"],
        stderr_to_stdout: true
      )
    end)

    # Give it a moment to start and write the PID
    Process.sleep(1000)

    case File.read(pid_file) do
      {:ok, pid} ->
        Mix.shell().info("Phoenix server started (PID: #{String.trim(pid)})")

      {:error, _} ->
        Mix.shell().info("Phoenix server starting... (check tmp/phoenix.log)")
    end
  end

  defp register_caddy_route(branch, port) do
    Mix.shell().info("Registering Caddy route for #{branch}.firmowid.localhost...")

    route_config = %{
      "id" => branch,
      "hostname" => "#{branch}.firmowid.localhost",
      "upstream" => "127.0.0.1:#{port}"
    }

    case Req.post("http://localhost:11190/api/routes", json: route_config) do
      {:ok, %{status: status}} when status in 200..299 ->
        Mix.shell().info("Caddy route registered: https://#{branch}.firmowid.localhost -> localhost:#{port}")

      {:ok, %{status: status, body: body}} ->
        Mix.shell().error("Warning: Failed to register Caddy route (status #{status})")
        Mix.shell().error(inspect(body))

      {:error, reason} ->
        Mix.shell().error("Warning: Failed to register Caddy route (is development-caddy running?)")
        Mix.shell().error(inspect(reason))
    end
  end
end
