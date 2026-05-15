defmodule FirmowidWeb.Organization.Utilities.Navigation do
  @moduledoc """
  Central navigation contract for organization onboarding routes.
  """

  use FirmowidWeb, :verified_routes

  @doc """
  Returns the canonical onboarding path.
  """
  @spec onboarding_path() :: String.t()
  def onboarding_path, do: ~p"/organizacja"
end
