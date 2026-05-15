defmodule FirmowidWeb.Infrastructure.Utilities.Navigation do
  @moduledoc """
  Shared allowlist plumbing for cross-feature `powrot_do` paths.
  """

  alias FirmowidWeb.Management.Utilities.Navigation, as: ManagementNavigation

  @doc """
  Resolves a raw cross-feature return path into its canonical allowlisted path.
  """
  @spec allowlisted_return_path(String.t() | nil) :: String.t() | nil
  def allowlisted_return_path(raw_return_to) do
    ManagementNavigation.counterparty_show_return_path(raw_return_to) ||
      ManagementNavigation.counterparties_return_path(raw_return_to)
  end
end
