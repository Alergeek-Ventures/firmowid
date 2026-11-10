defmodule FirmowidWeb.Organization.Utilities.Navigation do
  @moduledoc """
  Central navigation contract for organization onboarding routes.
  """
  use FirmowidWeb, :verified_routes

  @type onboarding_step :: :firma | :branza | :dolacz
  @type first_step :: :ksef | :bank | :plan | :gotowe

  @doc """
  Returns the canonical onboarding path, at its first step or at `step`.
  """
  @spec onboarding_path(onboarding_step() | nil) :: String.t()
  def onboarding_path(step \\ nil)
  def onboarding_path(nil), do: ~p"/organizacja"
  def onboarding_path(step), do: ~p"/organizacja?#{[krok: step]}"

  @doc "Returns the path of the setup steps that follow creating an organization."
  @spec first_steps_path(first_step() | nil) :: String.t()
  def first_steps_path(step \\ nil)
  def first_steps_path(nil), do: ~p"/pierwsze-kroki"
  def first_steps_path(step), do: ~p"/pierwsze-kroki?#{[krok: step]}"

  @doc "The `cel` value of the organization switch that continues with the first steps."
  @spec first_steps_target() :: String.t()
  def first_steps_target, do: "pierwsze-kroki"
end
