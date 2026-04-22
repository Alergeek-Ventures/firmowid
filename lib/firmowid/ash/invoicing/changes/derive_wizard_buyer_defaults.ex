defmodule Firmowid.Ash.Invoicing.Changes.DeriveWizardBuyerDefaults do
  @moduledoc """
  Derives wizard invoice defaults from buyer context.

  This keeps buyer-country / identifier rules in the domain action instead of
  LiveView orchestration.
  """
  use Ash.Resource.Change

  alias Firmowid.Ash.Finances
  alias Firmowid.Ash.Invoicing.CountryCodes
  alias Firmowid.Ash.Scope

  @impl true
  def change(changeset, _opts, context) do
    buyer_country = Ash.Changeset.get_attribute(changeset, :buyer_country)
    buyer_pesel = Ash.Changeset.get_attribute(changeset, :buyer_pesel)
    buyer_type = Ash.Changeset.get_attribute(changeset, :buyer_type)

    invoice_type = invoice_type_for_country(buyer_country)
    currency = currency_for_country(buyer_country)

    is_reverse_charge =
      buyer_country
      |> CountryCodes.tax_id_type(buyer_pesel, buyer_type)
      |> reverse_charge_for_id_type?()

    default_account_number =
      find_default_bank_account_number(context.actor, changeset.tenant, currency)

    changeset
    |> Ash.Changeset.force_change_attribute(:invoice_type, invoice_type)
    |> Ash.Changeset.force_change_attribute(:currency, currency)
    |> Ash.Changeset.force_change_attribute(:is_reverse_charge, is_reverse_charge)
    |> Ash.Changeset.force_change_attribute(:seller_account_number, default_account_number)
  end

  defp find_default_bank_account_number(actor, tenant, currency) do
    scope = %Scope{actor: actor, tenant: tenant}

    case Finances.get_default_bank_account_for_currency(currency, scope) do
      {:ok, nil} -> nil
      {:ok, account} -> account.iban
      {:error, _error} -> nil
    end
  end

  defp reverse_charge_for_id_type?(:eu_vat), do: true
  defp reverse_charge_for_id_type?(:other_id), do: true
  defp reverse_charge_for_id_type?(_), do: false

  defp currency_for_country("PL"), do: "PLN"
  defp currency_for_country(_), do: "EUR"

  defp invoice_type_for_country("PL"), do: :poland
  defp invoice_type_for_country(_), do: :foreign
end
