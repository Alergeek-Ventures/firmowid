defmodule FirmowidWeb.DocumentsLive.Index do
  alias Firmowid.Blobs
  use FirmowidWeb, :live_view

  alias Firmowid.Documents
  alias Firmowid.Finances
  alias Firmowid.InvoiceMatcher
  alias Firmowid.BankData

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Documents.subscribe_cost_invoice_broadcast(socket.assigns.current_user.organization_id)
      Finances.subscribe_transaction_broadcast(socket.assigns.current_user.organization_id)
    end

    user = socket.assigns.current_user
    organization_id = user.organization_id

    socket =
      socket
      # upload form
      |> allow_upload(:file,
        max_entries: 50,
        accept: ["application/pdf", "image/*"],
        progress: &handle_progress/3,
        auto_upload: true
      )

    connected_bank_accounts =
      BankData.list_requisitions(organization_id)
      |> Enum.count(&(&1.status == :accepted))

    socket =
      socket
      |> assign(
        :has_connected_bank_account,
        connected_bank_accounts > 0
      )

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    socket =
      socket
      |> apply_action(socket.assigns.live_action, params)

    month =
      case Map.get(params, "month") do
        nil -> Date.utc_today() |> Date.beginning_of_month()
        date_string -> Date.from_iso8601!(date_string)
      end

    filter =
      case Map.get(params, "filter") do
        nil -> :invoices
        filter_string -> String.to_existing_atom(filter_string)
      end

    socket =
      socket
      # UI controls
      |> assign(
        :params,
        %{
          month: month,
          filter: filter
        }
      )
      |> refetch_invoice_matchers()

    {:noreply, socket}
  end

  @impl true
  def handle_event("change-month", %{"month" => month}, socket) do
    month = month |> Date.from_iso8601!()

    socket =
      socket
      |> update_param(:month, month)

    {:noreply, socket}
  end

  def handle_event("change-filter", %{"filter" => filter}, socket) do
    filter = filter |> String.to_atom()

    socket =
      socket
      |> update_param(:filter, filter)

    {:noreply, socket}
  end

  defp update_param(socket, key, value) do
    params =
      socket.assigns.params
      |> Map.put(key, value)

    params = %{
      month: params.month |> Date.beginning_of_month() |> Date.to_iso8601(),
      filter: params.filter |> Atom.to_string()
    }

    socket =
      socket
      |> push_patch(to: ~p"/?month=#{params.month}&filter=#{params.filter}")

    socket
  end

  defp handle_progress(:file, _, socket) do
    socket =
      case uploaded_entries(socket, :file) do
        {[_ | _] = entries, []} ->
          handle_uploads(entries, socket)
          socket |> refetch_upload_counts()

        _ ->
          socket
      end

    {:noreply, socket}
  end

  defp handle_uploads(entries, socket) do
    for entry <- entries do
      consume_uploaded_entry(socket, entry, fn %{path: path} ->
        case Documents.upload_cost_invoice(path, entry.client_type, entry.client_name) do
          {:error, {:blob_already_exists, blob_checksum}} ->
            cost_invoice = Documents.get_cost_invoice_by_checksum!(blob_checksum)

            LiveToast.send_toast(
              :info,
              "Ta faktura jest już w systemie",
              title: "#{cost_invoice.issue_date} / #{cost_invoice.seller_display_name}",
              action: fn assigns ->
                assigns =
                  assigns
                  |> assign(
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

  @impl true
  def handle_event("upload", _, socket) do
    socket =
      socket
      |> refetch_upload_counts()

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle-skip-invoicing", %{"invoice-matcher" => invoice_matcher}, socket) do
    case String.split(invoice_matcher, "|") do
      [cost_invoice_id, ""] ->
        Documents.toggle_skip_invoicing(
          :cost_invoice,
          cost_invoice_id
        )

      ["", transaction_id] ->
        Finances.toggle_skip_invoicing(
          :transaction,
          transaction_id
        )
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info(:transaction_list_updated, socket) do
    socket =
      socket
      |> refetch_invoice_matchers()

    {:noreply, socket}
  end

  @impl true
  def handle_info(:cost_invoice_list_updated, socket) do
    socket =
      socket
      |> refetch_invoice_matchers()

    {:noreply, socket}
  end

  def handle_info({:cost_invoice_failed_to_process, original_filename}, socket) do
    LiveToast.send_toast(:error, original_filename, title: "Nie udało się wgrać pliku")

    socket =
      socket
      |> refetch_invoice_matchers()

    {:noreply, socket}
  end

  def handle_info(
        {:cost_invoice_added, cost_invoice},
        socket
      ) do
    socket = refetch_invoice_matchers(socket)

    LiveToast.send_toast(
      :success,
      "#{cost_invoice.issue_date} / #{cost_invoice.seller_display_name}",
      title: "Faktura załadowana",
      action: fn assigns ->
        assigns =
          assigns
          |> assign(
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

  defp refetch_invoice_matchers(socket) do
    user = socket.assigns.current_user
    organization_id = user.organization_id

    month = socket.assigns.params.month
    filter = socket.assigns.params.filter
    date_range_from = Date.beginning_of_month(month)
    date_range_to = Date.end_of_month(month)

    socket =
      socket
      # actual data
      |> assign(
        :invoice_matchers,
        InvoiceMatcher.get_invoice_matchers(
          organization_id,
          date_range_from,
          date_range_to,
          filter
        )
      )

    # any transactions / invoices present in it
    is_month_touched =
      InvoiceMatcher.get_invoice_matchers(
        organization_id,
        date_range_from,
        date_range_to,
        :all
      )
      |> Enum.count() > 0

    # no new transactions can be added
    has_month_ended =
      socket.assigns.params.month
      |> Date.end_of_month()
      |> Date.compare(Date.utc_today()) == :lt

    pending_invoice_matchers_count =
      InvoiceMatcher.get_invoice_matchers(
        organization_id,
        date_range_from,
        date_range_to,
        :unmatched
      )
      |> Enum.count()

    socket =
      socket
      |> assign(
        :is_month_touched,
        is_month_touched
      )
      |> assign(
        :is_month_closed,
        is_month_touched and has_month_ended and pending_invoice_matchers_count == 0
      )
      |> assign(
        :pending_invoice_matchers_count,
        pending_invoice_matchers_count
      )
      |> refetch_upload_counts()

    socket
  end

  defp refetch_upload_counts(socket) do
    socket
    |> assign(
      :processing_blobs_count,
      Documents.get_processing_blobs_count()
    )
    |> assign(
      :currently_uploading_count,
      length(Enum.filter(socket.assigns.uploads.file.entries, &(!&1.done?)))
    )
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Fakturowanie")
  end
end
