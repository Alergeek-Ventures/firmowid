defmodule FirmowidWeb.InvoicingLive.Index do
  @moduledoc false
  use FirmowidWeb, :live_view

  alias Firmowid.Accounts
  alias Firmowid.BankData
  alias Firmowid.CostInvoices
  alias Firmowid.Finances
  alias Firmowid.Invoicing
  alias Firmowid.SalesInvoices

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    organization_id = user.organization_id
    organization = Accounts.get_organization_with_avatar(user.organization)

    Bodyguard.permit!(Invoicing, :read, user)

    Posthog.capture("$set", user.id, %{
      "$set" => %{
        email: user.email,
        name: user.name,
        role: user.role,
        system_role: user.system_role,
        # We have to stringify datetime before sending because of posthog's weird decision
        # https://github.com/PostHog/posthog-elixir/blob/44b47bf7a54667879b0eeea79b92b309f62fb73c/lib/posthog/event.ex#L156
        employment_date:
          case user.employment_date do
            nil -> nil
            date -> Date.to_iso8601(date)
          end,
        organization_id: organization_id,
        organization_name: organization.name
      }
    })

    Posthog.capture("invoicing_view", user.id, %{
      organization_id: organization_id
    })

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

    invoicing_search_enabled =
      Posthog.feature_flag_enabled?("invoicing_search", user.id)

    socket =
      socket
      |> assign(:show_search, false)
      |> assign(:search_query, "")
      |> assign(:search_results, [])
      |> assign(:invoicing_search_enabled, invoicing_search_enabled)

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
      |> assign(:params, %{month: month, filter: filter})
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
        <.link class="text-sm text-bold underline" navigate={~p"/?month=#{@issue_date}&filter=invoices"}>
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
        <.link class="text-sm text-bold underline" navigate={~p"/?month=#{@issue_date}&filter=invoices"}>
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

    params = %{
      month: params.month |> Date.beginning_of_month() |> Date.to_iso8601(),
      filter: Atom.to_string(params.filter)
    }

    socket = push_patch(socket, to: ~p"/?month=#{params.month}&filter=#{params.filter}")

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

            Posthog.capture("cost_invoice_upload_duplicate", socket.assigns.current_user.id, %{
              organization_id: socket.assigns.current_user.organization_id
            })

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
                <.link class="text-sm text-bold underline" navigate={~p"/?month=#{@issue_date}&filter=invoices"}>
                  Wyświetl <.icon name="hero-arrow-right-solid" class="h-3 w-3" />
                </.link>
                """
              end
            )

          {:error, :failure} ->
            Posthog.capture("cost_invoice_upload_failure", socket.assigns.current_user.id, %{
              organization_id: socket.assigns.current_user.organization_id
            })

            LiveToast.send_toast(
              :error,
              "Nie udało się wgrać pliku"
            )

          _ ->
            Posthog.capture("cost_invoice_upload", socket.assigns.current_user.id, %{
              organization_id: socket.assigns.current_user.organization_id
            })

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

    socket =
      assign(
        socket,
        :invoicing_entries,
        Invoicing.get_invoicing_entries(date_range_from, date_range_to, filter)
      )

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
end
