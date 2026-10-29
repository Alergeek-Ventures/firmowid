defmodule Firmowid.Analysis.Actions.GetTaxForecast do
  @moduledoc "Loads invoice inputs only after checking the member's role and tenant."
  use Ash.Resource.Actions.Implementation

  alias Firmowid.Analysis.TaxForecastCalculator
  alias Firmowid.Core
  alias Firmowid.Core.User
  alias Firmowid.Currencies.NbpApiClient
  alias Firmowid.Invoicing
  alias Firmowid.Invoicing.Calculations.AnnotatedCorrections
  alias Firmowid.Invoicing.CostInvoice
  alias Firmowid.Invoicing.SalesInvoice
  alias Firmowid.Scope
  alias Firmowid.SystemActor

  @impl true
  def run(input, _opts, %{
        actor: %User{member: %{organization_id: tenant, archived_at: nil, role: role}} = actor,
        tenant: tenant
      })
      when is_binary(tenant) and role in [:invoicing, :accountant, :admin] do
    scope = Scope.new!(actor, tenant)

    # Organization has no analysis_reader bypass. Read configuration as the human,
    # then grant invoice-only read access for this already verified organization.
    with {:ok, organization} <-
           Core.get_organization(tenant, scope: scope, not_found_error?: true) do
      reader = Scope.new!(%SystemActor{org_id: tenant, role: :analysis_reader}, tenant)

      with {:ok, sales} <-
             SalesInvoice.list(%{submission: :confirmed},
               scope: reader,
               page: false,
               load: [
                 :sales_invoice_items,
                 corrected_invoice: [
                   :sales_invoice_items,
                   corrections: [:sales_invoice_items, :locked_at, :inserted_at]
                 ]
               ]
             ),
           {:ok, costs} <- CostInvoice.list(%{}, scope: reader, page: false) do
        sales = Enum.map(sales, &with_reference/1)
        conversions = conversion_context(input.arguments.month, sales, costs, organization)

        {:ok,
         TaxForecastCalculator.calculate(
           input.arguments.month,
           organization.is_vat_payer,
           sales,
           costs,
           organization.tax_forecast_settings,
           conversions
         )}
      end
    end
  end

  def run(_input, _opts, _context), do: {:error, Ash.Error.Forbidden.exception([])}

  defp conversion_context(month, sales, costs, organization) do
    settings = organization.tax_forecast_settings || %{}

    income? =
      not is_nil(settings[:income_reserve_rate]) and settings[:invoice_costs_deductible] == true

    documents =
      if organization.is_vat_payer == true or income? do
        Enum.map(sales, &{:sales_invoice, &1, &1.currency}) ++
          Enum.flat_map(costs, fn invoice ->
            if needs_cost_rate?(invoice, income?),
              do: [{:cost_invoice, invoice, to_string(invoice.amount.currency)}],
              else: []
          end)
      else
        []
      end

    documents
    |> Enum.filter(fn {_type, invoice, currency} ->
      date = invoice.sale_date || invoice.issue_date

      currency != "PLN" and
        (is_nil(date) or Date.beginning_of_month(date) == Date.beginning_of_month(month))
    end)
    |> Map.new(fn {type, invoice, currency} ->
      {{type, invoice.id}, document_rate(invoice, currency)}
    end)
  end

  defp needs_cost_rate?(_invoice, true), do: true

  defp needs_cost_rate?(%{amount: %Money{currency: currency}, deductible_vat_amount: %Money{currency: currency}}, false),
    do: currency != :PLN

  defp needs_cost_rate?(_invoice, false), do: false

  defp document_rate(%{issue_date: nil}, currency),
    do: {:error, %{reason: :exchange_rate_unavailable, currency: currency, rate_date: nil}}

  defp document_rate(invoice, currency) do
    date =
      if invoice.sale_date,
        do: Invoicing.get_currency_conversion_date(invoice.issue_date, invoice.sale_date),
        else: invoice.issue_date

    cond do
      not NbpApiClient.supported_currency?(currency) ->
        {:error, :unsupported_currency}

      Date.after?(date, Date.utc_today()) ->
        {:error, %{reason: :exchange_rate_unavailable, currency: currency, rate_date: date}}

      true ->
        case Invoicing.get_currency_rate(%{
               currency: currency,
               issue_date: invoice.issue_date,
               sale_date: invoice.sale_date
             }) do
          nil ->
            {:error, %{reason: :exchange_rate_unavailable, currency: currency, rate_date: date}}

          metadata ->
            {:ok, Map.merge(metadata, %{currency: currency, conversion_date: date})}
        end
    end
  end

  defp with_reference(%{ksef_invoice_kind: :vat} = invoice), do: %{invoice | reference_invoice: nil}

  defp with_reference(%{corrected_invoice: nil} = invoice), do: %{invoice | reference_invoice: nil}

  defp with_reference(invoice) do
    # Match list's :confirmed semantics: a draft cannot be a tax before-state.
    corrected_invoice = %{
      invoice.corrected_invoice
      | corrections: Enum.reject(invoice.corrected_invoice.corrections, &is_nil(&1.invoice_number))
    }

    # Resolve from the fully loaded chain. ReferenceInvoice's calculation load
    # does not declare the timestamps required for ordering its dependencies.
    correction =
      corrected_invoice
      |> AnnotatedCorrections.annotate()
      |> Enum.find(&(&1.id == invoice.id))

    %{invoice | reference_invoice: correction.reference_invoice}
  end
end
