defmodule FirmowidWeb.Assistant.Utilities.Presentation do
  @moduledoc "Readable chat turns and authorized record previews for assistant decisions."
  use Gettext, backend: Firmowid.Gettext

  alias Ash.Error.Forbidden
  alias Ash.Error.Invalid
  alias AshAi.ChatUI.Tools
  alias Firmowid.Assistant
  alias Firmowid.Core
  alias Firmowid.Finances
  alias Firmowid.Invoicing
  alias Firmowid.Scope
  alias Firmowid.Timetracker.Project
  alias Firmowid.Timetracker.Session
  alias FirmowidWeb.Assistant.Utilities.Changes
  alias FirmowidWeb.Invoicing.Utilities.Navigation
  alias FirmowidWeb.Management.Utilities.Navigation, as: ManagementNavigation

  require Ash.Query

  @sales_tools ~w(connect_sales_invoice_transactions disconnect_sales_invoice_transactions)
  @invoice_previews ~w(preview_sales_invoice preview_sales_invoice_correction)
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

  # Fixed scenarios the current tools answer.
  def suggestions(nil) do
    for tile <- tiles(), do: {tile.key, tile.question}
  end

  @doc "Returns the empty screen's suggestion tiles: a question, one line of context and the prompt sent."
  @spec tiles() :: [
          %{key: String.t(), title: String.t(), context: String.t(), question: String.t()}
        ]
  def tiles do
    [
      %{
        key: "overdue",
        title: gettext("Which sales invoices are overdue?"),
        context: gettext("Unpaid, oldest first"),
        question:
          gettext("Show unpaid sales invoices past their due date, oldest first, with how many days each is overdue.")
      },
      %{
        key: "accountant",
        title: gettext("Which transfers will the accountant ask about?"),
        context: gettext("Payments without a cost invoice"),
        question: gettext("Find outgoing transfers from the last three months that have no cost invoice.")
      },
      %{
        key: "fixed_costs",
        title: gettext("How have fixed costs changed?"),
        context: gettext("The last three months by category"),
        question: gettext("Compare fixed costs from the last three months by category and tell me what went up.")
      },
      %{
        key: "projects",
        title: gettext("Which projects earn money and which lose it?"),
        context: gettext("Revenue against team costs"),
        question: gettext("Compare revenue and team costs per project over the last three months.")
      }
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
    %{id: id, role: :user, text: text}
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
          name: call.name,
          arguments: call.arguments,
          label: tool_label(call.name),
          status: result_status(result, payload),
          summary: result_summary(payload),
          count: result_count(payload)
        }
      end)

    %{
      id: id,
      role: :assistant,
      text: text,
      blocks: blocks(text, id),
      tools: tools,
      steps: steps(tools),
      invoices: for(%{name: name, status: :done} = tool <- tools, name in @invoice_previews, do: tool.id)
    }
  end

  @doc """
  Returns the invoice and correction previews the transcript shows as invoice cards, keyed by
  tool call: each previewed call becomes one confirmation.
  """
  @spec invoice_previews([map()]) :: [
          %{id: String.t(), kind: :invoice | :correction, arguments: map()}
        ]
  def invoice_previews(turns) do
    for %{role: :assistant, tools: tools} <- turns,
        %{name: name, status: :done} = tool <- tools,
        name in @invoice_previews do
      kind = if name == "preview_sales_invoice_correction", do: :correction, else: :invoice
      %{id: tool.id, kind: kind, arguments: tool.arguments}
    end
  end

  @doc """
  Derives the ID the confirmed invoice is issued with from the conversation and the tool call, so
  the card finds the issued document again after a reload instead of offering to issue it twice.
  A UUIDv7 with the conversation's timestamp and the rest taken from a hash.
  """
  @spec confirmation_id(String.t(), String.t()) :: String.t()
  def confirmation_id(conversation_id, call_id) do
    <<timestamp::48, _rest::80>> = Ecto.UUID.dump!(conversation_id)
    <<rand_a::12, rand_b::62, _::182>> = :crypto.hash(:sha256, conversation_id <> call_id)
    Ecto.UUID.load!(<<timestamp::48, 7::4, rand_a::12, 2::2, rand_b::62>>)
  end

  # One sentence about what was looked at, in the user's terms, and one line per step. Calls
  # waiting for approval are on the approval card, not steps.
  defp steps(tools) do
    tools |> Enum.reject(&(&1.status == :pending)) |> taken_steps()
  end

  defp taken_steps([]), do: nil

  defp taken_steps(tools) do
    items =
      tools
      |> Enum.filter(&(&1.status == :done and &1.count != nil))
      |> Enum.group_by(& &1.name, & &1.count)
      |> Enum.flat_map(fn {name, counts} -> List.wrap(reviewed(name, Enum.sum(counts))) end)

    failed = Enum.count(tools, &(&1.status in [:error, :unknown]))

    %{
      summary:
        if(items == [],
          do: ngettext("Took %{count} step", "Took %{count} steps", length(tools)),
          else: gettext("Reviewed %{items}", items: join_items(items))
        ),
      failure: if(failed > 0, do: ngettext("%{count} step failed", "%{count} steps failed", failed)),
      lines:
        Enum.map(
          tools,
          &%{id: &1.id, label: &1.label, result: tool_status_label(&1.status, &1.summary)}
        )
    }
  end

  defp join_items([item]), do: item

  defp join_items(items) do
    {init, [last]} = Enum.split(items, -1)
    gettext("%{items} and %{last}", items: Enum.join(init, ", "), last: last)
  end

  defp reviewed("list_transactions", n), do: ngettext("%{count} bank transaction", "%{count} bank transactions", n)

  defp reviewed("list_sales_invoices", n), do: ngettext("%{count} sales invoice", "%{count} sales invoices", n)

  defp reviewed("list_cost_invoices", n), do: ngettext("%{count} cost invoice", "%{count} cost invoices", n)

  defp reviewed("suggest_transaction_invoices", n),
    do: ngettext("%{count} candidate invoice", "%{count} candidate invoices", n)

  defp reviewed(name, n) when name in ["suggest_sales_invoice_transactions", "suggest_cost_invoice_transactions"],
    do: ngettext("%{count} candidate payment", "%{count} candidate payments", n)

  defp reviewed("list_monthly_salaries", n), do: ngettext("%{count} monthly salary", "%{count} monthly salaries", n)

  defp reviewed("suggest_transaction_salaries", n),
    do: ngettext("%{count} candidate salary", "%{count} candidate salaries", n)

  defp reviewed("list_counterparties", n), do: ngettext("%{count} counterparty", "%{count} counterparties", n)

  defp reviewed("list_sessions", n), do: ngettext("%{count} work session", "%{count} work sessions", n)

  defp reviewed("list_leave_requests", n), do: ngettext("%{count} leave request", "%{count} leave requests", n)

  defp reviewed("list_projects", n), do: ngettext("%{count} project", "%{count} projects", n)

  defp reviewed("list_analysis_entries", n), do: ngettext("%{count} analysis entry", "%{count} analysis entries", n)

  defp reviewed("list_analysis_tags", n), do: ngettext("%{count} analysis tag", "%{count} analysis tags", n)

  defp reviewed(_name, _n), do: nil

  defp tool_status_label(:done, nil), do: gettext("Completed")
  defp tool_status_label(:done, summary), do: summary
  defp tool_status_label(:pending, _summary), do: gettext("Waiting")
  defp tool_status_label(:denied, _summary), do: gettext("Not performed")
  defp tool_status_label(:unknown, _summary), do: gettext("Check the result")
  defp tool_status_label(:error, _summary), do: gettext("Error")

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

  # A list longer than this shows its first @visible_records rows and expands in place.
  @collapsed_after 10
  @visible_records 8

  # Markdown tables with a record per row (see the prompt) become dense record rows and a task
  # list of candidates becomes a pick list; the rest of the answer stays sanitized HTML. Wider
  # tables are comparisons and keep their columns.
  defp blocks(text, id) do
    text
    |> MDEx.parse_document!(extension: [table: true, strikethrough: true, tasklist: true])
    |> Map.fetch!(:nodes)
    |> Enum.chunk_by(&block_kind/1)
    |> Enum.with_index()
    |> Enum.flat_map(fn {nodes, index} ->
      case block_kind(hd(nodes)) do
        :html ->
          [{:html, html(nodes)}]

        kind ->
          nodes
          |> Enum.with_index()
          |> Enum.map(fn {node, nth} ->
            structured(kind, node, "#{id}-#{kind}-#{index}-#{nth}")
          end)
      end
    end)
  end

  defp block_kind(%MDEx.Table{nodes: [%{nodes: cells} | _]}) do
    if length(cells) <= 4, do: :records, else: :html
  end

  defp block_kind(%MDEx.List{is_task_list: true, nodes: items}) do
    if Enum.all?(items, &(length(candidate_cells(&1)) == 5)), do: :pick, else: :html
  end

  defp block_kind(_node), do: :html

  defp structured(:records, table, id), do: {:records, records(table, id)}

  defp structured(:pick, list, id), do: {:pick, %{id: id, candidates: Enum.map(list.nodes, &candidate/1)}}

  # A candidate is "date | counterparty | title | evidence | amount"; caveats in the evidence are
  # emphasized (see the prompt).
  defp candidate(item) do
    [date, who, title, evidence, amount] = Enum.map(candidate_cells(item), &trim_cell/1)

    %{
      date: html(date),
      counterparty: html(who),
      title: html(title),
      evidence: html(evidence),
      amount: html(amount),
      amount_tone: amount_tone(plain_text(%{nodes: amount}), links(item.nodes)),
      choice: Enum.map_join([date, who, amount], " · ", &plain_text(%{nodes: &1}))
    }
  end

  defp candidate_cells(%MDEx.TaskItem{nodes: [%MDEx.Paragraph{nodes: nodes}]}) do
    nodes
    |> Enum.flat_map(fn
      %MDEx.Text{literal: literal} = text ->
        literal
        |> String.split("|")
        |> Enum.map_intersperse(:cell, &%{text | literal: &1})

      node ->
        [node]
    end)
    |> Enum.chunk_by(&(&1 == :cell))
    |> Enum.reject(&(&1 == [:cell]))
  end

  defp candidate_cells(_item), do: []

  # Trims the spaces around the separators, keeping those between the cell's own nodes.
  defp trim_cell(nodes) do
    nodes
    |> List.update_at(0, &trim_text(&1, :leading))
    |> List.update_at(-1, &trim_text(&1, :trailing))
    |> Enum.reject(&match?(%MDEx.Text{literal: ""}, &1))
  end

  defp trim_text(%MDEx.Text{literal: literal} = text, :leading), do: %{text | literal: String.trim_leading(literal)}

  defp trim_text(%MDEx.Text{literal: literal} = text, :trailing), do: %{text | literal: String.trim_trailing(literal)}

  defp trim_text(node, _side), do: node

  defp records(table, id) do
    rows =
      for %MDEx.TableRow{header: false, nodes: cells} <- table.nodes do
        [title | rest] = cells
        {meta, amount} = if rest == [], do: {[], nil}, else: Enum.split(rest, -1)
        amount = amount && hd(amount)

        %{
          title: html(title.nodes),
          meta: meta |> Enum.reject(&(plain_text(&1) == "")) |> Enum.map(&html(&1.nodes)),
          amount: amount && html(amount.nodes),
          amount_tone: amount && amount_tone(plain_text(amount), links(cells))
        }
      end

    %{
      id: id,
      rows: rows,
      collapse?: length(rows) > @collapsed_after,
      visible: @visible_records
    }
  end

  # Costs are written with a minus (see the prompt); a link to a cost invoice also marks one.
  defp amount_tone(amount, links) do
    cond do
      not Regex.match?(~r/\d/u, amount) or
          not Regex.match?(~r/zł|PLN|EUR|USD|GBP|CHF|€|\$|£/u, amount) ->
        nil

      String.starts_with?(amount, ["-", "−", "–"]) ->
        :expense

      Enum.any?(links, &String.contains?(&1, "/kosztowe/")) ->
        :expense

      true ->
        :income
    end
  end

  defp plain_text(%{literal: literal}) when is_binary(literal), do: literal
  defp plain_text(%{nodes: nodes}), do: nodes |> Enum.map_join(&plain_text/1) |> String.trim()
  defp plain_text(_node), do: ""

  defp links(nodes) when is_list(nodes), do: Enum.flat_map(nodes, &links/1)
  defp links(%MDEx.Link{url: url} = link), do: [url | links(link.nodes)]
  defp links(%{nodes: nodes}), do: links(nodes)
  defp links(_node), do: []

  # sobelow_skip ["XSS.Raw"]
  # Model text is untrusted: MDEx omits raw HTML and Ammonia sanitizes the generated HTML.
  defp html(nodes) do
    %MDEx.Document{nodes: nodes}
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

    calls = Enum.map(calls, &call_changes(&1, scope))

    references =
      calls
      |> Enum.flat_map(fn
        {_call, {:ok, references}, _changes} -> references
        {_call, _unavailable, _changes} -> []
      end)
      |> Enum.uniq()

    records = load_records(references, scope)

    previews =
      Enum.map(calls, fn {call, references, changes} ->
        %{
          id: call.id,
          label: tool_label(call.name),
          records: preview_records(references, records),
          changes: changes,
          unchanged?: references == :unchanged
        }
      end)

    readable? = Enum.all?(previews, &Enum.all?(&1.records))

    %{
      available?: readable? and not Enum.any?(previews, & &1.unchanged?),
      readable?: readable?,
      calls: previews
    }
  end

  # Writes that change fields show them before and after; links show only the linked records.
  defp call_changes(call, scope) do
    if Changes.covers?(call.name) do
      case Changes.preview(call, scope) do
        {:ok, references, changes} -> {call, {:ok, references}, changes}
        failure -> {call, failure, []}
      end
    else
      {call, references(call), []}
    end
  end

  defp preview_records({:ok, references}, records), do: Enum.map(references, &Map.get(records, &1))

  defp preview_records(:error, _records), do: [nil]
  defp preview_records(:unchanged, _records), do: []

  defp references(%{name: name, arguments: %{"id" => id, "input" => %{"transaction_ids" => ids}}})
       when name in @sales_tools and is_list(ids) do
    {:ok, [{:sales, id} | Enum.map(ids, &{:transaction, &1})]}
  end

  defp references(%{name: name, arguments: %{"id" => id, "input" => %{"transaction_ids" => ids}}})
       when name in @cost_tools and is_list(ids) do
    {:ok, [{:cost, id} | Enum.map(ids, &{:transaction, &1})]}
  end

  defp references(%{name: "restore_transaction_for_matching", arguments: %{"id" => id}}), do: {:ok, [{:transaction, id}]}

  defp references(%{
         name: "link_sales_invoice_counterparty",
         arguments: %{"id" => id, "input" => %{"counterparty_id" => counterparty_id}}
       }), do: {:ok, [{:sales, id}, {:counterparty, counterparty_id}]}

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

  defp read_records(:counterparty, ids, scope) do
    query = Ash.Query.filter(Firmowid.Invoicing.Counterparty, id in ^ids)

    case Invoicing.list_counterparties(%{status: :all},
           scope: scope,
           query: query,
           load: [:display_label]
         ) do
      {:ok, records} -> records
      {:error, %Forbidden{}} -> []
      {:error, %Invalid{}} -> []
      {:error, error} -> raise Ash.Error.to_error_class(error)
    end
  end

  defp read_records(:project, ids, scope) do
    Enum.flat_map(ids, &(&1 |> Project.get(scope: scope) |> found()))
  end

  defp read_records(:session, ids, scope) do
    Enum.flat_map(
      ids,
      &(&1 |> Session.current_session(scope: scope, load: [:project]) |> found())
    )
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

  defp found({:ok, record}), do: [record]
  defp found({:error, %Forbidden{}}), do: []
  defp found({:error, %Invalid{}}), do: []
  defp found({:error, error}), do: raise(Ash.Error.to_error_class(error))

  defp record(:session, session) do
    minutes =
      session.end_datetime && DateTime.diff(session.end_datetime, session.start_datetime, :minute)

    %{
      label: (session.project && session.project.name) || gettext("Work session"),
      description: session.title,
      amount:
        minutes &&
          "#{div(minutes, 60)}:#{String.pad_leading(to_string(rem(minutes, 60)), 2, "0")}",
      amount_tone: nil,
      date: DateTime.to_date(session.start_datetime),
      path: nil,
      kind: gettext("Work session")
    }
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

  defp record(:counterparty, counterparty) do
    %{
      label: counterparty.display_label,
      description:
        Enum.join(
          Enum.reject([counterparty.full_name, counterparty.tax_id], &(&1 in [nil, ""])),
          " · "
        ),
      amount: nil,
      amount_tone: nil,
      date: nil,
      path: ManagementNavigation.counterparty_path(counterparty.id),
      kind: gettext("Counterparty")
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

  defp result_count(%{"results" => results}) when is_list(results), do: length(results)
  defp result_count(_payload), do: nil

  defp tool_label("list_transactions"), do: gettext("Search transactions")
  defp tool_label("list_sales_invoices"), do: gettext("Search sales invoices")
  defp tool_label("list_cost_invoices"), do: gettext("Search cost invoices")
  defp tool_label("suggest_transaction_invoices"), do: gettext("Find matching invoices")
  defp tool_label("suggest_sales_invoice_transactions"), do: gettext("Find invoice payments")
  defp tool_label("suggest_cost_invoice_transactions"), do: gettext("Find invoice payments")
  defp tool_label("connect_sales_invoice_transactions"), do: gettext("Link invoice payments")
  defp tool_label("connect_cost_invoice_transactions"), do: gettext("Link invoice payments")

  defp tool_label("disconnect_sales_invoice_transactions"), do: gettext("Unlink invoice payments")

  defp tool_label("disconnect_cost_invoice_transactions"), do: gettext("Unlink invoice payments")

  defp tool_label("restore_transaction_for_matching"), do: gettext("Restore a skipped transaction")

  defp tool_label("get_ksef_connection_status"), do: gettext("Check the KSeF connection")
  defp tool_label("get_next_sales_invoice_number"), do: gettext("Find the next invoice number")
  defp tool_label("wait_for_ksef_submissions"), do: gettext("Wait for KSeF")
  defp tool_label("list_monthly_salaries"), do: gettext("Search monthly salaries")
  defp tool_label("suggest_transaction_salaries"), do: gettext("Find a matching salary")
  defp tool_label("list_counterparties"), do: gettext("Search counterparties")

  defp tool_label("link_sales_invoice_counterparty"), do: gettext("Link the invoice to a counterparty")

  defp tool_label("list_sessions"), do: gettext("Search work sessions")
  defp tool_label("get_current_session"), do: gettext("Check the running work session")
  defp tool_label("list_leave_requests"), do: gettext("Search leave requests")
  defp tool_label("get_shared_birthday"), do: gettext("Check your shared birthday")
  defp tool_label("list_projects"), do: gettext("Search projects")
  defp tool_label("get_sales_invoice"), do: gettext("Open a sales invoice")
  defp tool_label("preview_sales_invoice"), do: gettext("Check invoice details")
  defp tool_label("preview_sales_invoice_correction"), do: gettext("Check correction details")
  defp tool_label("list_analysis_entries"), do: gettext("Search analysis entries")
  defp tool_label("list_analysis_tags"), do: gettext("Search analysis tags")

  defp tool_label("update_sales_invoice_internal_note"), do: gettext("Change the sales invoice note")

  defp tool_label("update_cost_invoice_internal_note"), do: gettext("Change the cost invoice note")

  defp tool_label("update_transaction_internal_note"), do: gettext("Change the transaction note")
  defp tool_label("connect_transaction_salary"), do: gettext("Assign the transfer to a salary")

  defp tool_label("disconnect_transaction_salary"), do: gettext("Unassign the transfer from a salary")

  defp tool_label("set_analysis_entry_category"), do: gettext("Set the analysis category")

  defp tool_label("set_analysis_entry_project_tags"), do: gettext("Assign projects in the analysis")

  defp tool_label("start_session"), do: gettext("Start a work session")
  defp tool_label("stop_current_session"), do: gettext("Stop the work session")
  defp tool_label("edit_session"), do: gettext("Edit a work session")
  defp tool_label("add_sessions"), do: gettext("Add work sessions")
  defp tool_label("create_leave_request"), do: gettext("Request leave")
  defp tool_label("update_profile"), do: gettext("Update your profile")
  defp tool_label("create_sales_invoice_draft"), do: gettext("Save an invoice draft")
  defp tool_label("update_sales_invoice_draft"), do: gettext("Update the invoice draft")
  defp tool_label(_name), do: gettext("Unknown operation")
end
