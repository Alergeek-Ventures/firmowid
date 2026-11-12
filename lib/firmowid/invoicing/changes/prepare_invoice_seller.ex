defmodule Firmowid.Invoicing.Changes.PrepareInvoiceSeller do
  @moduledoc """
  Snapshots the scoped organization's seller details while preparing a new invoice or saved draft.

  An unnumbered document is issued on the day it is prepared, so its issue date is always today in Poland.
  A saved draft's date is only the day it was saved and must not backdate its later issuance.
  A transfer without a seller account uses the organization's default bank account for the currency,
  as the invoice creator does. A new domestic invoice that does not choose cash accounting starts with
  the organization's last choice.
  """
  use Ash.Resource.Change
  use Gettext, backend: Firmowid.Gettext

  alias Firmowid.Core
  alias Firmowid.Finances
  alias Firmowid.LocalDate
  alias Firmowid.Scope

  @doc "Copies the current organization's details into a new or revised draft."
  @spec change(Ash.Changeset.t(), keyword(), Ash.Resource.Change.Context.t()) :: Ash.Changeset.t()
  @impl true
  def change(changeset, _opts, context) do
    case Core.get_organization(context.tenant, Ash.Context.to_opts(context)) do
      {:ok, nil} ->
        Ash.Changeset.add_error(changeset,
          field: :input,
          message: gettext_noop("The current organization was not found.")
        )

      {:ok, organization} ->
        changeset
        |> Ash.Changeset.force_change_attributes(%{
          seller_display_name: organization.name,
          seller_address: organization.address,
          seller_nip: organization.nip,
          seller_name: nil,
          seller_surname: nil
        })
        |> Ash.Changeset.force_change_attribute(:issue_date, LocalDate.today())
        |> new_invoice_defaults()
        |> default_cash_accounting(organization)
        |> default_if_nil(:vat_exemption_type, organization.vat_exemption_type)
        |> default_if_nil(:vat_exemption_basis, organization.vat_exemption_basis)
        |> default_seller_account(context)

      {:error, error} ->
        Ash.Changeset.add_error(changeset, error)
    end
  end

  defp new_invoice_defaults(%{action_type: :create} = changeset) do
    changeset
    |> Ash.Changeset.change_new_attribute(:currency, "PLN")
    |> Ash.Changeset.change_new_attribute(:buyer_country, "PL")
  end

  defp new_invoice_defaults(changeset), do: changeset

  # Cash accounting is a way of settling VAT on domestic sales: an organization outside VAT and
  # a foreign invoice never use it. On a new invoice the attribute's own default (false) is not
  # a choice, so it gives way to the organization's last one.
  defp default_cash_accounting(changeset, organization) do
    cond do
      not organization.is_vat_payer or
          Ash.Changeset.get_attribute(changeset, :invoice_type) != :poland ->
        Ash.Changeset.force_change_attribute(changeset, :is_cash_account, false)

      :is_cash_account in changeset.defaults ->
        Ash.Changeset.force_change_attribute(
          changeset,
          :is_cash_account,
          organization.is_cash_account
        )

      true ->
        changeset
    end
  end

  defp default_seller_account(changeset, context) do
    currency = Ash.Changeset.get_attribute(changeset, :currency)

    if is_binary(currency) and
         Ash.Changeset.get_attribute(changeset, :payment_method) == :transfer and
         Ash.Changeset.get_attribute(changeset, :seller_account_number) in [nil, ""] do
      currency
      |> Finances.get_default_bank_account_for_currency(%Scope{
        actor: context.actor,
        tenant: context.tenant
      })
      |> case do
        {:ok, nil} ->
          changeset

        {:ok, account} ->
          Ash.Changeset.force_change_attribute(changeset, :seller_account_number, account.iban)

        {:error, error} ->
          Ash.Changeset.add_error(changeset, error)
      end
    else
      changeset
    end
  end

  defp default_if_nil(changeset, field, default) do
    if is_nil(Ash.Changeset.get_attribute(changeset, field)),
      do: Ash.Changeset.force_change_attribute(changeset, field, default),
      else: changeset
  end
end
