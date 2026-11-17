defmodule FirmowidWeb.Billing.Utilities.Navigation do
  @moduledoc """
  Central navigation contract for billing routes.
  """
  use FirmowidWeb, :verified_routes

  @doc "Returns the page where admins choose between a higher plan and what stays within the current one."
  @spec plan_limit_path() :: String.t()
  def plan_limit_path, do: ~p"/limit-planu"

  @doc "Returns the page Tpay sends the buyer back to after the card page."
  @spec card_return_path() :: String.t()
  def card_return_path, do: ~p"/abonament/karta"

  @doc "Returns the link that opens Tpay's card page for a new card of the active subscription."
  @spec card_change_path() :: String.t()
  def card_change_path, do: ~p"/abonament/karta?#{[zmiana: "tak"]}"
end
