defmodule Firmowid.Ash.Invoicing.Services.InvoiceListing do
  @moduledoc "Merges bounded authorized invoice reads using a validated date/id/type cursor."

  import Ash.Expr

  alias Ash.Error.Action.InvalidArgument
  alias Firmowid.Ash.Invoicing
  alias Firmowid.Ash.Scope

  @doc "Lists invoices using validated Ash arguments and the action's actor/tenant context."
  @spec list(map(), map()) :: {:ok, map()} | {:error, term()}
  def list(arguments, context) do
    with {:ok, scope} <- validated_scope(context),
         {:ok, filters} <- normalize(arguments),
         {:ok, cursor} <- decode_cursor(arguments[:cursor], filters, scope.tenant),
         {:ok, rows} <- read_invoices(filters, cursor, scope, context) do
      invoices = rows |> Enum.sort(&before?(&1, &2, filters.sort)) |> Enum.take(filters.limit + 1)
      has_more = length(invoices) > filters.limit
      page = Enum.take(invoices, filters.limit)

      {:ok,
       %{
         invoices: page,
         query: public_filters(filters),
         has_more: has_more,
         next_cursor: if(has_more, do: encode_cursor(List.last(page), filters, scope.tenant))
       }}
    end
  end

  defp validated_scope(%{actor: actor, tenant: tenant}) when is_binary(tenant) do
    case Scope.new(actor, tenant) do
      {:ok, scope} -> {:ok, scope}
      {:error, :actor_tenant_mismatch} -> invalid(:tenant, "Actor does not belong to tenant")
    end
  end

  defp validated_scope(_context), do: invalid(:tenant, "An authenticated tenant scope is required")

  defp normalize(arguments) do
    filters =
      %{query: nil, date_from: nil, date_to: nil, currency: nil}
      |> Map.merge(Map.take(arguments, [:type, :query, :date_from, :date_to, :currency, :sort, :limit]))
      |> Map.update!(:query, &trim_optional/1)
      |> Map.update!(:currency, fn currency ->
        case trim_optional(currency) do
          nil -> nil
          value -> String.upcase(value)
        end
      end)

    cond do
      filters.date_from && filters.date_to &&
          Date.after?(filters.date_from, filters.date_to) ->
        invalid(:date_to, "Must be on or after date_from")

      filters.currency &&
          filters.currency not in Enum.map(Money.known_currencies(), &to_string/1) ->
        invalid(:currency, "Must be a recognized currency code")

      true ->
        {:ok, filters}
    end
  end

  defp trim_optional(nil), do: nil

  defp trim_optional(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp public_filters(filters) do
    filters
    |> Map.update!(:type, &Atom.to_string/1)
    |> Map.update!(:sort, &Atom.to_string/1)
    |> Map.update!(:date_from, &iso_date/1)
    |> Map.update!(:date_to, &iso_date/1)
  end

  defp fingerprint(filters, tenant) do
    query = public_filters(filters)

    values =
      Enum.map(
        [:type, :query, :date_from, :date_to, :currency, :sort, :limit],
        &Map.fetch!(query, &1)
      )

    :sha256
    |> :crypto.hash(Jason.encode!([tenant | values]))
    |> Base.url_encode64(padding: false)
  end

  defp decode_cursor(nil, _filters, _tenant), do: {:ok, nil}

  defp decode_cursor(value, filters, tenant) do
    with {:ok, json} <- Base.url_decode64(value, padding: false),
         {:ok, %{"v" => 1, "filter" => binding, "date" => date, "id" => id, "type" => type}} <-
           Jason.decode(json),
         true <- binding == fingerprint(filters, tenant),
         true <- type in ["cost", "sales"],
         true <- filters.type == :all or Atom.to_string(filters.type) == type,
         {:ok, id} <- Ecto.UUID.cast(id),
         {:ok, date} <- cursor_date(date) do
      {:ok, %{date: date, id: id, type: type}}
    else
      _ -> invalid(:cursor, "Invalid cursor or cursor does not match the current filters")
    end
  end

  defp cursor_date(nil), do: {:ok, nil}
  defp cursor_date(value) when is_binary(value), do: Date.from_iso8601(value)
  defp cursor_date(_value), do: :error

  defp encode_cursor(row, filters, tenant) do
    %{
      v: 1,
      filter: fingerprint(filters, tenant),
      date: row.issue_date,
      id: row.id,
      type: row.type
    }
    |> Jason.encode!()
    |> Base.url_encode64(padding: false)
  end

  defp read_invoices(filters, cursor, scope, context) do
    types = if filters.type == :all, do: [:cost, :sales], else: [filters.type]

    Enum.reduce_while(types, {:ok, []}, fn type, {:ok, rows} ->
      case read_type(type, filters, cursor, scope, context) do
        {:ok, records} -> {:cont, {:ok, rows ++ Enum.map(records, &row(&1, type))}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp read_type(type, filters, cursor, scope, context) do
    params =
      filters
      |> Map.take([:query, :date_from, :date_to, :currency])
      |> Map.put(:limit, filters.limit + 1)
      |> Map.put(:listing_sort, filters.sort)

    opts =
      context
      |> Ash.Context.to_opts()
      |> Keyword.drop([:actor, :tenant, :authorize?])
      |> Keyword.merge(
        scope: scope,
        authorize?: true,
        query: [filter: cursor_filter(cursor, type, filters.sort)]
      )

    case type do
      :cost -> Invoicing.list_cost_invoices(params, Keyword.put(opts, :page, false))
      :sales -> Invoicing.list_sales_invoices(params, Keyword.put(opts, :load, [:gross_value]))
    end
  end

  # Null dates always sort last. IDs are ascending in both directions; type breaks
  # the possible cross-resource UUID tie, so each source uses the same boundary.
  defp cursor_filter(nil, _type, _sort), do: true

  defp cursor_filter(cursor, type, sort) do
    date_cursor_filter(cursor.date, sort, id_cursor_filter(cursor, type))
  end

  defp id_cursor_filter(cursor, type) do
    if Atom.to_string(type) > cursor.type do
      expr(id >= ^cursor.id)
    else
      expr(id > ^cursor.id)
    end
  end

  defp date_cursor_filter(nil, _sort, id_filter), do: expr(is_nil(issue_date) and ^id_filter)

  defp date_cursor_filter(date, :newest, id_filter) do
    expr(is_nil(issue_date) or issue_date < ^date or (issue_date == ^date and ^id_filter))
  end

  defp date_cursor_filter(date, :oldest, id_filter) do
    expr(is_nil(issue_date) or issue_date > ^date or (issue_date == ^date and ^id_filter))
  end

  defp before?(left, right, sort) do
    case {left.issue_date, right.issue_date} do
      {date, date} -> {left.id, left.type} <= {right.id, right.type}
      {nil, _date} -> false
      {_date, nil} -> true
      {left_date, right_date} when sort == :newest -> left_date > right_date
      {left_date, right_date} -> left_date < right_date
    end
  end

  defp row(invoice, :sales) do
    invoice
    |> common_row("sales", invoice.invoice_number, invoice.ksef_invoice_kind)
    |> Map.put(:counterparty, sales_counterparty(invoice))
    |> Map.put(:amount, %{
      value: Decimal.to_string(invoice.gross_value || Decimal.new(0), :normal),
      currency: invoice.currency
    })
  end

  defp row(invoice, :cost) do
    invoice
    |> common_row("cost", invoice.invoice_identifier, invoice.invoice_type)
    |> Map.put(:counterparty, present_name(invoice.seller_display_name) || invoice.seller || "")
    |> Map.put(:amount, money(invoice.amount))
  end

  defp common_row(invoice, type, number, kind) do
    %{
      id: invoice.id,
      type: type,
      number: number,
      issue_date: iso_date(invoice.issue_date),
      due_date: iso_date(invoice.due_date),
      ksef_number: invoice.ksef_number,
      invoice_kind: if(kind, do: Atom.to_string(kind))
    }
  end

  defp sales_counterparty(invoice) do
    present_name(invoice.buyer_display_name) || present_name(invoice.buyer_full_name) ||
      Enum.join(Enum.reject([invoice.buyer_given_name, invoice.buyer_surname], &is_nil/1), " ")
  end

  defp present_name(value), do: trim_optional(value)

  defp money(%Money{amount: amount, currency: currency}) do
    %{value: Decimal.to_string(amount, :normal), currency: to_string(currency)}
  end

  defp iso_date(nil), do: nil
  defp iso_date(date), do: Date.to_iso8601(date)

  defp invalid(field, message), do: {:error, InvalidArgument.exception(field: field, message: message)}
end
