defmodule Firmowid.Ash.Invoicing.Calculations.CounterpartyTaxIdType do
  @moduledoc """
  Computes the tax ID type for a counterparty based on country and PESEL presence.

  Returns one of `:nip`, `:eu_vat`, `:other_id`, `:optional_id`, or `:no_id`.
  Delegates to `Firmowid.SalesInvoices.CountryCodes.tax_id_type/2`.
  """
  use Ash.Resource.Calculation

  alias Firmowid.SalesInvoices.CountryCodes

  @impl true
  def load(_query, _opts, _context), do: [:country, :pesel]

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, fn record ->
      CountryCodes.tax_id_type(record.country, record.pesel)
    end)
  end
end
