defmodule Firmowid.Ash.Analysis.Actions.ListEntries do
  @moduledoc "Lists a month's analysis entries with their categories, as shown on the analysis dashboard."
  use Ash.Resource.Actions.Implementation

  alias Firmowid.Ash.Analysis
  alias Firmowid.Ash.Core.User
  alias Firmowid.Ash.Finances.Transaction
  alias Firmowid.Ash.Invoicing.CostInvoice
  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Ash.Scope
  alias FirmowidWeb.Infrastructure.Flags

  @impl true
  def run(input, _opts, %{actor: %User{organization_id: tenant} = actor, tenant: tenant}) when is_binary(tenant) do
    if Map.get(Flags.evaluate_for_user(actor), :analysis_dashboard, false) do
      month = Date.beginning_of_month(input.arguments.month)

      entries =
        Analysis.get_organization_entries(month, Date.end_of_month(month), %Scope{
          actor: actor,
          tenant: tenant
        })

      rows =
        (entries.sales_invoices ++ entries.cost_invoices ++ entries.transactions)
        |> Enum.map(&entry/1)
        |> Enum.sort_by(& &1.date, Date)

      {:ok, %{month: month, entries: rows}}
    else
      {:error, :analysis_unavailable}
    end
  end

  # This must also reject mismatched tenants for admins, whose policy bypass is global.
  def run(_input, _opts, _context), do: {:error, Ash.Error.Forbidden.exception([])}

  defp entry(%SalesInvoice{} = invoice) do
    row(invoice, :sales_invoice, :income, %{
      counterparty: invoice.buyer_display_name_label,
      description: Enum.map_join(invoice.sales_invoice_items, ", ", & &1.name),
      date: invoice.sale_date || invoice.issue_date,
      amount: invoice.effective_amount
    })
  end

  defp entry(%CostInvoice{} = invoice) do
    row(invoice, :cost_invoice, :expenses, %{
      counterparty: invoice.effective_seller_display_name || invoice.seller_display_name || invoice.seller,
      description: invoice.description,
      date: invoice.effective_sale_date || invoice.sale_date,
      amount: invoice.effective_amount
    })
  end

  defp entry(%Transaction{} = transaction) do
    income? = Money.positive?(transaction.amount)

    row(transaction, :transaction, if(income?, do: :income, else: :expenses), %{
      counterparty: if(income?, do: transaction.debtor_name, else: transaction.creditor_name),
      description: transaction.remittance_information_unstructured,
      date: transaction.booking_date,
      amount: transaction.amount
    })
  end

  defp row(entity, entity_type, section, %{amount: amount} = fields) do
    Map.merge(fields, %{
      id: entity.id,
      entity_type: entity_type,
      section: section,
      amount: amount && Money.to_decimal(amount),
      currency: amount && amount |> Money.to_currency_code() |> Atom.to_string(),
      categories:
        Enum.map(
          entity.entity_tags,
          &%{kind: &1.kind, name: &1.tag_definition && &1.tag_definition.name}
        )
    })
  end
end
