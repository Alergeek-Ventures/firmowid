defmodule Mix.Tasks.Translations.Check do
  @shortdoc "Validates Polish catalogs against POT sources"
  @moduledoc """
  Always checks technical PO validity against POT sources. Editorial review is
  managed in Accent. `--check-extraction` also runs `translations.extract.check`,
  which reuses only unchanged successful local extraction verification.
  """
  use Mix.Task

  alias Firmowid.Translations

  @impl Mix.Task
  @doc "Validates catalogs unconditionally, optionally verifying source extraction first."
  @spec run([String.t()]) :: :ok
  def run(args) do
    if "--check-extraction" in args, do: check_extraction!()

    Enum.each(Translations.domains(), &check_domain!/1)
    :ok
  end

  defp check_domain!(domain) do
    pot_path = Path.join("priv/gettext", domain <> ".pot")
    po_path = Path.join(["priv/gettext", "pl", "LC_MESSAGES", domain <> ".po"])
    require_file!(pot_path, "missing expected POT")
    require_file!(po_path, "missing expected Polish PO")

    pot = Expo.PO.parse_file!(pot_path)
    po = Expo.PO.parse_file!(po_path)

    case Translations.validate_catalog(pot, po, domain) do
      :ok -> :ok
      {:error, message} ->
        Mix.raise("""
        #{message}
        PO: #{po_path}
        Accent snapshot: #{catalog_version(po)}
        Refresh a stale pinned catalog with mix translations.fetch --version FULL_SHA --fallback-version MAIN_FULL_SHA.
        """)
    end
  end

  defp catalog_version(%Expo.Messages{top_comments: comments}) do
    case Regex.run(~r/Accent version: ([[:xdigit:]]{40})/, IO.iodata_to_binary(comments)) do
      [_, version] -> version
      nil -> "unmarked"
    end
  end

  defp require_file!(path, prefix) do
    if !File.exists?(path), do: Mix.raise("#{prefix}: #{path}")
  end

  defp check_extraction! do
    Mix.Task.reenable("translations.extract.check")
    Mix.Task.run("translations.extract.check")
  end
end
