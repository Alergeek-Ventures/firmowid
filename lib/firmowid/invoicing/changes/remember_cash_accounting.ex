defmodule Firmowid.Invoicing.Changes.RememberCashAccounting do
  @moduledoc """
  Remembers an issued domestic invoice's cash accounting on the organization, so the next new
  invoice starts with it (see `PrepareInvoiceSeller`). A foreign invoice and an organization
  outside VAT never use it and leave the remembered choice alone.
  """
  use Ash.Resource.Change

  alias Firmowid.Core

  @doc "Updates the organization after the invoice is written, in the same transaction."
  @spec change(Ash.Changeset.t(), keyword(), Ash.Resource.Change.Context.t()) :: Ash.Changeset.t()
  @impl true
  def change(changeset, _opts, context) do
    opts = Ash.Context.to_opts(context)

    Ash.Changeset.after_action(changeset, fn _changeset, invoice ->
      remember(invoice, context.tenant, opts)
    end)
  end

  defp remember(%{invoice_type: :poland} = invoice, organization_id, opts) do
    with {:ok, organization} <- Core.get_organization(organization_id, opts),
         {:ok, _organization} <- update(organization, invoice.is_cash_account, opts) do
      {:ok, invoice}
    end
  end

  defp remember(invoice, _organization_id, _opts), do: {:ok, invoice}

  defp update(%{is_vat_payer: false} = organization, _cash_accounting?, _opts), do: {:ok, organization}

  defp update(%{is_cash_account: same} = organization, same, _opts), do: {:ok, organization}

  defp update(organization, cash_accounting?, opts),
    do: Core.remember_cash_accounting(organization, cash_accounting?, opts)
end
