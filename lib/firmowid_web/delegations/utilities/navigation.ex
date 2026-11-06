defmodule FirmowidWeb.Delegations.Utilities.Navigation do
  @moduledoc "Canonical user-facing navigation paths for delegations."

  @doc "Returns the path for submitting a delegation."
  @spec new_path() :: String.t()
  def new_path, do: "/delegacje/dodaj"

  @doc "Returns the path for correcting an unsigned delegation order."
  @spec edit_path(String.t()) :: String.t()
  def edit_path(reference), do: "/delegacje/#{reference}/edycja"

  @doc "Returns the path for viewing a delegation."
  @spec show_path(String.t()) :: String.t()
  def show_path(reference), do: "/delegacje/#{reference}"

  @doc "Returns the authenticated download path for a delegation settlement PDF."
  @spec settlement_download_path(String.t()) :: String.t()
  def settlement_download_path(reference), do: "/delegacje/#{reference}/rozliczenie/pobierz"
end
