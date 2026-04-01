defmodule FirmowidWeb.Invoicing.Views.Index do
  @moduledoc false
  use FirmowidWeb, :live_view

  import FirmowidWeb.Billing.Components.Billing
  import FirmowidWeb.Core.PubSubDebounce

  alias Firmowid.Analytics
  alias Firmowid.Ash.Billing
  alias Firmowid.Ash.Finances
  alias Firmowid.Ash.Finances.Transaction, as: AshTransaction
  alias Firmowid.Ash.Invoicing.CostInvoice, as: AshCostInvoice
  alias Firmowid.BankData
  alias Firmowid.Invoicing
  alias Firmowid.Invoicing.TransactionGroup
  alias Firmowid.Ksef
  alias Firmowid.SalesInvoices
  alias FirmowidWeb.Core.Endpoint

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    organization_id = user.organization_id

    Bodyguard.permit!(Invoicing, :read, user)

    if connected?(socket) do
      AshCostInvoice.subscribe_cost_invoice_broadcast(organization_id)
      Endpoint.subscribe("transaction:updated:#{organization_id}")
      SalesInvoices.subscribe_sales_invoice_broadcast(organization_id)
      Invoicing.subscribe_invoicing_broadcast(organization_id)
      BankData.subscribe_requisition_updates(organization_id)
      Ksef.subscribe_ksef_status(organization_id)
    end

    socket =
      if Bodyguard.permit?(Invoicing, :upload, user) do
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
      organization_id
      |> BankData.list_requisitions()
      |> Enum.count(&(&1.status == :accepted))

    socket = assign(socket, :has_connected_bank_account, connected_bank_accounts > 0)

    active_months =
      Invoicing.get_all_months_with_invoicing_entries() ++
        [Date.beginning_of_month(Date.utc_today())]

    socket = assign(socket, :active_months, active_months)

    # Check billing limits for cost invoices
    limits = Billing.get_limits!(tenant: organization_id, scope: socket.assigns.ash_scope)

    cost_invoices_limit_check =
      if limits.cost_invoices_used >= limits.cost_invoices_limit,
        do: {:warning, :over_limit, %{used: limits.cost_invoices_used, limit: limits.cost_invoices_limit}},
        else: :ok

    socket =
      socket
      |> assign(:show_search, false)
      |> assign(:search_query, "")
      |> assign(:search_results, [])
      |> assign(:cost_invoices_limit_check, cost_invoices_limit_check)
      |> assign(:transactions_debounce_timer, nil)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    Bodyguard.permit!(Invoicing, :read, socket.assigns.current_user)

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

    Analytics.track_event("invoicing_filter_change", socket.assigns.current_user, %{
      filter_value: filter
    })

    {:noreply, update_param(socket, :filter, filter)}
  end

  def handle_event("toggle-grouping", _params, socket) do
    current = socket.assigns.params.group_by_party
    new_value = !current

    Analytics.track_event("invoicing_grouping_toggle", socket.assigns.current_user, %{
      is_grouped: new_value
    })

    {:noreply, update_param(socket, :group_by_party, new_value)}
  end

  @impl true
  def handle_event("upload", _, socket) do
    Bodyguard.permit!(Invoicing, :upload, socket.assigns.current_user)

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
    Analytics.track_event("invoicing_search_open", socket.assigns.current_user, %{})

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
    Bodyguard.permit!(Invoicing, :read, socket.assigns.current_user)
    q = String.trim(q)

    results =
      Invoicing.search_invoices(%{
        query: q,
        include_sales: true,
        include_cost: true
      })

    {:noreply,
     socket
     |> assign(:search_results, results)
     |> assign(:search_query, q)}
  end

  def handle_event("goto-invoice", %{"id" => id, "type" => type}, socket) do
    Bodyguard.permit!(Invoicing, :read, socket.assigns.current_user)

    Analytics.track_event("invoicing_search_select", socket.assigns.current_user, %{
      invoice_type: type
    })

    path =
      case type do
        "cost" -> ~p"/kosztowe/#{id}"
        "sales" -> ~p"/sprzedazowe/#{id}"
      end

    {:noreply, push_navigate(socket, to: path)}
  end

  @impl true
  def handle_info({:toggle_skip_invoicing, %{id: id, type: type}}, socket) do
    Bodyguard.permit!(Invoicing, :update, socket.assigns.current_user)

    socket =
      case type do
        "cost_invoice" ->
          AshCostInvoice.toggle_skip_invoicing(id)
          socket

        "transaction" ->
          scope = socket.assigns.ash_scope
          tx = Finances.get_transaction!(id, scope: scope)
          new_skip = !tx.skip_invoicing
          Finances.set_transaction_skip_invoicing!(tx, %{skip_invoicing: new_skip}, scope: scope)
          toggle_transaction_skip(socket, id, new_skip)

        "sales_invoice" ->
          SalesInvoices.toggle_skip_invoicing(id)
          socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{payload: %Ash.Notifier.Notification{resource: AshTransaction}}, socket) do
    {:noreply, debounce_refetch(socket, :transactions, 10_000)}
  end

  @impl true
  def handle_info({:debounced_refetch, :transactions}, socket) do
    {:noreply, refetch_invoicing_entries(socket)}
  end

  @impl true
  def handle_info(:cost_invoice_list_updated, socket) do
    socket = refetch_invoicing_entries(socket)

    {:noreply, socket}
  end

  @impl true
  def handle_info(:sales_invoice_list_updated, socket) do
    socket = refetch_invoicing_entries(socket)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:ksef_invoice_status, _payload}, socket) do
    socket = refetch_invoicing_entries(socket)

    {:noreply, socket}
  end

  def handle_info({:cost_invoice_failed_to_process, original_filename}, socket) do
    LiveToast.send_toast(:error, original_filename, title: "Nie udało się wgrać pliku")

    socket = refetch_invoicing_entries(socket)

    {:noreply, socket}
  end

  def handle_info({:invalid_document_uploaded, original_filename}, socket) do
    LiveToast.send_toast(
      :error,
      "Plik #{original_filename} nie zawiera wymaganych danych. Upewnij się, że wgrywasz fakturę, paragon lub rachunek.",
      title: "Nieprawidłowy dokument"
    )

    {:noreply, socket}
  end

  def handle_info({:cost_invoice_added, cost_invoice}, socket) do
    socket = refetch_invoicing_entries(socket)

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

  def handle_info({:cost_invoice_match, %{cost_invoice: cost_invoice}}, socket) do
    socket = refetch_invoicing_entries(socket)

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

  def handle_info({:requisition_status_update, %{status: status}}, socket) do
    {toast_type, message} =
      case status do
        :linked -> {:success, "Konto bankowe zostało pomyślnie połączone!"}
        :processing -> {:info, "Łączenie z bankiem w toku..."}
        :rejected -> {:error, "Połączenie z bankiem zostało odrzucone. Spróbuj ponownie."}
        :expired -> {:error, "Link do połączenia wygasł. Utwórz nowe połączenie."}
        :timeout -> {:error, "Przekroczono limit czasu połączenia. Spróbuj ponownie."}
        :error -> {:error, "Wystąpił błąd podczas łączenia konta bankowego. Spróbuj ponownie."}
      end

    LiveToast.send_toast(toast_type, message)

    {:noreply, socket}
  end

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
    Bodyguard.permit!(Invoicing, :upload, socket.assigns.current_user)
    user = socket.assigns.current_user

    for entry <- entries do
      consume_uploaded_entry(socket, entry, fn %{path: path} ->
        Analytics.track_event("cost_invoice_upload", user, %{file_type: entry.client_type})
        handle_upload_result(AshCostInvoice.upload_cost_invoice(path, entry.client_type, entry.client_name))
        {:ok, nil}
      end)
    end
  end

  defp handle_upload_result({:error, {:blob_already_exists, blob_checksum}}) do
    # TODO: replace authorize?: false + actor: %{} with system actor once available
    cost_invoice =
      AshCostInvoice.by_checksum!(blob_checksum, tenant: Firmowid.Repo.get_org_id(), authorize?: false, actor: %{})

    LiveToast.send_toast(
      :info,
      "Ta faktura jest już w systemie",
      title: "#{cost_invoice.issue_date} / #{cost_invoice.seller_display_name}",
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
  end

  defp handle_upload_result({:error, :failure}) do
    LiveToast.send_toast(:error, "Nie udało się wgrać pliku")
  end

  defp handle_upload_result(_), do: nil

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
    Bodyguard.permit!(Invoicing, :read, socket.assigns.current_user)

    month = socket.assigns.params.month
    filter = socket.assigns.params.filter
    date_range_from = Date.beginning_of_month(month)
    date_range_to = Date.end_of_month(month)

    entries = Invoicing.get_invoicing_entries(date_range_from, date_range_to, filter)

    entries = group_cost_transactions_by_party(entries, socket.assigns.params.group_by_party)

    socket = assign(socket, :invoicing_entries, entries)

    # actual data
    pending_entries =
      Invoicing.get_invoicing_entries(date_range_from, date_range_to, :unmatched)

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

    # any transactions / invoices present in it
    # nothing for this month was added yet
    # leftovers from previous month need also not to be present
    # Note: use raw count here — semantic check regardless of grouping
    is_month_touched =
      date_range_from
      |> Invoicing.get_invoicing_entries(
        date_range_to,
        :all
      )
      |> Enum.count() > 0 or
        raw_pending_count > 0

    # no new transactions can be added
    has_month_ended =
      socket.assigns.params.month
      |> Date.end_of_month()
      |> Date.compare(Date.utc_today()) == :lt

    socket =
      socket
      |> assign(
        :is_month_touched,
        is_month_touched
      )
      |> assign(
        :is_month_closed,
        is_month_touched and has_month_ended and raw_pending_count == 0
      )
      |> assign(
        :pending_invoicing_entries_count,
        pending_invoicing_entries_count
      )
      |> refetch_upload_counts()

    socket
  end

  defp refetch_upload_counts(socket) do
    socket
    |> assign(
      :processing_blobs_count,
      AshCostInvoice.get_processing_cost_invoices_count()
    )
    |> assign(
      :currently_uploading_count,
      length(Enum.filter(socket.assigns.uploads.file.entries, &(!&1.done?)))
    )
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
    |> Invoicing.order_entries_for_display()
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
end
