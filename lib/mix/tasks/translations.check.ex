defmodule Mix.Tasks.Translations.Check do
  @shortdoc "Validates Polish catalogs against POT sources"
  @moduledoc "Checks catalog extraction and technical PO validity. Editorial review is managed in Accent."
  use Mix.Task

  alias Firmowid.Translations

  @impl Mix.Task
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
      {:error, message} -> Mix.raise(message)
    end
  end

  defp require_file!(path, prefix) do
    if !File.exists?(path), do: Mix.raise("#{prefix}: #{path}")
  end

  defp check_extraction! do
    mix = System.find_executable("mix") || "mix"

    case System.cmd(mix, ["gettext.extract", "--check-up-to-date"], stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, _status} -> Mix.raise(output)
    end
  end
end
