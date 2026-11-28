defmodule Firmowid.Invoicing.StripeConnection.Changes.VerifyKey do
  @moduledoc """
  Checks the restricted Stripe key a company connects with and keeps it.

  The key must be restricted (`rk_live_`; outside production also `rk_test_`), so it can only do
  what the company allowed. Before the transaction one list request per permission tells
  whether Stripe knows the key and whether it has every permission the invoicing reads; the
  first one missing is named in the error, under the name Stripe's key editor shows.
  """
  use Ash.Resource.Change
  use Gettext, backend: Firmowid.Gettext

  alias Firmowid.Billing.StripeTerms

  # What the invoicing reads, as `{name in Stripe's key editor, a request that needs it}`.
  @permissions [
    {"Events", "/v1/events"},
    {"Payment Intents", "/v1/payment_intents"},
    {"Charges and Refunds", "/v1/charges"},
    {"Customers", "/v1/customers"},
    {"Invoices", "/v1/invoices"},
    {"Credit Notes", "/v1/credit_notes"},
    {"Checkout Sessions", "/v1/checkout/sessions"}
  ]

  @doc "The read permissions the restricted key needs, as Stripe's key editor names them."
  @spec permissions() :: [String.t()]
  def permissions, do: Enum.map(@permissions, &elem(&1, 0))

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_transaction(changeset, fn changeset ->
      key = changeset |> Ash.Changeset.get_argument(:api_key) |> String.trim()

      case verify(key) do
        :ok ->
          Ash.Changeset.force_change_attribute(changeset, :api_key, key)

        {:invalid, message, vars} ->
          Ash.Changeset.add_error(changeset, field: :api_key, message: message, vars: vars)

        {:error, error} ->
          Ash.Changeset.add_error(changeset, error)
      end
    end)
  end

  defp verify(key) do
    if String.starts_with?(key, prefixes()) do
      Enum.find_value(@permissions, :ok, fn {permission, path} -> check(key, permission, path) end)
    else
      {:invalid, gettext_noop("Paste a restricted key: it starts with rk_live_."), []}
    end
  end

  # A test key works like a live one, but only outside production.
  defp prefixes do
    if Application.get_env(:firmowid, :environment) == :prod,
      do: ["rk_live_"],
      else: ["rk_live_", "rk_test_"]
  end

  defp check(key, permission, path) do
    case StripeTerms.request(:get, path, %{limit: 1}, api_key: key) do
      {:ok, _list} ->
        nil

      {:error, %Stripe.Error{extra: %{http_status: 401}}} ->
        {:invalid, gettext_noop("Stripe does not know this key. Copy it again from Stripe."), []}

      {:error, %Stripe.Error{extra: %{http_status: 403}}} ->
        {:invalid, gettext_noop("The key lacks the permission %{permission}: Read. Add it in Stripe and try again."),
         permission: permission}

      {:error, error} ->
        {:error, error}
    end
  end
end
