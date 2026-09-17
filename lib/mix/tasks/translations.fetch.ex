defmodule Mix.Tasks.Translations.Fetch do
  @shortdoc "Fetches the Polish catalog for a pinned Git revision"
  @moduledoc "Fetches the Polish Accent catalog for an explicit revision without creating snapshots or falling back to latest."

  use Mix.Task

  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(args) do
    {options, remaining} = OptionParser.parse!(args, strict: [version: :string])
    ensure_no_arguments!(remaining)

    version = Keyword.get_lazy(options, :version, &git_head!/0)

    case System.cmd("elixir", ["scripts/accent.exs", "export", "--version", version], stderr_to_stdout: true) do
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
