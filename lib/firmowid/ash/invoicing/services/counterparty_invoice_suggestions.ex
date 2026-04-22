defmodule Firmowid.Ash.Invoicing.Services.CounterpartyInvoiceSuggestions do
  @moduledoc """
  Suggests unlinked sales invoices for a counterparty by matching normalized buyer
  identifiers within the same buyer context.

  Matching prefers the counterparty `pesel` against invoice `buyer_pesel`, falling
  back to `tax_id` against `buyer_id`. Tax IDs are normalized by uppercasing and
  stripping non-alphanumeric characters so values like `PL 123-456-78-90` and
  `PL1234567890` compare equally, while PESEL values are normalized to digits only.
  Suggestions are additionally constrained to the same `country` and `type` to
  avoid collisions across buyer contexts.
  """

  alias Firmowid.Ash.Invoicing.Counterparty
  alias Firmowid.Ash.Invoicing.IdentifierNormalization
  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Ash.Scope

  require Ash.Query

  @default_limit 10

  @doc """
  Returns suggested, currently unlinked sales invoices for the given counterparty.
  """
  @spec list_for_counterparty(Counterparty.t() | map(), Scope.t(), keyword()) :: [
          SalesInvoice.t()
        ]
  def list_for_counterparty(counterparty, %Scope{} = scope, opts \\ []) do
    limit = Keyword.get(opts, :limit, @default_limit)

    case normalized_identifier(counterparty) do
      nil ->
        []

      {identifier_type, normalized_identifier} ->
        counterparty
        |> suggested_invoice_ids(identifier_type, normalized_identifier, scope, limit)
        |> load_invoices(scope)
    end
  end

  @doc """
  Returns true when the given invoice is currently suggested for the counterparty.
  """
  @spec suggested_for_counterparty?(
          Counterparty.t() | map(),
          SalesInvoice.t() | map() | binary(),
          Scope.t()
        ) :: boolean()
  def suggested_for_counterparty?(counterparty, invoice_or_id, %Scope{} = scope) do
    case normalized_identifier(counterparty) do
      nil ->
        false

      {identifier_type, normalized_identifier} ->
        invoice_id = invoice_id(invoice_or_id)

        counterparty
        |> suggested_invoice_query(identifier_type, normalized_identifier, scope)
        |> Ash.Query.filter(id == ^invoice_id)
        |> Ash.Query.select([:id])
        |> Ash.read_one!(scope: scope)
        |> Kernel.!=(nil)
    end
  end

  defp suggested_invoice_ids(counterparty, identifier_type, normalized_identifier, %Scope{} = scope, limit) do
    counterparty
    |> suggested_invoice_query(identifier_type, normalized_identifier, scope)
    |> Ash.Query.sort(issue_date: :desc, inserted_at: :desc)
    |> Ash.Query.limit(limit)
    |> Ash.Query.select([:id])
    |> Ash.read!(scope: scope)
    |> Enum.map(& &1.id)
  end

  defp load_invoices([], _scope), do: []

  defp load_invoices(invoice_ids, scope) do
    invoices_by_id =
      SalesInvoice
      |> Ash.Query.for_read(:read, %{ids: invoice_ids}, scope: scope)
      |> Ash.Query.load([:gross_value, :transactions])
      |> Ash.read!(scope: scope)
      |> Map.new(&{&1.id, &1})

    invoice_ids
    |> Enum.map(&Map.get(invoices_by_id, &1))
    |> Enum.reject(&is_nil/1)
  end

  defp normalized_identifier(counterparty) do
    case IdentifierNormalization.normalize_pesel(counterparty.pesel) do
      nil ->
        case IdentifierNormalization.normalize_tax_id(counterparty.tax_id) do
          nil -> nil
          normalized_tax_id -> {:tax_id, normalized_tax_id}
        end

      normalized_pesel ->
        {:pesel, normalized_pesel}
    end
  end

  defp invoice_id(%{id: id}), do: id
  defp invoice_id(id), do: id

  defp suggested_invoice_query(counterparty, :tax_id, normalized_tax_id, %Scope{} = scope) do
    SalesInvoice
    |> Ash.Query.for_read(:read, %{}, scope: scope)
    |> Ash.Query.filter(
      organization_id == ^scope.tenant and
        is_nil(counterparty_id) and
        buyer_type == ^counterparty.type and
        buyer_country == ^counterparty.country and
        not is_nil(buyer_id) and
        buyer_id != "" and
        fragment(
          "regexp_replace(upper(coalesce(?, '')), '[^0-9A-Z]', '', 'g')",
          buyer_id
        ) == ^normalized_tax_id
    )
  end

  defp suggested_invoice_query(counterparty, :pesel, normalized_pesel, %Scope{} = scope) do
    SalesInvoice
    |> Ash.Query.for_read(:read, %{}, scope: scope)
    |> Ash.Query.filter(
      organization_id == ^scope.tenant and
        is_nil(counterparty_id) and
        buyer_type == ^counterparty.type and
        buyer_country == ^counterparty.country and
        not is_nil(buyer_pesel) and
        buyer_pesel != "" and
        fragment("regexp_replace(coalesce(?, ''), '\\D', '', 'g')", buyer_pesel) ==
          ^normalized_pesel
    )
  end
end
