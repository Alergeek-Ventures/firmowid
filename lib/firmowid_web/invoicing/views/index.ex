defmodule FirmowidWeb.Invoicing.Views.Index do
  @moduledoc false
  # TODO: move business logic (transaction grouping by party, get_active_months)
  # to domain actions/calculations — LiveView should only handle presentation
  use FirmowidWeb, :live_view

  import FirmowidWeb.Core.PubSubDebounce

  alias Ash.Notifier.Notification
  alias Firmowid.Ash.Blobs
  alias Firmowid.Ash.Blobs.Blob
  alias Firmowid.Ash.Finances
  alias Firmowid.Ash.Finances.Requisition
  alias Firmowid.Ash.Finances.Transaction
  alias Firmowid.Ash.Invoicing
  alias Firmowid.Ash.Invoicing.CostInvoice
  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Ash.Invoicing.TransactionGroup
  alias Firmowid.Ash.Ksef
  alias FirmowidWeb.Core.Endpoint
  alias Phoenix.Socket.Broadcast

  require Ash.Query

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    organization_id = user.organization_id

    if connected?(socket) do
      # Ash PubSub — invoicing resources
      Endpoint.subscribe("blob:created:#{organization_id}")
      Endpoint.subscribe("blob:updated:#{organization_id}")
      Endpoint.subscribe("blob:destroyed:#{organization_id}")
      Endpoint.subscribe("cost_invoice:created:#{organization_id}")
      Endpoint.subscribe("cost_invoice:updated:#{organization_id}")
      Endpoint.subscribe("sales_invoice:created:#{organization_id}")
      Endpoint.subscribe("sales_invoice:updated:#{organization_id}")
      Endpoint.subscribe("sales_invoice:destroyed:#{organization_id}")
      # Ash PubSub — finances
      Endpoint.subscribe("transaction:updated:#{organization_id}")
      Endpoint.subscribe("requisition:linked:#{organization_id}")
      Endpoint.subscribe("requisition:rejected:#{organization_id}")
      Endpoint.subscribe("requisition:error:#{organization_id}")
      # KSeF status (separate system)
      Ksef.subscribe_ksef_status(organization_id)
    end

    socket =
      if user.role == :admin do
        allow_upload(socket, :file,
          max_entries: 50,
          accept: ["application/pdf", "image/*"],
          progress: &handle_progress/3,
          auto_upload: true
        )
      else
        socket
      end

    connected_bank_accounts =
      [scope: socket.assigns.ash_scope]
      |> Finances.list_requisitions!()
      |> Enum.count(&(&1.status == :accepted))

    socket = assign(socket, :has_connected_bank_account, connected_bank_accounts > 0)

    active_months =
      get_active_months(socket.assigns.ash_scope) ++
        [Date.beginning_of_month(Date.utc_today())]

    socket = assign(socket, :active_months, active_months)

    socket =
      socket
      |> assign(:show_search, false)
      |> assign(:search_query, "")
      |> assign(:search_results, [])
      |> assign(:transactions_debounce_timer, nil)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    parsed = parse_url_params(params)

    socket =
      socket
      |> apply_action(socket.assigns.live_action, params)
      |> maybe_show_tutorial(Map.get(params, "show_modal") == "true")
      |> assign(:params, parsed)
      |> refetch_invoicing_entries()

    {:noreply, socket}
  end

  defp parse_url_params(params) do
    %{
      month: parse_month(Map.get(params, "month")),
      filter: parse_filter(Map.get(params, "filter")),
      group_by_party: parse_group_by_party(Map.get(params, "group_by_party"))
    }
  end

  defp parse_month(nil), do: Date.beginning_of_month(Date.utc_today())
  defp parse_month(date_string), do: Date.from_iso8601!(date_string)

  defp parse_filter(nil), do: :invoices
  defp parse_filter(filter_string), do: String.to_existing_atom(filter_string)

  defp parse_group_by_party("true"), do: true
  defp parse_group_by_party("false"), do: false
  defp parse_group_by_party(nil), do: true
  defp parse_group_by_party(_), do: false

  defp maybe_show_tutorial(socket, true), do: push_event(socket, "js-exec", %{to: "#tutorial-modal", attr: "phx-show"})

  defp maybe_show_tutorial(socket, _), do: socket

  @impl true
  def handle_event("change-month", %{"month" => month}, socket) do
    month = Date.from_iso8601!(month)

    {:noreply, update_param(socket, :month, month)}
  end

  def handle_event("hide-tutorial-modal", _params, socket) do
    socket =
      socket
      |> push_event("js-exec", %{
        to: "#tutorial-modal",
        attr: "phx-remove"
      })
      |> update_param(:show_modal, false)

    {:noreply, socket}
  end

  def handle_event("change-filter", %{"filter" => filter}, socket) do
    # Use existing atoms to avoid atom exhaustion
    filter = String.to_existing_atom(filter)

    {:noreply, update_param(socket, :filter, filter)}
  end

  def handle_event("toggle-grouping", _params, socket) do
    current = socket.assigns.params.group_by_party
    new_value = !current

    {:noreply, update_param(socket, :group_by_party, new_value)}
  end

  @impl true
  def handle_event("upload", _, socket) do
    socket = refetch_upload_counts(socket)

    {:noreply, socket}
  end

  def handle_event(
        "toggle-skip-invoicing",
        %{"id" => id, "type" => type},
        %{assigns: %{params: %{filter: :unmatched}}} = socket
      ) do
    # mark for removal (animation)
    socket = push_event(socket, "mark-for-removal", %{id: id})

    # actual removal
    Process.send_after(self(), {:toggle_skip_invoicing, %{id: id, type: type}}, 500)

    {:noreply, socket}
  end

  def handle_event("toggle-skip-invoicing", %{"id" => id, "type" => type}, socket) do
    # instantly remove if not in unmatched view (where changing state removes the row)
    Process.send_after(self(), {:toggle_skip_invoicing, %{id: id, type: type}}, 1)

    {:noreply, socket}
  end

  def handle_event(
        "toggle-skip-invoicing-group",
        %{"group_id" => group_id, "transaction_ids" => transaction_ids},
        %{assigns: %{params: %{filter: :unmatched}}} = socket
      ) do
    # mark group for removal (animation)
    socket = push_event(socket, "mark-for-removal", %{id: group_id})

    # mark all child transactions for removal
    socket =
      Enum.reduce(transaction_ids, socket, fn id, acc ->
        push_event(acc, "mark-for-removal", %{id: id})
      end)

    # actual removal - toggle all transactions
    Enum.each(transaction_ids, fn id ->
      Process.send_after(self(), {:toggle_skip_invoicing, %{id: id, type: "transaction"}}, 500)
    end)

    {:noreply, socket}
  end

  def handle_event("toggle-skip-invoicing-group", %{"transaction_ids" => transaction_ids}, socket) do
    # instantly remove if not in unmatched view
    Enum.each(transaction_ids, fn id ->
      Process.send_after(self(), {:toggle_skip_invoicing, %{id: id, type: "transaction"}}, 1)
    end)

    {:noreply, socket}
  end

  def handle_event("open-search", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_search, true)
     |> assign(:search_query, "")
     |> assign(:search_results, [])}
  end

  def handle_event("close-search", _params, socket) do
    {:noreply, assign(socket, :show_search, false)}
  end

  def handle_event("update-search", %{"q" => q}, socket) do
    q = String.trim(q)

    results =
      Invoicing.search_invoices(
        %{
          query: q,
          include_sales: true,
          include_cost: true
        },
        socket.assigns.ash_scope
      )

    {:noreply,
     socket
     |> assign(:search_results, results)
     |> assign(:search_query, q)}
  end

  def handle_event("goto-invoice", %{"id" => id, "type" => type}, socket) do
    path =
      case type do
        "cost" -> ~p"/kosztowe/#{id}"
        "sales" -> ~p"/sprzedazowe/#{id}"
      end

    {:noreply, push_navigate(socket, to: path)}
  end

  @impl true
  def handle_info({:toggle_skip_invoicing, %{id: id, type: type}}, socket) do
    socket =
      case type do
        "cost_invoice" ->
          scope = socket.assigns.ash_scope
          cost_invoice = Invoicing.get_cost_invoice!(id, scope: scope)
          Invoicing.toggle_cost_invoice_skip!(cost_invoice, scope: scope)
          socket

        "transaction" ->
          scope = socket.assigns.ash_scope
          tx = Finances.get_transaction!(id, scope: scope)
          new_skip = !tx.skip_invoicing
          Finances.set_transaction_skip_invoicing!(tx, %{skip_invoicing: new_skip}, scope: scope)
          toggle_transaction_skip(socket, id, new_skip)

        "sales_invoice" ->
          scope = socket.assigns.ash_scope
          invoice = SalesInvoice.by_id!(id, scope: scope)
          SalesInvoice.toggle_skip!(invoice, scope: scope)
          socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info(%Broadcast{payload: %Notification{resource: Transaction}}, socket) do
    {:noreply, debounce_refetch(socket, :transactions, 10_000)}
  end

  @impl true
  def handle_info({:debounced_refetch, :transactions}, socket) do
    {:noreply, refetch_invoicing_entries(socket)}
  end

  # Blob created — file is being processed, refresh list
  @impl true
  def handle_info(%Broadcast{payload: %Notification{resource: Blob, action: %{type: :create}}}, socket) do
    {:noreply, refetch_invoicing_entries(socket)}
  end

  # Blob updated — processing state transitions
  @impl true
  def handle_info(%Broadcast{payload: %Notification{resource: Blob, action: %{type: :update}, data: blob}}, socket) do
    if blob.processing_state == :failed do
      show_blob_processing_failure_toast(blob)
    end

    {:noreply, refetch_invoicing_entries(socket)}
  end

  # Blob destroyed — processing failed
  @impl true
  def handle_info(
        %Broadcast{
          payload:
            %Notification{resource: Blob, action: %{type: :destroy}, metadata: %{reason: :processing_failed}} =
              notification
        },
        socket
      ) do
    LiveToast.send_toast(:error, notification.data.original_filename, title: "Nie udało się wgrać pliku")

    {:noreply, refetch_invoicing_entries(socket)}
  end

  # Blob destroyed — invalid document uploaded
  @impl true
  def handle_info(
        %Broadcast{
          payload:
            %Notification{resource: Blob, action: %{type: :destroy}, metadata: %{reason: :invalid_document}} =
              notification
        },
        socket
      ) do
    LiveToast.send_toast(
      :error,
      "Plik #{notification.data.original_filename} nie zawiera wymaganych danych. Upewnij się, że wgrywasz fakturę, paragon lub rachunek.",
      title: "Nieprawidłowy dokument"
    )

    {:noreply, socket}
  end

  # Blob destroyed — normal cleanup (delete invoice, etc.)
  @impl true
  def handle_info(%Broadcast{payload: %Notification{resource: Blob, action: %{type: :destroy}}}, socket) do
    {:noreply, refetch_invoicing_entries(socket)}
  end

  # Cost invoice created — show success toast with link
  @impl true
  def handle_info(
        %Broadcast{payload: %Notification{resource: CostInvoice, action: %{type: :create}} = notification},
        socket
      ) do
    socket = refetch_invoicing_entries(socket)
    cost_invoice = notification.data

    LiveToast.send_toast(
      :success,
      "#{cost_invoice.issue_date} / #{cost_invoice.seller_display_name}",
      title: "Faktura załadowana",
      action: fn assigns ->
        assigns =
          assign(
            assigns,
            :issue_date,
            cost_invoice.issue_date |> Date.beginning_of_month() |> Date.to_iso8601()
          )

        ~H"""
        <.link
          class="text-bold text-sm underline"
          navigate={~p"/fakturowanie?month=#{@issue_date}&filter=invoices"}
        >
          Wyświetl <.icon name="hero-arrow-right-solid" class="size-3" />
        </.link>
        """
      end
    )

    {:noreply, socket}
  end

  # Cost invoice connected to transaction — show match toast
  @impl true
  def handle_info(
        %Broadcast{payload: %Notification{resource: CostInvoice, action: %{name: :connect_transactions}, data: ci}},
        socket
      ) do
    socket = refetch_invoicing_entries(socket)
    cost_invoice = ci

    LiveToast.send_toast(
      :success,
      "#{cost_invoice.issue_date} / #{cost_invoice.seller_display_name}",
      title: "Połączenie faktury z transakcją",
      action: fn assigns ->
        assigns =
          assign(
            assigns,
            :issue_date,
            cost_invoice.issue_date |> Date.beginning_of_month() |> Date.to_iso8601()
          )

        ~H"""
        <.link
          class="text-bold text-sm underline"
          navigate={~p"/fakturowanie?month=#{@issue_date}&filter=invoices"}
        >
          Wyświetl <.icon name="hero-arrow-right-solid" class="size-3" />
        </.link>
        """
      end
    )

    {:noreply, socket}
  end

  # Cost invoice — generic update/destroy catch-all
  @impl true
  def handle_info(%Broadcast{payload: %Notification{resource: CostInvoice}}, socket) do
    {:noreply, refetch_invoicing_entries(socket)}
  end

  # Sales invoice — any change
  @impl true
  def handle_info(%Broadcast{payload: %Notification{resource: SalesInvoice}}, socket) do
    {:noreply, refetch_invoicing_entries(socket)}
  end

  @impl true
  def handle_info({:ksef_invoice_status, _payload}, socket) do
    {:noreply, refetch_invoicing_entries(socket)}
  end

  # Handle Ash native PubSub broadcasts for requisition status changes
  def handle_info(
        %Broadcast{topic: "requisition:" <> _, payload: %Notification{resource: Requisition, action: action}},
        socket
      ) do
    {toast_type, message} =
      case action do
        :accept ->
          {:success, "Konto bankowe zostało pomyślnie połączone!"}

        :reject ->
          {:error, "Połączenie z bankiem zostało odrzucone. Spróbuj ponownie."}

        :handle_check_error ->
          {:error, "Wystąpił błąd podczas łączenia konta bankowego. Spróbuj ponownie."}

        _ ->
          {:info, "Status połączenia z bankiem został zaktualizowany."}
      end

    LiveToast.send_toast(toast_type, message)

    {:noreply, socket}
  end

  defp show_blob_processing_failure_toast(%Blob{original_filename: filename, processing_metadata: metadata}) do
    case processing_failure_reason(metadata) do
      :invalid_document ->
        LiveToast.send_toast(
          :error,
          processing_failure_message(metadata, filename),
          title: "Nieprawidłowy dokument"
        )

      _ ->
        LiveToast.send_toast(:error, processing_failure_message(metadata, filename), title: "Nie udało się wgrać pliku")
    end
  end

  defp processing_failure_reason(%{"error_code" => "invalid_document"}), do: :invalid_document
  defp processing_failure_reason(%{error_code: "invalid_document"}), do: :invalid_document
  defp processing_failure_reason(%{"error" => ":invalid_document"}), do: :invalid_document
  defp processing_failure_reason(%{error: ":invalid_document"}), do: :invalid_document
  defp processing_failure_reason(_), do: :processing_failed

  defp processing_failure_message(%{"error_message" => message}, _filename) when is_binary(message), do: message
  defp processing_failure_message(%{error_message: message}, _filename) when is_binary(message), do: message

  defp processing_failure_message(_metadata, filename), do: filename

  defp update_param(socket, key, value) do
    params = Map.put(socket.assigns.params, key, value)

    url_params = %{
      month: params.month |> Date.beginning_of_month() |> Date.to_iso8601(),
      filter: Atom.to_string(params.filter),
      group_by_party: to_string(params.group_by_party)
    }

    socket =
      push_patch(socket,
        to:
          ~p"/fakturowanie?month=#{url_params.month}&filter=#{url_params.filter}&group_by_party=#{url_params.group_by_party}"
      )

    socket
  end

  defp handle_progress(:file, _, socket) do
    socket =
      case uploaded_entries(socket, :file) do
        {[_ | _] = entries, []} ->
          handle_uploads(entries, socket)
          refetch_upload_counts(socket)

        _ ->
          socket
      end

    {:noreply, socket}
  end

  defp handle_uploads(entries, socket) do
    scope = socket.assigns.ash_scope

    for entry <- entries do
      consume_uploaded_entry(socket, entry, fn %{path: path} ->
        handle_upload_result(
          upload_cost_invoice(
            path,
            entry.client_type,
            entry.client_name,
            scope
          ),
          scope
        )

        {:ok, nil}
      end)
    end
  end

  defp handle_upload_result({:ok, {:existing_cost_invoice, cost_invoice}}, _scope) do
    LiveToast.send_toast(
      :info,
      "Ta faktura jest już w systemie",
      title: "Duplikat pliku",
      action: fn assigns ->
        assigns = assign(assigns, :cost_invoice_id, cost_invoice.id)

        ~H"""
        <.link
          class="text-bold text-sm underline"
          navigate={~p"/kosztowe/#{@cost_invoice_id}"}
        >
          Wyświetl <.icon name="hero-arrow-right-solid" class="size-3" />
        </.link>
        """
      end
    )
  end

  defp handle_upload_result({:ok, :blob_already_processing}, _scope) do
    LiveToast.send_toast(:info, "Ten plik jest już przetwarzany")
  end

  defp handle_upload_result({:ok, :blob_reprocessing_started}, _scope) do
    LiveToast.send_toast(:info, "Plik został dodany ponownie do kolejki przetwarzania")
  end

  defp handle_upload_result({:error, :blob_already_exists}, _scope) do
    LiveToast.send_toast(:info, "Ta faktura jest już w systemie")
  end

  defp handle_upload_result(_result, _scope), do: nil

  defp upload_cost_invoice(path, content_type, original_filename, scope) do
    Blobs.create_or_retry_cost_invoice_blob(path, content_type, original_filename, scope: scope)
  end

  # TODO: re-add Transaction struct constraints once legacy Ecto schema is removed
  defp toggle_transaction_skip(socket, id, new_skip) do
    entries =
      Enum.map(socket.assigns.invoicing_entries, fn
        %{__struct__: _, id: ^id, skip_invoicing: _} = tx ->
          Map.put(tx, :skip_invoicing, new_skip)

        %TransactionGroup{transactions: txns} = group ->
          updated =
            Enum.map(txns, fn
              %{__struct__: _, id: ^id, skip_invoicing: _} = tx -> Map.put(tx, :skip_invoicing, new_skip)
              other -> other
            end)

          %{group | transactions: updated}

        other ->
          other
      end)

    assign(socket, :invoicing_entries, entries)
  end

  defp refetch_invoicing_entries(socket) do
    month = socket.assigns.params.month
    filter = socket.assigns.params.filter
    scope = socket.assigns.ash_scope
    date_range_from = Date.beginning_of_month(month)
    date_range_to = Date.end_of_month(month)

    entries = fetch_entries(date_range_from, date_range_to, filter, scope)

    entries = group_cost_transactions_by_party(entries, socket.assigns.params.group_by_party)

    socket = assign(socket, :invoicing_entries, entries)

    # Pending entries for badge count
    pending_entries =
      fetch_entries(date_range_from, date_range_to, :unmatched, scope)

    raw_pending_count = Enum.count(pending_entries)

    # Badge count follows the grouping toggle: when grouping is on,
    # grouped transactions count as one item each
    pending_invoicing_entries_count =
      if socket.assigns.params.group_by_party do
        pending_entries
        |> group_cost_transactions_by_party(true)
        |> Enum.count()
      else
        raw_pending_count
      end

    # Check if any entries exist this month (regardless of filter)
    all_entries_count =
      date_range_from
      |> fetch_entries(date_range_to, :all, scope)
      |> Enum.count()

    is_month_touched = all_entries_count > 0 or raw_pending_count > 0

    # No new transactions can be added after month ends
    has_month_ended =
      month
      |> Date.end_of_month()
      |> Date.compare(Date.utc_today()) == :lt

    socket
    |> assign(:is_month_touched, is_month_touched)
    |> assign(:is_month_closed, is_month_touched and has_month_ended and raw_pending_count == 0)
    |> assign(:pending_invoicing_entries_count, pending_invoicing_entries_count)
    |> refetch_upload_counts()
  end

  defp refetch_upload_counts(socket) do
    currently_uploading_count =
      case socket.assigns do
        %{uploads: %{file: upload}} ->
          length(Enum.filter(upload.entries, &(!&1.done?)))

        _ ->
          0
      end

    socket
    |> assign(
      :processing_blobs_count,
      Invoicing.get_processing_cost_invoices_count(socket.assigns.ash_scope)
    )
    |> assign(:currently_uploading_count, currently_uploading_count)
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, :page_title, "Fakturowanie")
  end

  defp group_cost_transactions_by_party(entries, true) do
    # Separate transactions from other entries (invoices)
    # TODO: re-add Transaction struct constraints once legacy Ecto schema is removed
    {transactions, other_entries} =
      Enum.split_with(entries, fn
        %{__struct__: _, transaction_amount: _} -> true
        _ -> false
      end)

    # Split into cost (negative) and income (positive) transactions
    {cost_transactions, income_transactions} =
      Enum.split_with(transactions, fn %{transaction_amount: amount} ->
        Decimal.lt?(amount, 0)
      end)

    # Group cost transactions by creditor_name
    cost_by_party = Enum.group_by(cost_transactions, & &1.creditor_name)

    # Group income transactions by debtor_name
    income_by_party = Enum.group_by(income_transactions, & &1.debtor_name)

    # Process cost transaction groups
    {cost_groups, ungrouped_cost} =
      Enum.split_with(cost_by_party, fn {_party, txns} ->
        length(txns) >= 2 &&
          Enum.all?(txns, &groupable_transaction?/1)
      end)

    # Process income transaction groups
    {income_groups, ungrouped_income} =
      Enum.split_with(income_by_party, fn {_party, txns} ->
        length(txns) >= 2 &&
          Enum.all?(txns, &groupable_transaction?/1)
      end)

    # Build group structs
    cost_group_structs =
      Enum.map(cost_groups, fn {party, txns} ->
        build_transaction_group(party, txns)
      end)

    income_group_structs =
      Enum.map(income_groups, fn {party, txns} ->
        build_transaction_group(party, txns)
      end)

    # Flatten ungrouped transactions
    ungrouped_cost_flat = Enum.flat_map(ungrouped_cost, fn {_party, txns} -> txns end)
    ungrouped_income_flat = Enum.flat_map(ungrouped_income, fn {_party, txns} -> txns end)

    [cost_group_structs, income_group_structs, ungrouped_cost_flat, ungrouped_income_flat, other_entries]
    |> Enum.concat()
    |> order_entries_for_display()
  end

  # Pattern match: grouping disabled
  defp group_cost_transactions_by_party(entries, false) do
    entries
  end

  # TODO: re-add Transaction struct constraints once legacy Ecto schema is removed
  defp groupable_transaction?(%{skip_invoicing: skip, cost_invoices: cost, sales_invoices: sales}) do
    not skip and cost == [] and sales == []
  end

  defp groupable_transaction?(_), do: false

  defp build_transaction_group(party, transactions) do
    total =
      Enum.reduce(transactions, Decimal.new(0), fn t, acc ->
        Decimal.add(acc, t.transaction_amount)
      end)

    # Use LATEST date for sorting
    latest_transaction = Enum.max_by(transactions, & &1.booking_date, Date)

    # Generate stable ID from party name
    id = "group-#{:erlang.phash2(party)}"

    %TransactionGroup{
      id: id,
      party: party,
      total: total,
      count: length(transactions),
      currency: latest_transaction.transaction_currency,
      date: latest_transaction.booking_date,
      transactions: transactions
    }
  end

  # ── Entries — direct resource calls ─────────────────────────────────

  @cost_invoice_loads [
    :transactions,
    :effective_total_amount,
    :effective_currency,
    :effective_seller_display_name
  ]
  @sales_invoice_loads [
    :gross_value,
    :sales_invoice_items,
    :buyer_display_name_label,
    :transactions,
    corrections: :sales_invoice_items,
    latest_correction: :sales_invoice_items
  ]

  defp fetch_entries(from, to, filter, scope) do
    case filter do
      :all ->
        [
          list_cost_invoices(from, to, %{date_field: :issue_date}, scope),
          list_sales_invoices(from, to, %{date_field: :issue_date, kind: :vat}, scope),
          list_transactions(from, to, %{}, scope)
        ]
        |> Enum.concat()
        |> order_entries_for_display()

      :unmatched ->
        [
          list_cost_invoices(from, to, %{date_field: :due_date, reconciliation: :pending}, scope),
          list_sales_invoices(from, to, %{date_field: :due_date, kind: :vat, reconciliation: :pending}, scope),
          list_transactions(from, to, %{reconciliation: :pending}, scope)
        ]
        |> Enum.concat()
        |> order_entries_for_display()

      :invoices ->
        [
          list_cost_invoices(from, to, %{date_field: :issue_date}, scope),
          list_sales_invoices(from, to, %{date_field: :issue_date, kind: :vat}, scope)
        ]
        |> Enum.concat()
        |> order_entries_for_display()

      :transactions ->
        from
        |> list_transactions(to, %{}, scope)
        |> order_entries_for_display()
    end
  end

  defp list_cost_invoices(from, to, extra_args, scope) do
    args = Map.merge(%{date_from: from, date_to: to}, extra_args)
    Invoicing.list_cost_invoices!(args, load: @cost_invoice_loads, scope: scope)
  end

  defp list_sales_invoices(from, to, extra_args, scope) do
    args = Map.merge(%{date_from: from, date_to: to}, extra_args)

    Invoicing.list_sales_invoices!(args, load: @sales_invoice_loads, scope: scope)
  end

  defp list_transactions(from, to, extra_args, scope) do
    args = Map.merge(%{date_from: from, date_to: to}, extra_args)

    Finances.list_transactions!(args,
      load: [:cost_invoices, :sales_invoices],
      query: [sort: [booking_date: :desc]],
      scope: scope
    )
  end

  # ── Active months — 3 Ash reads + Elixir dedup ─────────────────────

  defp get_active_months(scope) do
    scope_opts = [scope: scope]

    sales_months =
      SalesInvoice
      |> Ash.Query.select([:issue_date])
      |> Ash.Query.for_read(:read, %{}, scope_opts)
      |> Ash.read!(scope_opts)
      |> Enum.map(& &1.issue_date)

    cost_months =
      CostInvoice
      |> Ash.Query.select([:issue_date])
      |> Ash.Query.for_read(:read, %{}, scope_opts)
      |> Ash.read!(scope_opts)
      |> Enum.map(& &1.issue_date)

    tx_months =
      Transaction
      |> Ash.Query.select([:booking_date])
      |> Ash.Query.for_read(:read, %{}, scope_opts)
      |> Ash.read!(scope_opts)
      |> Enum.map(& &1.booking_date)

    (sales_months ++ cost_months ++ tx_months)
    |> Enum.map(&Date.beginning_of_month/1)
    |> Enum.uniq()
    |> Enum.sort(Date)
  end

  # ── Entry sorting for display ──────────────────────────────────────

  @doc false
  defp order_entries_for_display(entries) do
    Enum.sort(entries, fn a, b ->
      cond do
        # Draft invoices first (only SalesInvoice)
        entry_draft?(a) != entry_draft?(b) ->
          entry_draft?(a)

        entry_matched?(a) != entry_matched?(b) ->
          # Unmatched first
          not entry_matched?(a)

        entry_date(a) != entry_date(b) ->
          # Newer first
          Date.after?(entry_date(a), entry_date(b))

        # Invoice number descending (only SalesInvoice)
        (inv_a = entry_invoice_number(a)) != (inv_b = entry_invoice_number(b)) ->
          inv_a >= inv_b

        true ->
          a.id < b.id
      end
    end)
  end

  defp entry_date(%SalesInvoice{issue_date: date}), do: date
  defp entry_date(%CostInvoice{issue_date: date}), do: date
  defp entry_date(%Transaction{booking_date: date}), do: date
  defp entry_date(%TransactionGroup{date: date}), do: date

  defp entry_matched?(%SalesInvoice{} = inv), do: Enum.any?(inv.transactions) or Map.get(inv, :skip_invoicing, false)

  defp entry_matched?(%CostInvoice{} = inv), do: Enum.any?(inv.transactions) or Map.get(inv, :skip_invoicing, false)

  defp entry_matched?(%Transaction{} = tx), do: Enum.any?(tx.cost_invoices ++ tx.sales_invoices) or tx.skip_invoicing

  # Groups only contain unmatched transactions by design
  defp entry_matched?(%TransactionGroup{}), do: false
  defp entry_matched?(_), do: false

  # Draft = no invoice number assigned (only SalesInvoice)
  defp entry_draft?(%SalesInvoice{invoice_number: num}), do: is_nil(num)
  defp entry_draft?(_), do: false

  defp entry_invoice_number(%SalesInvoice{invoice_number: num}), do: num
  defp entry_invoice_number(_), do: nil
end
