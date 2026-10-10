defmodule Mix.Tasks.Translations.Fetch do
  @shortdoc "Fetches the Polish catalog for a pinned Git revision"
  @moduledoc "Fetches the Polish Accent catalog for an explicit revision, optionally falling back to a pinned main revision on HTTP 404. Never creates snapshots."

  use Mix.Task

  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(args) do
    {options, remaining} =
      OptionParser.parse!(args, strict: [version: :string, fallback_version: :string])

    ensure_no_arguments!(remaining)

    version = Keyword.get_lazy(options, :version, &git_head!/0)

    fallback_arguments =
      case Keyword.fetch(options, :fallback_version) do
        {:ok, fallback} -> ["--fallback-version", fallback]
        :error -> []
      end

    arguments = ["scripts/accent.exs", "export", "--version", version] ++ fallback_arguments

    case System.cmd("elixir", arguments, stderr_to_stdout: true) do
      {_output, 0} ->
        :ok

      {output, status} ->
        Mix.raise("Accent catalog export failed (status #{status}): #{String.trim(output)}")
    end
  end

  defp ensure_no_arguments!([]), do: :ok

  defp ensure_no_arguments!(arguments), do: Mix.raise("unknown arguments: #{Enum.join(arguments, " ")}")

  defp git_head! do
    case System.cmd("git", ["rev-parse", "HEAD"], stderr_to_stdout: true) do
      {version, 0} ->
        String.trim(version)

      {output, status} ->
        Mix.raise("could not determine Git HEAD (status #{status}): #{String.trim(output)}")
    end
  end
end
