defmodule FirmowidWeb.Billing.Utilities.Navigation do
  @moduledoc """
  Central navigation contract for billing routes.
  """
  use FirmowidWeb, :verified_routes

  @doc "Returns the page where admins choose between a higher plan and what stays within the current one."
  @spec plan_limit_path() :: String.t()
  def plan_limit_path, do: ~p"/limit-planu"
end
