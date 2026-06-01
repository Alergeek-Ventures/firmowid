defmodule Firmowid.Config.LocalEnv do
  @moduledoc """
  Loads local development and test environment variables before runtime config reads them.
  """

  require Logger

  @doc """
  Loads Infisical secrets and `.env.worktree` into the process environment.
  """
  @spec load!() :: :ok
  def load! do
    if skip_infisical?() do
      Logger.info("Skipping Infisical local env load")
    else
      Logger.info("Loading local env from Infisical")
      load_infisical_env()
      Logger.info("Loaded local env from Infisical")
    end

    if File.exists?(".env.worktree") do
      Logger.info("Loading local env from .env.worktree")
      load_dotenv_file(".env.worktree")
      Logger.info("Loaded local env from .env.worktree")
    else
      Logger.info("No .env.worktree file found")
    end

    :ok
  end

  defp skip_infisical? do
    truthy?(System.get_env("CI")) or truthy?(System.get_env("AV_SKIP_INFISICAL"))
  end

  defp truthy?(value), do: value in ["1", "true"]

  defp blank_or_comment?(line), do: line == "" or String.starts_with?(line, "#")

  defp valid_env_key?(key), do: key =~ ~r/^[A-Za-z_][A-Za-z0-9_]*$/

  defp parse_dotenv_value(value) do
    value = String.trim(value)

    cond do
      String.starts_with?(value, "\"") and String.ends_with?(value, "\"") ->
        value
        |> String.trim_leading("\"")
        |> String.trim_trailing("\"")
        |> String.replace(~S(\"), ~S("))
        |> String.replace(~S(\n), "\n")

      String.starts_with?(value, "'") and String.ends_with?(value, "'") ->
        value
        |> String.trim_leading("'")
        |> String.trim_trailing("'")

      true ->
        value
        |> String.split(~r/\s+#/, parts: 2)
        |> List.first()
        |> String.trim()
    end
  end

  defp parse_dotenv_line(raw_line) do
    line = String.trim(raw_line)

    with false <- blank_or_comment?(line),
         [key, raw_value] <-
           line |> String.replace_prefix("export ", "") |> String.split("=", parts: 2),
         key = String.trim(key),
         true <- valid_env_key?(key) do
      {key, parse_dotenv_value(raw_value)}
    else
      _ -> nil
    end
  end

  defp parse_dotenv(contents) do
    contents
    |> String.split(~r/\R/)
    |> Enum.reduce(%{}, fn raw_line, acc ->
      case parse_dotenv_line(raw_line) do
        {key, value} -> Map.put(acc, key, value)
        nil -> acc
      end
    end)
  end

  # sobelow_skip ["CI.System"]
  # The executable path is resolved by System.find_executable/1 for the fixed
  # Infisical command, and all arguments are static strings, not user input.
  defp load_infisical_env do
    infisical =
      System.find_executable("infisical") ||
        raise """
        Infisical CLI is required for local dev/test configuration.

        Install it, then authenticate once with:
        infisical login --domain="https://infisical.alergeek.me"

        To work offline temporarily, run Mix commands with AV_SKIP_INFISICAL=1.
        """

    case System.cmd(
           infisical,
           [
             "export",
             "--env=dev",
             "--path=/app",
             "--format=dotenv",
             "--domain=https://infisical.alergeek.me",
             "--silent"
           ],
           stderr_to_stdout: true
         ) do
      {dotenv, 0} ->
        dotenv |> parse_dotenv() |> System.put_env()

      {_output, _status} ->
        raise """
        Infisical export failed for local dev/test configuration.

        Make sure you are logged in and this repository is initialized:
        infisical login --domain="https://infisical.alergeek.me"
        infisical init --domain="https://infisical.alergeek.me"

        To work offline temporarily, run Mix commands with AV_SKIP_INFISICAL=1.
        """
    end
  end

  defp load_dotenv_file(path) do
    if Code.ensure_loaded?(Dotenv) do
      apply(Dotenv, :load!, [path])
    else
      Logger.warning("Skipping .env.worktree load because Dotenv is not available")
    end
  end
end
