defmodule FirmowidWeb.Assistant.Utilities.Presentation do
  @moduledoc "Readable chat turns and authorized record previews for assistant decisions."
  use Gettext, backend: Firmowid.Gettext

  alias AshAi.ChatUI.Tools
  alias Firmowid.Ash.Assistant
  alias Firmowid.Ash.Finances
  alias Firmowid.Ash.Invoicing
  alias FirmowidWeb.Invoicing.Utilities.Navigation

  @sales_tools ~w(connect_sales_invoice_transactions disconnect_sales_invoice_transactions)
  @cost_tools ~w(connect_cost_invoice_transactions disconnect_cost_invoice_transactions)

  @doc "Projects the canonical transcript, excluding provider reasoning."
  @spec turns(map()) :: [map()]
  def turns(conversation) do
    conversation.transcript
    |> Enum.with_index()
    |> Enum.map(fn {turn, index} -> turn(turn, index) end)
  end

  defp turn(%{"role" => "user", "text" => text}, index) do
    %{id: "assistant-turn-#{index}", role: :user, text: text, html: nil, tools: []}
  end

  defp turn(%{"role" => "assistant", "parts" => parts}, index) do
    calls = Enum.filter(parts, &(&1["type"] == "tool_call"))
    results = Enum.filter(parts, &(&1["type"] == "tool_result"))
    {:ok, normalized} = Tools.extract(%{tool_calls: calls, tool_results: results})
    by_id = Map.new(normalized.tool_results, &{&1.id, &1})

    text =
      parts
      |> Enum.filter(&(&1["type"] == "text"))
      |> Enum.map_join("\n\n", & &1["text"])

    tools =
      Enum.map(normalized.tool_calls, fn call ->
        result = Map.get(by_id, call.id)
        payload = if result, do: decode_content(result.content)

        %{
          id: call.id,
          label: label(call.name),
          status: result_status(result, payload),
          summary: result_summary(payload),
          details: details(%{arguments: call.arguments, result: payload})
        }
      end)

    %{
      id: "assistant-turn-#{index}",
      role: :assistant,
      text: text,
      html: markdown(text),
      tools: tools
    }
  end

  # sobelow_skip ["XSS.Raw"]
  # Model text is untrusted: MDEx omits raw HTML and Ammonia sanitizes the generated HTML.
  defp markdown(text) do
    text
    |> MDEx.to_html!(
      extension: [table: true, strikethrough: true],
      render: [unsafe: false],
      sanitize: MDEx.Document.default_sanitize_options()
    )
    |> Phoenix.HTML.raw()
  end

  @doc "Builds the decision preview from tool arguments and records read with the user's scope."
  @spec plan(map(), Firmowid.Ash.Scope.t()) :: map()
  def plan(conversation, scope) do
    {:ok, %{tool_calls: calls}} =
      Tools.extract(%{tool_calls: Assistant.pending_calls(conversation)})

    calls = Enum.map(calls, &{&1, references(&1)})

    references =
      calls
      |> Enum.flat_map(fn
        {_call, {:ok, references}} -> references
        {_call, :error} -> []
      end)
      |> Enum.uniq()

    records = load_records(references, scope)

    previews =
      Enum.map(calls, fn {call, references} ->
        %{
          id: call.id,
          label: label(call.name),
          records: preview_records(references, records),
          details: details(call.arguments)
        }
      end)

    %{available?: Enum.all?(previews, &Enum.all?(&1.records)), calls: previews}
  end

  defp preview_records({:ok, references}, records), do: Enum.map(references, &Map.get(records, &1))

  defp preview_records(:error, _records), do: [nil]

  defp references(%{name: name, arguments: %{"id" => id, "input" => %{"transaction_ids" => ids}}})
       when name in @sales_tools and is_list(ids) do
    {:ok, [{:sales, id} | Enum.map(ids, &{:transaction, &1})]}
  end

  defp references(%{name: name, arguments: %{"id" => id, "input" => %{"transaction_ids" => ids}}})
       when name in @cost_tools and is_list(ids) do
    {:ok, [{:cost, id} | Enum.map(ids, &{:transaction, &1})]}
  end

  defp references(%{name: "restore_transaction_for_matching", arguments: %{"id" => id}}), do: {:ok, [{:transaction, id}]}

  # ToolLoop requests approval before validating the tool name and arguments.
  # A malformed call must remain rejectable, but cannot produce an approvable preview.
  defp references(_call), do: :error

  defp load_records(references, scope) do
    references
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.flat_map(fn {kind, ids} ->
      kind |> read_records(ids, scope) |> Enum.map(&{{kind, &1.id}, record(kind, &1)})
    end)
    |> Map.new()
  end

  defp read_records(kind, ids, scope) do
    {read, loads} =
      case kind do
        :sales ->
          {&Invoicing.list_sales_invoices/2, [:effective_amount, :buyer_display_name_label]}

        :cost ->
          {&Invoicing.list_cost_invoices/2, [:effective_amount, :effective_seller_display_name]}

        :transaction ->
          {&Finances.list_transactions/2, [:counterparty_display_name, :direction]}
      end

    case read.(%{ids: ids}, scope: scope, page: false, load: loads) do
      {:ok, records} -> records
      {:error, %Ash.Error.Forbidden{}} -> []
      {:error, %Ash.Error.Invalid{}} -> []
      {:error, error} -> raise Ash.Error.to_error_class(error)
    end
  end

  defp record(:sales, invoice) do
    %{
      label: invoice.invoice_number || gettext("Draft invoice"),
      description: invoice.buyer_display_name_label,
      amount: invoice.effective_amount,
      amount_tone: :income,
      date: invoice.issue_date,
      path: Navigation.sales_invoice_show_path(invoice),
      kind: gettext("Sales invoice")
    }
  end

  defp record(:cost, invoice) do
    %{
      label: invoice.invoice_identifier || gettext("Cost invoice"),
      description: invoice.effective_seller_display_name,
      amount: invoice.effective_amount,
      amount_tone: :expense,
      date: invoice.issue_date,
      path: Navigation.cost_invoice_show_path(invoice),
      kind: gettext("Cost invoice")
    }
  end

  defp record(:transaction, transaction) do
    %{
      label: transaction.counterparty_display_name || gettext("Bank transaction"),
      description: transaction.remittance_information_unstructured,
      amount: transaction.amount,
      amount_tone: transaction.direction,
      date: transaction.booking_date,
      path: Navigation.transaction_show_path(transaction),
      kind: gettext("Bank transaction")
    }
  end

  defp decode_content(content) when is_binary(content) do
    case Jason.decode(content) do
      {:ok, decoded} -> decoded
      {:error, _} -> content
    end
  end

  defp decode_content(content), do: content
  defp result_status(nil, _payload), do: :pending
  defp result_status(_result, %{"errors" => [_ | _]}), do: :error

  defp result_status(_result, %{"error" => error}) when is_binary(error) do
    cond do
      String.contains?(error, "Outcome unknown") -> :unknown
      String.contains?(String.downcase(error), ["denied", "not run"]) -> :denied
      true -> :error
    end
  end

  defp result_status(_result, %{"error" => _}), do: :error
  defp result_status(%{is_error: true}, _payload), do: :error
  defp result_status(_result, _payload), do: :done

  defp result_summary(%{"results" => results}) when is_list(results) do
    ngettext("%{count} result", "%{count} results", length(results))
  end

  defp result_summary(_payload), do: nil

  defp details(value), do: value |> Jason.encode!(pretty: true) |> String.slice(0, 6000)

  @doc "Human names for the assistant's allowlisted tools."
  @spec label(String.t()) :: String.t()
  def label("list_transactions"), do: gettext("Search transactions")
  def label("list_sales_invoices"), do: gettext("Search sales invoices")
  def label("list_cost_invoices"), do: gettext("Search cost invoices")
  def label("suggest_transaction_invoices"), do: gettext("Find matching invoices")
  def label("suggest_sales_invoice_transactions"), do: gettext("Find invoice payments")
  def label("suggest_cost_invoice_transactions"), do: gettext("Find invoice payments")
  def label("connect_sales_invoice_transactions"), do: gettext("Connect invoice payments")
  def label("connect_cost_invoice_transactions"), do: gettext("Connect invoice payments")
  def label("disconnect_sales_invoice_transactions"), do: gettext("Disconnect invoice payments")
  def label("disconnect_cost_invoice_transactions"), do: gettext("Disconnect invoice payments")
  def label("restore_transaction_for_matching"), do: gettext("Restore a skipped transaction")
  def label("list_monthly_salaries"), do: gettext("Search monthly salaries")
  def label("suggest_transaction_salaries"), do: gettext("Find a matching salary")
  def label(_name), do: gettext("Unknown operation")
end
