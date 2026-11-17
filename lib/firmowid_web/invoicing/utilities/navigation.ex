defmodule FirmowidWeb.Invoicing.Utilities.Navigation do
  @moduledoc """
  Central navigation contract for invoicing return paths.
  """

  use FirmowidWeb, :verified_routes

  alias Firmowid.Finances.Transaction
  alias Firmowid.Invoicing.CostInvoice
  alias Firmowid.Invoicing.SalesInvoice
  alias FirmowidWeb.Infrastructure.Utilities.Navigation, as: InfrastructureNavigation
  alias FirmowidWeb.Infrastructure.Utilities.QueryParams
  alias FirmowidWeb.Invoicing.SalesInvoices.Utilities.CreatorQueryParams
  alias FirmowidWeb.Invoicing.Utilities.InvoiceDownloadParams
  alias FirmowidWeb.Invoicing.Utilities.QueryCodec

  @type invoicing_index_target :: %{
          month: Date.t(),
          filter: QueryCodec.filter(),
          subfilter: QueryCodec.subfilter() | nil
        }
  @type return_target ::
          {:invoicing_index, invoicing_index_target()}
          | :last_sales_invoices
          | {:transaction_show, Ash.UUID.t(), return_destination()}
  @type return_destination :: return_target() | String.t() | nil

  @doc """
  Builds the canonical path of the list of invoices or of transactions for the given params.
  """
  @spec invoicing_index_path(invoicing_index_target()) :: String.t()
  def invoicing_index_path(%{month: month, filter: filter, subfilter: subfilter}) do
    query =
      QueryParams.compact(
        miesiac: month |> Date.beginning_of_month() |> Date.to_iso8601(),
        filtr: QueryCodec.encode_filter(filter),
        podfiltr: encode_subfilter(subfilter)
      )

    ~p"/fakturowanie?#{query}"
  end

  @doc """
  Builds the path of the list of invoices of every month.
  """
  @spec invoices_list_path() :: String.t()
  def invoices_list_path, do: ~p"/fakturowanie?#{[filtr: QueryCodec.encode_filter(:invoices)]}"

  @doc """
  Builds the path of the list of transactions of every month.
  """
  @spec transactions_list_path() :: String.t()
  def transactions_list_path, do: ~p"/fakturowanie?#{[filtr: QueryCodec.encode_filter(:transactions)]}"

  @doc """
  Builds the canonical path to the recent sales invoices tab.
  """
  @spec last_sales_invoices_path() :: String.t()
  def last_sales_invoices_path,
    do: ~p"/sprzedazowe?#{[karta: QueryCodec.encode_last_sales_invoices_tab(:last_sales_invoices)]}"

  @doc """
  Builds the canonical sales invoice creator path.
  """
  @spec sales_invoice_creator_path() :: String.t()
  def sales_invoice_creator_path, do: ~p"/sprzedazowe"

  @spec sales_invoice_creator_path(map()) :: String.t()
  def sales_invoice_creator_path(params) when is_map(params) do
    ~p"/sprzedazowe?#{QueryParams.compact(params)}"
  end

  @doc """
  Resolves a raw sales-invoice creator return path into its canonical allowlisted path.
  """
  @spec sales_invoice_creator_return_path(String.t() | nil) :: String.t() | nil
  def sales_invoice_creator_return_path(nil), do: nil

  def sales_invoice_creator_return_path(raw_return_to) when is_binary(raw_return_to) do
    case URI.parse(raw_return_to) do
      %URI{
        scheme: nil,
        host: nil,
        authority: nil,
        fragment: nil,
        path: "/sprzedazowe",
        query: query
      } ->
        params = URI.decode_query(query || "")

        case CreatorQueryParams.normalize_return_params(params) do
          {:ok, normalized_params} -> sales_invoice_creator_path(Map.new(normalized_params))
          _other -> nil
        end

      _other ->
        nil
    end
  end

  def sales_invoice_creator_return_path(_raw_return_to), do: nil

  @doc """
  Builds the monthly invoice-download path.
  """
  @spec month_download_path(Date.t(), map()) :: String.t()
  def month_download_path(%Date{} = month, options) when is_map(options) do
    ~p"/pobierz-miesiac" <>
      "?" <> InvoiceDownloadParams.encode_month_download_query(month, options)
  end

  @doc """
  Builds a PDF download path with the internal-note query param.
  """
  @spec pdf_download_path(String.t(), boolean()) :: String.t()
  def pdf_download_path(path, include_internal_note) when is_binary(path) and is_boolean(include_internal_note) do
    path <> "?" <> InvoiceDownloadParams.encode_pdf_query(include_internal_note)
  end

  @doc """
  Builds the canonical sales-invoice PDF download path.
  """
  @spec sales_invoice_pdf_path(SalesInvoice.t() | Ash.UUID.t()) :: String.t()
  def sales_invoice_pdf_path(invoice_or_id)

  def sales_invoice_pdf_path(%SalesInvoice{id: id}), do: sales_invoice_pdf_path(id)

  def sales_invoice_pdf_path(id) when is_binary(id) do
    ~p"/sprzedazowe/#{id}/pobierz"
  end

  @doc """
  Builds the canonical sales-invoice PDF download path with query params.
  """
  @spec sales_invoice_pdf_download_path(SalesInvoice.t() | Ash.UUID.t(), boolean()) :: String.t()
  def sales_invoice_pdf_download_path(invoice_or_id, include_internal_note)

  def sales_invoice_pdf_download_path(%SalesInvoice{id: id}, include_internal_note),
    do: sales_invoice_pdf_download_path(id, include_internal_note)

  def sales_invoice_pdf_download_path(id, include_internal_note) when is_binary(id) do
    pdf_download_path(sales_invoice_pdf_path(id), include_internal_note)
  end

  @doc """
  Builds the canonical cost-invoice PDF download path.
  """
  @spec cost_invoice_pdf_path(CostInvoice.t() | Ash.UUID.t()) :: String.t()
  def cost_invoice_pdf_path(invoice_or_id)

  def cost_invoice_pdf_path(%CostInvoice{id: id}), do: cost_invoice_pdf_path(id)

  def cost_invoice_pdf_path(id) when is_binary(id) do
    ~p"/kosztowe/#{id}/pobierz"
  end

  @doc """
  Builds the canonical cost-invoice PDF download path with query params.
  """
  @spec cost_invoice_pdf_download_path(CostInvoice.t() | Ash.UUID.t(), boolean()) :: String.t()
  def cost_invoice_pdf_download_path(invoice_or_id, include_internal_note)

  def cost_invoice_pdf_download_path(%CostInvoice{id: id}, include_internal_note),
    do: cost_invoice_pdf_download_path(id, include_internal_note)

  def cost_invoice_pdf_download_path(id, include_internal_note) when is_binary(id) do
    pdf_download_path(cost_invoice_pdf_path(id), include_internal_note)
  end

  @doc """
  Parses raw invoicing index query params into the canonical typed state. Without a
  list asked for in `filtr`, the filter is `nil`.
  """
  @spec parse_invoicing_index_params(map(), Date.t()) :: %{
          month: Date.t(),
          filter: QueryCodec.filter() | nil,
          subfilter: QueryCodec.subfilter() | nil
        }
  def parse_invoicing_index_params(params, date \\ Date.utc_today()) when is_map(params) do
    %{
      month: QueryParams.parse_date(params, "miesiac", Date.beginning_of_month(date)),
      filter: QueryCodec.parse_filter(Map.get(params, "filtr")),
      subfilter: QueryCodec.parse_subfilter(Map.get(params, "podfiltr"))
    }
  end

  @doc """
  Builds the canonical transaction details path with an optional return destination.
  """
  @spec transaction_show_path(Transaction.t() | Ash.UUID.t(), return_destination()) :: String.t()
  def transaction_show_path(transaction_or_id, return_to \\ nil)

  def transaction_show_path(%Transaction{id: id}, return_to), do: transaction_show_path(id, return_to)

  def transaction_show_path(id, return_to) when is_binary(id),
    do: append_return_to(~p"/transakcje/#{id}", normalize_return_to(return_to))

  @doc """
  Builds the canonical sales invoice details path with an optional return destination.
  """
  @spec sales_invoice_show_path(SalesInvoice.t() | Ash.UUID.t(), return_destination()) ::
          String.t()
  def sales_invoice_show_path(invoice_or_id, return_to \\ nil)

  def sales_invoice_show_path(%SalesInvoice{id: id}, return_to), do: sales_invoice_show_path(id, return_to)

  def sales_invoice_show_path(id, return_to) when is_binary(id),
    do: append_return_to(~p"/sprzedazowe/#{id}", normalize_return_to(return_to))

  @doc """
  Builds the canonical sales invoice edit path with an optional return destination.
  """
  @spec sales_invoice_edit_path(SalesInvoice.t() | Ash.UUID.t(), return_destination()) ::
          String.t()
  def sales_invoice_edit_path(invoice_or_id, return_to \\ nil)

  def sales_invoice_edit_path(%SalesInvoice{id: id}, return_to), do: sales_invoice_edit_path(id, return_to)

  def sales_invoice_edit_path(id, return_to) when is_binary(id),
    do: append_return_to(~p"/sprzedazowe/#{id}/edytuj", normalize_return_to(return_to))

  @doc """
  Builds the canonical sales invoice summary path with an optional return destination.
  """
  @spec sales_invoice_summary_path(SalesInvoice.t() | Ash.UUID.t(), return_destination()) ::
          String.t()
  def sales_invoice_summary_path(invoice_or_id, return_to \\ nil)

  def sales_invoice_summary_path(%SalesInvoice{id: id}, return_to), do: sales_invoice_summary_path(id, return_to)

  def sales_invoice_summary_path(id, return_to) when is_binary(id),
    do: append_return_to(~p"/sprzedazowe/#{id}/podsumowanie", normalize_return_to(return_to))

  @doc """
  Builds the canonical cost invoice details path with an optional return destination.
  """
  @spec cost_invoice_show_path(CostInvoice.t() | Ash.UUID.t(), return_destination()) ::
          String.t()
  def cost_invoice_show_path(invoice_or_id, return_to \\ nil)

  def cost_invoice_show_path(%CostInvoice{id: id}, return_to), do: cost_invoice_show_path(id, return_to)

  def cost_invoice_show_path(id, return_to) when is_binary(id),
    do: append_return_to(~p"/kosztowe/#{id}", normalize_return_to(return_to))

  @doc """
  Parses a raw `return_to` query param into a typed, allowlisted target.
  """
  @spec parse_return_target(String.t() | nil) :: return_target() | nil
  def parse_return_target(nil), do: nil

  def parse_return_target(raw_return_to) when is_binary(raw_return_to) do
    case URI.parse(raw_return_to) do
      %URI{scheme: nil, host: nil, authority: nil, fragment: nil, path: path, query: query} ->
        path
        |> resolve_allowlisted_target(query)
        |> case do
          {:ok, target} -> target
          :error -> nil
        end

      _ ->
        nil
    end
  end

  def parse_return_target(_raw_return_to), do: nil

  @doc """
  Renders a typed return target back into its canonical path.
  """
  @spec return_target_path(return_target() | nil) :: String.t() | nil
  def return_target_path(nil), do: nil
  def return_target_path(:last_sales_invoices), do: last_sales_invoices_path()

  def return_target_path({:invoicing_index, params}), do: invoicing_index_path(params)

  def return_target_path({:transaction_show, transaction_id, nested_return_target}) do
    append_return_to(
      ~p"/transakcje/#{transaction_id}",
      normalize_return_to(nested_return_target)
    )
  end

  @doc """
  Resolves a raw `return_to` query param into a canonical, allowlisted path.
  """
  @spec return_to_path(return_destination()) :: String.t() | nil
  def return_to_path(nil), do: nil

  def return_to_path(:last_sales_invoices), do: last_sales_invoices_path()

  def return_to_path({:invoicing_index, _params} = target), do: return_target_path(target)

  def return_to_path({:transaction_show, _transaction_id, _nested_target} = target), do: return_target_path(target)

  def return_to_path(raw_return_to) when is_binary(raw_return_to) do
    case parse_return_target(raw_return_to) do
      nil -> InfrastructureNavigation.allowlisted_return_path(raw_return_to)
      return_target -> return_target_path(return_target)
    end
  end

  def return_to_path(_raw_return_to), do: nil

  defp resolve_allowlisted_target("/fakturowanie", query), do: resolve_invoicing_index_target(query)

  defp resolve_allowlisted_target("/sprzedazowe", query), do: resolve_last_sales_invoices_target(query)

  defp resolve_allowlisted_target(path, query), do: resolve_transaction_show_target(path, query)

  defp resolve_invoicing_index_target(query) do
    params = URI.decode_query(query || "")

    with true <- Enum.all?(Map.keys(params), &(&1 in QueryCodec.invoicing_index_param_keys())),
         {:ok, month} <- parse_month(params),
         {:ok, filter} <- parse_filter(params),
         {:ok, subfilter} <- parse_subfilter(params) do
      {:ok, {:invoicing_index, %{month: month, filter: filter, subfilter: subfilter}}}
    else
      _ -> :error
    end
  end

  defp resolve_last_sales_invoices_target(query) do
    case URI.decode_query(query || "") do
      %{"karta" => raw_tab} ->
        case QueryCodec.parse_last_sales_invoices_tab(raw_tab) do
          :last_sales_invoices -> {:ok, :last_sales_invoices}
          _other -> :error
        end

      _ ->
        :error
    end
  end

  defp resolve_transaction_show_target(path, query) do
    with {:ok, transaction_id} <- parse_transaction_path(path),
         {:ok, return_target} <- parse_nested_return_target(query) do
      {:ok, {:transaction_show, transaction_id, return_target}}
    else
      _ -> :error
    end
  end

  defp parse_transaction_path("/transakcje/" <> transaction_id) do
    if transaction_id != "" and not String.contains?(transaction_id, "/") do
      {:ok, transaction_id}
    else
      :error
    end
  end

  defp parse_transaction_path(_path), do: :error

  defp parse_nested_return_target(nil), do: {:ok, nil}

  defp parse_nested_return_target(query) do
    case URI.decode_query(query) do
      %{} = params when map_size(params) == 0 ->
        {:ok, nil}

      %{"powrot_do" => raw_return_to} ->
        case parse_return_target(raw_return_to) do
          nil ->
            case InfrastructureNavigation.allowlisted_return_path(raw_return_to) do
              nil -> :error
              return_to -> {:ok, return_to}
            end

          return_target ->
            {:ok, return_target}
        end

      _ ->
        :error
    end
  end

  defp parse_month(%{"miesiac" => month}) do
    case Date.from_iso8601(month) do
      {:ok, parsed_month} -> {:ok, parsed_month}
      _ -> :error
    end
  end

  defp parse_month(_params), do: :error

  defp parse_filter(%{"filtr" => raw_filter}) do
    case QueryCodec.parse_filter(raw_filter) do
      nil -> :error
      filter -> {:ok, filter}
    end
  end

  defp parse_filter(_params), do: :error

  defp parse_subfilter(%{"podfiltr" => raw_subfilter}) do
    case QueryCodec.parse_subfilter(raw_subfilter) do
      nil -> :error
      subfilter -> {:ok, subfilter}
    end
  end

  defp parse_subfilter(_params), do: {:ok, nil}

  defp append_return_to(path, return_to) when is_binary(return_to) and return_to != "" do
    path <> "?" <> URI.encode_query(%{powrot_do: return_to})
  end

  defp append_return_to(path, _return_to), do: path

  defp normalize_return_to(return_to) when is_binary(return_to), do: return_to_path(return_to)
  defp normalize_return_to(return_to), do: return_target_path(return_to)

  defp encode_subfilter(nil), do: nil
  defp encode_subfilter(subfilter), do: QueryCodec.encode_subfilter(subfilter)
end
