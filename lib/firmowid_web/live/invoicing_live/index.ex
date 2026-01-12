defmodule FirmowidWeb.InvoicingLive.Index do
  @moduledoc false
  use FirmowidWeb, :live_view

  alias Firmowid.BankData
  alias Firmowid.CostInvoices
  alias Firmowid.Finances
  alias Firmowid.Finances.Transaction
  alias Firmowid.Invoicing
  alias Firmowid.SalesInvoices
  alias FirmowidWeb.InvoicingLive.TransactionGroup

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    organization_id = user.organization_id

    Bodyguard.permit!(Invoicing, :read, user)

    if connected?(socket) do
      CostInvoices.subscribe_cost_invoice_broadcast(organization_id)
      Finances.subscribe_transaction_broadcast(organization_id)
      SalesInvoices.subscribe_sales_invoice_broadcast(organization_id)
      Invoicing.subscribe_invoicing_broadcast(organization_id)
      BankData.subscribe_requisition_updates(organization_id)
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

    socket =
      socket
      |> assign(:show_search, false)
      |> assign(:search_query, "")
      |> assign(:search_results, [])

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    Bodyguard.permit!(Invoicing, :read, socket.assigns.current_user)

    socket = apply_action(socket, socket.assigns.live_action, params)

    month =
      case Map.get(params, "month") do
        nil -> Date.beginning_of_month(Date.utc_today())
        date_string -> Date.from_iso8601!(date_string)
      end

    filter =
      case Map.get(params, "filter") do
        nil -> :invoices
        filter_string -> String.to_existing_atom(filter_string)
      end

    # Default group_by_party to true for groupable filters, false otherwise
    groupable_filter = filter in [:transactions, :all, :unmatched]

    group_by_party =
      case Map.get(params, "group_by_party") do
        "true" -> groupable_filter
        "false" -> false
        nil -> groupable_filter
        _ -> false
      end

    show_modal = Map.get(params, "show_modal") == "true"

    socket =
      if show_modal do
        push_event(socket, "js-exec", %{to: "#tutorial-modal", attr: "phx-show"})
      else
        socket
      end

    socket =
      socket
      # UI controls
      |> assign(:params, %{month: month, filter: filter, group_by_party: group_by_party})
      |> refetch_invoicing_entries()

    {:noreply, socket}
  end

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
    {:noreply, update_param(socket, :group_by_party, !current)}
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

    case type do
      "cost_invoice" ->
        CostInvoices.toggle_skip_invoicing(id)

      "transaction" ->
        Finances.toggle_skip_invoicing(id)

      "sales_invoice" ->
        SalesInvoices.toggle_skip_invoicing(id)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info(:transaction_list_updated, socket) do
    socket = refetch_invoicing_entries(socket)

    {:noreply, socket}
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
          class="text-sm text-bold underline"
          navigate={~p"/fakturowanie?month=#{@issue_date}&filter=invoices"}
        >
          Wyświetl <.icon name="hero-arrow-right-solid" class="h-3 w-3" />
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
          class="text-sm text-bold underline"
          navigate={~p"/fakturowanie?month=#{@issue_date}&filter=invoices"}
        >
          Wyświetl <.icon name="hero-arrow-right-solid" class="h-3 w-3" />
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

    for entry <- entries do
      consume_uploaded_entry(socket, entry, fn %{path: path} ->
        case CostInvoices.upload_cost_invoice(path, entry.client_type, entry.client_name) do
          {:error, {:blob_already_exists, blob_checksum}} ->
            cost_invoice = CostInvoices.get_cost_invoice_by_checksum!(blob_checksum)

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
                  class="text-sm text-bold underline"
                  navigate={~p"/fakturowanie?month=#{@issue_date}&filter=invoices"}
                >
                  Wyświetl <.icon name="hero-arrow-right-solid" class="h-3 w-3" />
                </.link>
                """
              end
            )

          {:error, :failure} ->
            LiveToast.send_toast(
              :error,
              "Nie udało się wgrać pliku"
            )

          _ ->
            nil
        end

        {:ok, nil}
      end)
    end
  end

  defp refetch_invoicing_entries(socket) do
    Bodyguard.permit!(Invoicing, :read, socket.assigns.current_user)

    month = socket.assigns.params.month
    filter = socket.assigns.params.filter
    date_range_from = Date.beginning_of_month(month)
    date_range_to = Date.end_of_month(month)

    entries = Invoicing.get_invoicing_entries(date_range_from, date_range_to, filter)

    # For :unmatched filter with grouping enabled, we need context about all transactions
    # to avoid grouping when some transactions are skipped/matched
    entries =
      if socket.assigns.params.group_by_party && filter == :unmatched do
        all_transactions = Finances.list_transactions(date_range_from, date_range_to)
        group_cost_transactions_by_party(entries, true, all_transactions)
      else
        group_cost_transactions_by_party(entries, socket.assigns.params.group_by_party, [])
      end

    socket = assign(socket, :invoicing_entries, entries)

    # actual data
    pending_invoicing_entries_count =
      date_range_from
      |> Invoicing.get_invoicing_entries(
        date_range_to,
        :unmatched
      )
      |> Enum.count()

    # any transactions / invoices present in it
    # nothing for this month was added yet
    # leftovers from previous month need also not to be present
    is_month_touched =
      date_range_from
      |> Invoicing.get_invoicing_entries(
        date_range_to,
        :all
      )
      |> Enum.count() > 0 or
        pending_invoicing_entries_count > 0

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
        is_month_touched and has_month_ended and pending_invoicing_entries_count == 0
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
      CostInvoices.get_processing_cost_invoices_count()
    )
    |> assign(
      :currently_uploading_count,
      length(Enum.filter(socket.assigns.uploads.file.entries, &(!&1.done?)))
    )
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, :page_title, "Fakturowanie")
  end

  defp group_cost_transactions_by_party(entries, true, context_transactions) do
    # Separate cost transactions from other entries
    {cost_transactions, other_entries} =
      Enum.split_with(entries, fn
        %Transaction{transaction_amount: amount} -> Decimal.lt?(amount, 0)
        _ -> false
      end)

    # Group ALL cost transactions by party name (exact match)
    all_cost_by_party = Enum.group_by(cost_transactions, & &1.creditor_name)

    # Build a set of parties that have non-groupable transactions in the full context
    parties_with_mixed_state =
      if context_transactions == [] do
        MapSet.new()
      else
        context_transactions
        |> Enum.filter(fn
          %Transaction{transaction_amount: amount} = t ->
            Decimal.lt?(amount, 0) && !groupable_cost_transaction?(t)

          _ ->
            false
        end)
        |> MapSet.new(& &1.creditor_name)
      end

    {groups, ungrouped_transactions} =
      Enum.split_with(all_cost_by_party, fn {party, txns} ->
        # Must have at least 2 transactions
        # AND all transactions in entries must be groupable
        # AND party must not have mixed state in the full context
        length(txns) >= 2 &&
          Enum.all?(txns, &groupable_cost_transaction?/1) &&
          !MapSet.member?(parties_with_mixed_state, party)
      end)

    group_structs =
      Enum.map(groups, fn {party, txns} ->
        build_transaction_group(party, txns)
      end)

    ungrouped_flat =
      Enum.flat_map(ungrouped_transactions, fn {_party, txns} -> txns end)

    [group_structs, ungrouped_flat, other_entries]
    |> Enum.concat()
    |> Invoicing.order_entries_for_display()
  end

  # Pattern match: grouping disabled
  defp group_cost_transactions_by_party(entries, false, _context) do
    entries
  end

  defp groupable_cost_transaction?(%Transaction{} = transaction) do
    is_cost = Decimal.lt?(transaction.transaction_amount, 0)
    not_skipped = transaction.skip_invoicing == false

    not_matched =
      transaction.cost_invoices_transactions == [] &&
        transaction.sales_invoices_transactions == []

    is_cost && not_skipped && not_matched
  end

  defp groupable_cost_transaction?(_), do: false

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
