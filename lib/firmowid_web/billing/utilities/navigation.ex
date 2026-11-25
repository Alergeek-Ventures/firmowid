defmodule FirmowidWeb.Billing.Utilities.Navigation do
  @moduledoc """
  Central navigation contract for billing routes.
  """
  use FirmowidWeb, :verified_routes

  alias FirmowidWeb.Core.Endpoint
  alias FirmowidWeb.Settings.Utilities.Navigation, as: SettingsNavigation

  @doc "Returns the page where admins choose between a higher plan and what stays within the current one."
  @spec plan_limit_path() :: String.t()
  def plan_limit_path, do: ~p"/limit-planu"

  @doc """
  Returns the absolute URLs Stripe Checkout sends the buyer back to: after a completed checkout
  Stripe sends the buyer to the checkout return with the session's id; after one left without
  completing it, back to `cancel_path`, the page the purchase started on.
  """
  @spec checkout_return_urls(String.t()) :: %{success_url: String.t(), cancel_url: String.t()}
  def checkout_return_urls(cancel_path) do
    %{
      # Stripe replaces the placeholder itself, so it must not be URL-encoded.
      success_url: Endpoint.url() <> ~p"/abonament/powrot" <> "?sesja={CHECKOUT_SESSION_ID}",
      cancel_url: Endpoint.url() <> cancel_path
    }
  end

  @doc "Returns the absolute URL Stripe's customer portal sends the admin back to: the subscription settings."
  @spec portal_return_url() :: String.t()
  def portal_return_url, do: Endpoint.url() <> SettingsNavigation.canonical_path(:subscription)
end
