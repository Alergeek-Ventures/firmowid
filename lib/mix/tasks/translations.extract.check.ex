defmodule Mix.Tasks.Translations.Extract.Check do
  @shortdoc "Verifies Gettext extraction, reusing unchanged local successes"
  @moduledoc """
  Checks POT freshness with native `gettext.extract --check-up-to-date` on a
  cache miss. Only successful verification is remembered under the current
  `Mix.Project.build_path/0`; no catalogs or Git index entries are written.

      mix translations.extract.check
      mix translations.extract.check --force

  `--force` bypasses reuse. The native `mix gettext.extract --check-up-to-date`
  remains available for unconditional verification, and `mix gettext.extract`
  remains the command for updating source POT files. Catalog validation is
  separate and always runs in `mix translations.check`.
  """

  use Mix.Task

  alias Firmowid.Translations.ExtractionCache

  @impl Mix.Task
  @doc "Verifies extraction with an environment-specific successful-check cache."
  @spec run([String.t()]) :: :ok
  def run(args) do
    {options, remaining} = OptionParser.parse!(args, strict: [force: :boolean])
    if remaining != [], do: Mix.raise("Unexpected arguments: #{Enum.join(remaining, " ")}")

    # Match native extraction: compile-time configuration, not runtime secrets/services.
    Mix.Task.run("compile")
    {:ok, _applications} = Application.ensure_all_started(:gettext)

    options =
      options ++
        [root: File.cwd!(), build_path: Mix.Project.build_path(), context: &compiler_context/0]

    case ExtractionCache.run(options, &check_extraction!/0) do
      :cached -> Mix.shell().info("Gettext extraction verification unchanged (cached success).")
      :checked -> :ok
    end

    :ok
  end

  defp compiler_context do
    # Environment-dependent macros/configuration can affect extraction. Hash the
    # complete environment in memory; do not log or persist individual values.
    environment = System.get_env() |> Enum.sort() |> :erlang.term_to_binary()
    environment_hash = :crypto.hash(:sha256, environment)

    # This is tooling, not application behavior: cache entries belong to Mix's
    # selected environment and target, including effective compiler settings.
    # credo:disable-for-next-line Credo.Check.Warning.MixEnv
    mix_environment = Mix.env()

    {
      System.version(),
      :erlang.system_info(:system_version),
      System.find_executable("mix"),
      mix_environment,
      Mix.target(),
      Mix.Project.config(),
      Code.compiler_options(),
      :firmowid |> Application.get_all_env() |> Enum.sort(),
      :gettext |> Application.get_all_env() |> Enum.sort(),
      environment_hash
    }
  end

  defp check_extraction! do
    Mix.Task.reenable("gettext.extract")
    Mix.Task.run("gettext.extract", ["--check-up-to-date"])
    :ok
  end
end
