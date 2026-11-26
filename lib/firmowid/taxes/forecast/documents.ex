defmodule Firmowid.Taxes.Forecast.Documents do
  @moduledoc """
  Reads the documents a tax year's calculations build on, and turns them into
  the income entries of `Firmowid.Taxes.Forecast.IncomeEntries`. The forecast
  and the suggestions of the owner's settings (`Firmowid.Taxes.TaxYear.Actions`)
  share it, so both see the same entries.

  Everything is read with the options of the caller (its actor and tenant), so
  the caller's policies decide what is seen.
  """

  alias Firmowid.Analysis
  alias Firmowid.Analysis.OwnAccounts
  alias Firmowid.Core.Organization
  alias Firmowid.Finances
  alias Firmowid.Invoicing
  alias Firmowid.Scope
  alias Firmowid.Taxes.Forecast.Income
  alias Firmowid.Taxes.Forecast.IncomeEntries

  @type t :: %{
          required(:sales_invoices) => [struct()],
          required(:cost_invoices) => [struct()],
          required(:salaries) => [struct()],
          required(:skipped_transactions) => [struct()],
          optional(atom()) => any()
        }

  @doc """
  Reads every document set once, from the year before too: a cash accounting
  invoice of it may be paid in `year`, and the owners' health contribution and
  Mały ZUS Plus look back.
  """
  @spec read(integer(), keyword()) :: t()
  def read(year, opts) do
    dates = %{
      date_from: Date.new!(year - 1, 1, 1),
      date_to: Date.new!(year, 12, 31),
      date_field: :any
    }

    two_years = Map.delete(dates, :date_field)

    %{
      sales_invoices:
        dates
        |> Map.put(:submission, :confirmed)
        |> Invoicing.list_sales_invoices!(
          Keyword.put(opts, :load, [
            :vat_value,
            :net_value,
            :gross_value,
            :transactions,
            corrected_invoice: [:vat_value, :net_value, corrections: [:vat_value, :net_value]]
          ])
        ),
      cost_invoices:
        Invoicing.list_cost_invoices!(
          dates,
          Keyword.put(opts, :load, [:transactions, :original_invoice])
        ),
      salaries:
        %{salary_assigned: true}
        |> Finances.list_transactions!(opts)
        |> Enum.filter(&(&1.salary_month in Date.range(two_years.date_from, two_years.date_to))),
      skipped_transactions:
        two_years
        |> Map.merge(%{reconciliation: :skipped, salary_assigned: false})
        |> Finances.list_transactions!(Keyword.put(opts, :load, [:entity_tags]))
    }
  end

  @doc """
  Builds the income entries of `documents`. The categories the analysis resolves
  for the skipped transfers (the owner's confirmed rules, certain signals, the
  classifier), read as the caller, tell which of them are costs.
  """
  @spec income_entries(t(), Organization.t(), Scope.t()) :: [Income.entry()]
  def income_entries(documents, organization, scope) do
    categories =
      %{sales_invoices: [], cost_invoices: [], transactions: documents.skipped_transactions}
      |> Analysis.categorize_entries(scope)
      |> Map.new(fn {{:transaction, id}, {_entry, {category, _source}}} -> {id, category} end)

    IncomeEntries.build(
      Map.put(documents, :categories, categories),
      organization,
      OwnAccounts.load(scope)
    )
  end
end
