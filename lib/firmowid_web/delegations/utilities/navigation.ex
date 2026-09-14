defmodule FirmowidWeb.Delegations.Utilities.Navigation do
  @moduledoc "Canonical user-facing navigation paths for delegations."

  @doc "Returns the path for submitting a delegation."
  @spec new_path() :: String.t()
  def new_path, do: "/delegacje/dodaj"

  @doc "Returns the path for viewing a delegation."
  @spec show_path(String.t()) :: String.t()
  def show_path(reference), do: "/delegacje/#{reference}"
end
