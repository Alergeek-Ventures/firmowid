defmodule Mix.Tasks.Dev.Shared do
  @moduledoc """
  Shared helper functions for `mix dev.up` and `mix dev.down`.
  """

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
end
