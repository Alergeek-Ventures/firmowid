defmodule FirmowidWeb.Assistant.Utilities.Presentation do
  @moduledoc "Readable chat turns and authorized record previews for assistant decisions."
  use Gettext, backend: Firmowid.Gettext

  alias Ash.Error.Forbidden
  alias Ash.Error.Invalid
  alias AshAi.ChatUI.Tools
  alias Firmowid.Ash.Assistant
  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Finances
  alias Firmowid.Ash.Invoicing
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.Timetracker.Project
  alias FirmowidWeb.Invoicing.Utilities.Navigation
  alias FirmowidWeb.Management.Utilities.Navigation, as: ManagementNavigation

  @sales_tools ~w(connect_sales_invoice_transactions disconnect_sales_invoice_transactions)
  @cost_tools ~w(connect_cost_invoice_transactions disconnect_cost_invoice_transactions)

  @doc "Returns the same contextual prompt keys and text for display and submission."
  @spec suggestions(map() | nil) :: [{String.t(), String.t()}]
  def suggestions(%{type: "transaction"}) do
    [
      {"previous_month", gettext("This transaction paid several invoices from the previous month")},
      {"bulk_payment", gettext("This was a bulk payment for several documents")},
      {"different_name", gettext("The counterparty may appear under a different name on the invoices")}
    ]
  end

  def suggestions(%{type: type}) when type in ["sales_invoice", "cost_invoice"] do
    [
      {"previous_month", gettext("This invoice covers all transactions from the previous month")},
      {"different_name", gettext("The transaction for this invoice has a different counterparty name")},
      {"late_payment", gettext("The payment was made much later than the invoice was issued")}
    ]
  end

  def suggestions(%{type: type}) when type in ["employee", "project"], do: []

  def suggestions(nil) do
    [
      {"unmatched", gettext("Find transactions without an invoice")},
      {"skipped", gettext("Show skipped transactions")},
      {"matched", gettext("Check already matched payments")}
    ]
  end

  @doc "Names conversation status consistently in history and live announcements."
  @spec status_label(atom()) :: String.t()
  def status_label(:running), do: gettext("Assistant is working on your request.")
  def status_label(:awaiting_approval), do: gettext("A plan is ready for your decision.")
  def status_label(:failed), do: gettext("The response was interrupted.")
  def status_label(:idle), do: gettext("Assistant is ready.")

  @doc "Explains an interrupted response or a rejected action without leaking backend details."
  @spec failure_message(String.t()) :: String.t()
  def failure_message("access_revoked"), do: gettext("Your access changed. Refresh the page before continuing.")

  def failure_message(_code),
    do:
      gettext("Some changes may already have been saved. Ask me to check the current state before proposing a new plan.")

  @doc "Projects the canonical transcript, excluding provider reasoning."
  @spec turns(map()) :: [map()]
  def turns(conversation) do
    conversation.messages
    |> Enum.chunk_by(&(&1.role == :user))
    |> Enum.flat_map(fn
      [%{role: :user} | _] = messages ->
        Enum.map(messages, &%{"role" => "user", "text" => AshAi.Transcript.text(&1.parts)})

      messages ->
        [%{"role" => "assistant", "parts" => Enum.flat_map(messages, & &1.parts)}]
    end)
    |> Enum.with_index()
    |> Enum.map(fn {turn, index} -> turn(turn, "assistant-turn-#{conversation.id}-#{index}") end)
  end

  defp turn(%{"role" => "user", "text" => text}, id) do
    %{id: id, role: :user, text: text, html: nil, tools: []}
  end

  defp turn(%{"role" => "assistant", "parts" => parts}, id) do
    calls = Enum.filter(parts, &(&1["type"] == "tool_call"))
    results = Enum.filter(parts, &(&1["type"] == "tool_result"))
    {:ok, normalized} = Tools.extract(%{tool_calls: calls, tool_results: results})
    results_by_id = Map.new(normalized.tool_results, &{&1.id, &1})

    text =
      parts
      |> Enum.filter(&(&1["type"] == "text"))
      |> Enum.map_join("\n\n", & &1["text"])

    tools =
      Enum.map(normalized.tool_calls, fn call ->
        result = Map.get(results_by_id, call.id)
        payload = if result, do: decode_content(result.content)

        %{
          id: call.id,
          label: tool_label(call.name),
          status: result_status(result, payload),
          summary: result_summary(payload)
        }
      end)

    %{
      id: id,
      role: :assistant,
      text: text,
      html: markdown(text),
      tools: tools
    }
  end

  @doc "Loads the selected conversation subject with the current user's permissions."
  @spec subject(map(), Scope.t()) :: map() | nil
  def subject(%{subject: subject}, scope) when not is_nil(subject) do
    %{type: subject["type"], record: subject_record(subject, scope)}
  end

  def subject(_conversation, _scope), do: nil

  defp subject_record(%{"type" => "employee", "id" => id}, scope) do
    %{id: id}
    |> Core.get_org_user(scope: scope, load: [member: :display_name])
    |> subject_result(:employee)
  end

  defp subject_record(%{"type" => "project", "id" => id}, scope) do
    id |> Project.get(scope: scope) |> subject_result(:project)
  end

  defp subject_record(%{"type" => type, "id" => id}, scope) do
    kind =
      case type do
        "transaction" -> :transaction
        "sales_invoice" -> :sales
        "cost_invoice" -> :cost
      end

    case read_records(kind, [id], scope) do
      [record] -> record(kind, record)
      [] -> nil
    end
  end

  defp subject_result({:ok, record}, kind), do: record(kind, record)
  defp subject_result({:error, %Forbidden{}}, _kind), do: nil
  defp subject_result({:error, %Invalid{}}, _kind), do: nil
  defp subject_result({:error, error}, _kind), do: raise(Ash.Error.to_error_class(error))

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
  @spec plan(map(), Scope.t()) :: map()
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
          label: tool_label(call.name),
          records: preview_records(references, records)
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
      {:error, %Forbidden{}} -> []
      {:error, %Invalid{}} -> []
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

  defp record(:employee, employee) do
    %{
      label: employee.member.display_name,
      description: nil,
      amount: nil,
      amount_tone: nil,
      date: nil,
      path: ManagementNavigation.employee_path(employee.id),
      kind: gettext("Employee")
    }
  end

  defp record(:project, project) do
    %{
      label: project.name,
      description: nil,
      amount: nil,
      amount_tone: nil,
      date: nil,
      path: ManagementNavigation.project_path(project.id),
      kind: gettext("Project")
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

  defp tool_label("list_transactions"), do: gettext("Search transactions")
  defp tool_label("list_sales_invoices"), do: gettext("Search sales invoices")
  defp tool_label("list_cost_invoices"), do: gettext("Search cost invoices")
  defp tool_label("suggest_transaction_invoices"), do: gettext("Find matching invoices")
  defp tool_label("suggest_sales_invoice_transactions"), do: gettext("Find invoice payments")
  defp tool_label("suggest_cost_invoice_transactions"), do: gettext("Find invoice payments")
  defp tool_label("connect_sales_invoice_transactions"), do: gettext("Connect invoice payments")
  defp tool_label("connect_cost_invoice_transactions"), do: gettext("Connect invoice payments")

  defp tool_label("disconnect_sales_invoice_transactions"), do: gettext("Disconnect invoice payments")

  defp tool_label("disconnect_cost_invoice_transactions"), do: gettext("Disconnect invoice payments")

  defp tool_label("restore_transaction_for_matching"), do: gettext("Restore a skipped transaction")

  defp tool_label("list_monthly_salaries"), do: gettext("Search monthly salaries")
  defp tool_label("suggest_transaction_salaries"), do: gettext("Find a matching salary")
  defp tool_label(_name), do: gettext("Unknown operation")
end
