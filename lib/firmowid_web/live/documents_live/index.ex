defmodule FirmowidWeb.DocumentsLive.Index do
  use FirmowidWeb, :live_view

  alias Firmowid.Documents
  alias Firmowid.Finances
  alias Firmowid.InvoiceMatcher
  alias Firmowid.BankData

  @impl true
  def mount(params, _session, socket) do
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
      # UI controls
      |> assign(
        :month,
        Map.get(
          params,
          "month",
          Date.utc_today()
          |> Date.to_iso8601()
        )
        |> Date.from_iso8601!()
        |> Date.beginning_of_month()
      )
      # filter invoice matchers
      |> assign(
        :filter,
        :all
      )
      |> refetch_invoice_matchers()

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

  defp handle_progress(:file, _entry, socket) do
    if Enum.all?(socket.assigns.uploads.file.entries, fn entry -> entry.done? end) do
      consume_uploaded_entries(socket, :file, fn %{path: path}, entry ->
        {:ok, _} = Documents.upload_cost_invoice(path, entry.client_type, entry.client_name)
      end)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_params(params, _url, socket) do
    socket =
      socket
      |> apply_action(socket.assigns.live_action, params)

    month_from_params = Map.get(params, "month", "1990-09-01") |> Date.from_iso8601!()
    month_from_socket = socket.assigns.month

    socket =
      if month_from_params != month_from_socket do
        socket
        |> push_patch(to: ~p"/?month=#{month_from_socket |> Date.to_iso8601()}")
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("upload", _, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("filter-change", %{"filter" => filter}, socket) do
    socket =
      socket
      |> assign(:filter, filter |> String.to_atom())
      |> refetch_invoice_matchers()

    {:noreply, socket}
  end

  @impl true
  def handle_event("change-month", %{"month" => month}, socket) do
    month = Date.from_iso8601!(month)

    socket =
      socket
      |> assign(:month, month)
      |> push_patch(to: ~p"/?month=#{month |> Date.to_iso8601()}")
      |> refetch_invoice_matchers()

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
      :info,
      "#{cost_invoice.invoice_identifier} / #{cost_invoice.seller_display_name}",
      title: "Faktura załadowana",
      action: fn assigns ->
        assigns =
          assigns
          |> assign(
            :issue_date,
            cost_invoice.issue_date |> Date.beginning_of_month() |> Date.to_iso8601()
          )

        ~H"""
        <.link class="text-sm text-bold underline" navigate={~p"/?month=#{@issue_date}"}>
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

    month = socket.assigns.month
    filter = socket.assigns.filter
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
      |> assign(
        :processing_blobs_count,
        Documents.get_processing_blobs_count()
      )

    socket
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Dokumenty")
  end
end
