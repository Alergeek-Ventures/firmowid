defmodule FirmowidWeb.Invoicing.Navigation do
  @moduledoc """
  Central navigation contract for invoicing return paths.
  """

  use FirmowidWeb, :verified_routes

  alias Firmowid.Ash.Finances.Transaction
  alias Firmowid.Ash.Invoicing.CostInvoice
  alias Firmowid.Ash.Invoicing.SalesInvoice

  @type filter :: :all | :invoices | :transactions | :unmatched
  @type subfilter :: :oplacone | :nieoplacone | :dopasowane | :bez_dokumentu
  @type view_mode :: :dashboard | :list
  @type invoicing_index_target :: %{
          month: Date.t(),
          filter: filter(),
          subfilter: subfilter() | nil,
          view_mode: view_mode()
        }
  @type return_target ::
          {:invoicing_index, invoicing_index_target()}
          | :last_sales_invoices
          | {:transaction_show, Ash.UUID.t(), return_target() | nil}
  @type return_destination :: return_target() | String.t() | nil

  @doc """
  Builds the canonical invoicing index path for the given params.
  """
  @spec invoicing_index_path(%{
          month: Date.t(),
          filter: filter(),
          subfilter: subfilter() | nil,
          view_mode: view_mode()
        }) :: String.t()
  def invoicing_index_path(%{month: month, filter: filter, subfilter: subfilter, view_mode: view_mode}) do
    query =
      Enum.reject(
        [
          month: month |> Date.beginning_of_month() |> Date.to_iso8601(),
          filter: Atom.to_string(filter),
          subfilter: subfilter && Atom.to_string(subfilter),
          view: view_mode == :list && "list"
        ],
        fn {_key, value} -> is_nil(value) or value == false end
      )

    ~p"/fakturowanie?#{query}"
  end

  @doc """
  Builds the canonical path to the recent sales invoices tab.
  """
  @spec last_sales_invoices_path() :: String.t()
  def last_sales_invoices_path, do: ~p"/sprzedazowe?#{[tab: "last_invoices"]}"

  @doc """
  Builds the default invoicing return target for a given date.
  """
  @spec default_invoicing_target(Date.t()) :: return_target()
  def default_invoicing_target(date) do
    {:invoicing_index, %{month: date, filter: :all, subfilter: nil, view_mode: :dashboard}}
  end

  @doc """
  Builds the default invoicing return path for a given date.
  """
  @spec default_invoicing_path(Date.t()) :: String.t()
  def default_invoicing_path(date), do: return_target_path(default_invoicing_target(date))

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
      return_target_path(nested_return_target)
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
    raw_return_to
    |> parse_return_target()
    |> return_target_path()
  end

  def return_to_path(_raw_return_to), do: nil

  defp resolve_allowlisted_target("/fakturowanie", query), do: resolve_invoicing_index_target(query)

  defp resolve_allowlisted_target("/sprzedazowe", query), do: resolve_last_sales_invoices_target(query)

  defp resolve_allowlisted_target(path, query), do: resolve_transaction_show_target(path, query)

  defp resolve_invoicing_index_target(query) do
    params = URI.decode_query(query || "")

    with true <- Enum.all?(Map.keys(params), &(&1 in ["month", "filter", "subfilter", "view"])),
         {:ok, month} <- parse_month(params),
         {:ok, filter} <- parse_filter(params),
         {:ok, subfilter} <- parse_subfilter(params),
         {:ok, view_mode} <- parse_view_mode(params) do
      {:ok,
       {:invoicing_index,
        %{
          month: month,
          filter: filter,
          subfilter: subfilter,
          view_mode: view_mode
        }}}
    else
      _ -> :error
    end
  end

  defp resolve_last_sales_invoices_target(query) do
    case URI.decode_query(query || "") do
      %{"tab" => "last_invoices"} -> {:ok, :last_sales_invoices}
      _ -> :error
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

      %{"return_to" => raw_return_to} ->
        case parse_return_target(raw_return_to) do
          nil -> :error
          return_target -> {:ok, return_target}
        end

      _ ->
        :error
    end
  end

  defp parse_month(%{"month" => month}) do
    case Date.from_iso8601(month) do
      {:ok, parsed_month} -> {:ok, parsed_month}
      _ -> :error
    end
  end

  defp parse_month(_params), do: :error

  defp parse_filter(%{"filter" => "all"}), do: {:ok, :all}
  defp parse_filter(%{"filter" => "invoices"}), do: {:ok, :invoices}
  defp parse_filter(%{"filter" => "transactions"}), do: {:ok, :transactions}
  defp parse_filter(%{"filter" => "unmatched"}), do: {:ok, :unmatched}
  defp parse_filter(_params), do: :error

  defp parse_subfilter(%{"subfilter" => "oplacone"}), do: {:ok, :oplacone}
  defp parse_subfilter(%{"subfilter" => "nieoplacone"}), do: {:ok, :nieoplacone}
  defp parse_subfilter(%{"subfilter" => "dopasowane"}), do: {:ok, :dopasowane}
  defp parse_subfilter(%{"subfilter" => "bez_dokumentu"}), do: {:ok, :bez_dokumentu}
  defp parse_subfilter(%{"subfilter" => _invalid_subfilter}), do: :error
  defp parse_subfilter(_params), do: {:ok, nil}

  defp parse_view_mode(%{"view" => "list"}), do: {:ok, :list}
  defp parse_view_mode(%{"view" => _invalid_view}), do: :error
  defp parse_view_mode(_params), do: {:ok, :dashboard}

  defp append_return_to(path, return_to) when is_binary(return_to) and return_to != "" do
    path <> "?" <> URI.encode_query(%{return_to: return_to})
  end

  defp append_return_to(path, _return_to), do: path

  defp normalize_return_to(return_to) when is_binary(return_to), do: return_to_path(return_to)
  defp normalize_return_to(return_to), do: return_target_path(return_to)
end
