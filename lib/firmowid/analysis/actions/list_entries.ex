defmodule Firmowid.Analysis.Actions.ListEntries do
  @moduledoc """
  Lists the analysis entries of whole months as counted on the analysis
  dashboard, with their template category, the counterparty's register data and
  the split of each amount between projects, shared costs, company and taxes.
  """
  use Ash.Resource.Actions.Implementation

  alias Ash.Error.Changes.InvalidArgument
  alias Firmowid.Analysis
  alias Firmowid.Analysis.CategoryTotals
  alias Firmowid.Core
  alias Firmowid.Core.Nip
  alias Firmowid.Core.RegisteredCompany
  alias Firmowid.Core.User
  alias Firmowid.Finances.Transaction
  alias Firmowid.Invoicing.CostInvoice
  alias Firmowid.Invoicing.SalesInvoice
  alias Firmowid.Scope

  @sources %{confirmed: :owner, certain: :rule, jev: :classifier}

  @impl true
  def run(input, _opts, %{actor: %User{member: %{organization_id: tenant}} = actor, tenant: tenant})
      when is_binary(tenant) do
    # Salaries count in their salary month, so only whole months add up to the totals.
    from = Date.beginning_of_month(input.arguments.from)
    to = Date.end_of_month(input.arguments.to)

    cond do
      Date.before?(to, from) ->
        {:error, InvalidArgument.exception(field: :to, message: "must not be before from")}

      Date.after?(Date.beginning_of_month(to), Date.shift(from, month: 11)) ->
        {:error, InvalidArgument.exception(field: :to, message: "must be within 12 months of from")}

      true ->
        {:ok, list(from, to, %Scope{actor: actor, tenant: tenant})}
    end
  end

  # This must also reject mismatched tenants for admins, whose policy bypass is global.
  def run(_input, _opts, _context), do: {:error, Ash.Error.Forbidden.exception([])}

  defp list(from, to, scope) do
    entries = Analysis.get_organization_entries(from, to, scope)
    categorized = Analysis.categorize_entries(entries, scope)
    entities = entries.sales_invoices ++ entries.cost_invoices ++ entries.transactions

    # Only the cache is read: listing never waits for the public registers.
    companies =
      entities
      |> Enum.flat_map(&List.wrap(nip(&1)))
      |> Enum.uniq()
      |> Core.list_registered_companies!(scope: scope)
      |> Map.new(&{&1.nip, &1})

    %{
      industry: Core.get_organization!(scope.tenant, scope: scope).industry,
      entries:
        entities
        |> Enum.map(&entry(&1, Map.get(categorized, {Analysis.entity_type(&1), &1.id}), companies))
        |> Enum.sort_by(& &1.date, Date)
    }
  end

  # Internal entries and zero amounts are not counted, so they have no review entry.
  defp entry(entity, counted, companies) do
    {review, {category, source}} = counted || {nil, {nil, nil}}
    amount = amount(entity)
    nip = nip(entity)

    entity
    |> fields()
    |> Map.merge(%{
      id: entity.id,
      entity_type: Analysis.entity_type(entity),
      internal: Enum.any?(entity.entity_tags, &(&1.kind == :internal)),
      counterparty_nip: nip || Analysis.counterparty_nip(entity),
      registered_activity: registered_activity(Map.get(companies, nip)),
      month: Analysis.entry_month(entity),
      amount: amount && Money.to_decimal(amount),
      currency: amount && amount |> Money.to_currency_code() |> Atom.to_string(),
      amount_pln: review && signed(review),
      category: category,
      category_source: Map.get(@sources, source),
      category_probability: if(source == :jev, do: review.probability),
      allocation: if(review, do: allocation(review, entity.entity_tags), else: [])
    })
  end

  defp fields(%SalesInvoice{} = invoice) do
    %{
      section: :income,
      counterparty: invoice.buyer_display_name_label,
      description: Enum.map_join(invoice.sales_invoice_items, ", ", & &1.name),
      date: invoice.sale_date || invoice.issue_date
    }
  end

  defp fields(%CostInvoice{} = invoice) do
    %{
      section: :expenses,
      counterparty: invoice.effective_seller_display_name || invoice.seller_display_name || invoice.seller,
      description: invoice.description,
      date: invoice.effective_sale_date || invoice.sale_date
    }
  end

  defp fields(%Transaction{} = transaction) do
    income? = Money.positive?(transaction.amount)

    %{
      section: if(income?, do: :income, else: :expenses),
      counterparty: if(income?, do: transaction.debtor_name, else: transaction.creditor_name),
      description: transaction.remittance_information_unstructured,
      date: transaction.booking_date
    }
  end

  defp amount(%Transaction{amount: amount}), do: amount
  defp amount(invoice), do: invoice.effective_amount

  defp registered_activity(%RegisteredCompany{} = company), do: RegisteredCompany.activity(company)

  defp registered_activity(nil), do: nil

  # Digits of a valid Polish NIP, the form the register cache is keyed by.
  defp nip(entity) do
    nip = Analysis.counterparty_nip(entity)
    if Nip.valid?(nip), do: Nip.normalize_digits(nip)
  end

  defp signed(%{side: :expenses, amount: amount}), do: Decimal.negate(amount)
  defp signed(%{side: :income, amount: amount}), do: amount

  # The same cent allocation as the totals, so per-project sums match the dashboard.
  defp allocation(review, tags) do
    review.amount
    |> CategoryTotals.split(tags)
    |> Enum.map(fn share ->
      %{
        kind: kind(share.key),
        name: share.name,
        amount_pln: signed(%{side: review.side, amount: share.amount})
      }
    end)
  end

  defp kind({:project, _id}), do: :project
  defp kind({:function, _id}), do: :shared_cost
  defp kind(key) when key in [:company, :taxes, :unassigned], do: key
end
