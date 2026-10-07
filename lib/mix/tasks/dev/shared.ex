defmodule Mix.Tasks.Dev.Shared do
  @moduledoc """
  Shared helper functions for the development Mix tasks.
  """

  @doc """
  Returns the default configuration for the worktree development environment.
  """
  @spec defaults() :: %{String.t() => String.t()}
  def defaults do
    %{
      "PORT" => "4000",
      "DB_PORT" => "5433",
      "S3_PORT" => "4566",
      "GOTENBERG_PORT" => "3000",
      "DEBUGGER_PORT" => "9229",
      "BRANCH" => "main"
    }
  end

  @doc """
  Prints the endpoint summary for the configured development environment.
  """
  @spec print_environment(%{String.t() => String.t()}, String.t()) :: :ok
  def print_environment(env, caddy_port) do
    branch = sanitize_branch(env["BRANCH"])
    port = env["PORT"]
    caddy_suffix = if caddy_port in ["80", "443"], do: "", else: ":#{caddy_port}"

    Mix.shell().info("")
    Mix.shell().info("Environment ready:")

    Mix.shell().info("  Phoenix:   http://#{branch}.firmowid.localhost#{caddy_suffix} (or http://localhost:#{port})")

    Mix.shell().info("  Tidewave:  http://localhost:#{port}/tidewave/mcp")
    Mix.shell().info("  Postgres:  localhost:#{env["DB_PORT"]}")
    Mix.shell().info("  S3:        localhost:#{env["S3_PORT"]}")
    Mix.shell().info("  Gotenberg:  localhost:#{env["GOTENBERG_PORT"]}")
    Mix.shell().info("  Debugger:  localhost:#{env["DEBUGGER_PORT"]}")
    Mix.shell().info("")
    Mix.shell().info("Logs: tail -f tmp/phoenix.log")
    Mix.shell().info("Stop: mix dev.down")
  end

  @doc """
  Sanitizes branch names for hostname and compose project naming.
  """
  @spec sanitize_branch(String.t()) :: String.t()
  def sanitize_branch(branch) do
    branch
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9-]/, "-")
    |> String.replace(~r/-+/, "-")
    |> String.trim("-")
    |> case do
      "" -> "main"
      sanitized -> sanitized
    end
  end

  @doc """
  Parses dotenv-style content into a map.
  """
  @spec parse_env(String.t()) :: map()
  def parse_env(content) do
    content
    |> String.split("\n", trim: true)
    |> Enum.reject(fn line -> String.starts_with?(line, "#") or String.trim(line) == "" end)
    |> Map.new(fn line ->
      [key, value] = String.split(line, "=", parts: 2)
      {String.trim(key), String.trim(value)}
    end)
  end

  @doc """
  Runs podman/docker compose, preferring distrobox-host-exec when available.
  """
  @spec podman([String.t()], [{String.t(), String.t()}]) :: {String.t(), non_neg_integer()}
  def podman(args, env) do
    env_prefix = Enum.map(env, fn {k, v} -> "#{k}=#{v}" end)

    cond do
      System.find_executable("distrobox-host-exec") ->
        System.cmd("distrobox-host-exec", ["env" | env_prefix] ++ ["podman" | args], stderr_to_stdout: true)

      System.find_executable("podman") ->
        System.cmd("podman", args, env: env, stderr_to_stdout: true)

      System.find_executable("docker") ->
        System.cmd("docker", args, env: env, stderr_to_stdout: true)
    end
  end

  @doc "Loads worktree configuration, falling back to standard defaults."
  @spec load_env() :: %{String.t() => String.t()}
  def load_env do
    case File.read(".env.worktree") do
      {:ok, content} ->
        Mix.shell().info("Loading configuration from .env.worktree")
        Map.merge(defaults(), parse_env(content))

      {:error, :enoent} ->
        Mix.shell().info("No .env.worktree found, using defaults (main branch setup)")
        defaults()
    end
  end

  @doc "Builds the compose environment for a configured worktree."
  @spec compose_env(%{String.t() => String.t()}) :: [{String.t(), String.t()}]
  def compose_env(env) do
    ["PORT", "DB_PORT", "S3_PORT", "GOTENBERG_PORT"]
    |> Enum.map(&{&1, Map.fetch!(env, &1)})
    |> then(&[{"COMPOSE_PROJECT_NAME", "firmowid-#{Map.fetch!(env, "BRANCH")}"} | &1])
  end

  @doc """
  Waits until a TCP listener has closed.

  This is used during a Phoenix restart so that the new process cannot race the
  old listener (and accidentally make a readiness check pass for the old app).
  """
  @spec wait_for_port_closed(String.t(), non_neg_integer()) :: :ok | {:error, :timeout}
  def wait_for_port_closed(port, attempts \\ 60)

  def wait_for_port_closed(_port, 0), do: {:error, :timeout}

  def wait_for_port_closed(port, attempts) do
    case :gen_tcp.connect(~c"localhost", String.to_integer(port), [], 300) do
      {:error, _reason} ->
        :ok

      {:ok, socket} ->
        :gen_tcp.close(socket)
        Process.sleep(500)
        wait_for_port_closed(port, attempts - 1)
    end
  end

  @doc """
  Waits for an HTTP endpoint to return a response accepted by `response?`.

  Requests deliberately disable Req retries: retries are handled by this
  bounded readiness loop, keeping failures quiet and the total wait predictable.
  """
  @spec wait_for_http(String.t(), (integer() -> boolean()), non_neg_integer()) ::
          :ok | {:error, :timeout}
  def wait_for_http(url, response?, attempts \\ 60)

  def wait_for_http(_url, _response?, 0), do: {:error, :timeout}

  def wait_for_http(url, response?, attempts) do
    case Req.get(url,
           retry: false,
           connect_options: [timeout: 300],
           receive_timeout: 300
         ) do
      {:ok, %{status: status}} when is_integer(status) ->
        if response?.(status) do
          :ok
        else
          retry_http(url, response?, attempts)
        end

      {:error, _reason} ->
        retry_http(url, response?, attempts)
    end
  rescue
    _error -> retry_http(url, response?, attempts)
  end

  defp retry_http(url, response?, attempts) do
    Process.sleep(500)
    wait_for_http(url, response?, attempts - 1)
  end
end
