defmodule FirmowidWeb.DocumentsLive.Index do
  use FirmowidWeb, :live_view

  alias Firmowid.Documents
  alias Firmowid.Finances
  alias Firmowid.InvoiceMatcher
  alias Firmowid.BankData

  @impl true
  def mount(params, _session, socket) do
    if connected?(socket), do: Documents.subscribe_to_documents_changes()

    previous_month_date =
      Map.get(
        params,
        "month",
        Date.utc_today()
        |> Date.beginning_of_month()
        |> Date.to_iso8601()
      )
      |> Date.from_iso8601!()

    date_range_from = Date.beginning_of_month(previous_month_date)
    date_range_to = Date.end_of_month(previous_month_date)

    user = socket.assigns.current_user
    organization_id = user.organization_id

    socket =
      socket
      # uploading indicator
      |> assign(
        :documents_pending_extraction,
        Documents.list_documents_without_metadata(organization_id)
      )
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
        previous_month_date
      )
      # filter invoice matchers
      |> assign(
        :filter,
        :all
      )
      # actual data
      |> assign(
        :invoice_matchers,
        InvoiceMatcher.get_invoice_matchers(
          organization_id,
          date_range_from,
          date_range_to,
          :all
        )
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

  defp handle_progress(:file, _entry, socket) do
    user = socket.assigns.current_user
    organization_id = user.organization_id

    if Enum.all?(socket.assigns.uploads.file.entries, fn entry -> entry.done? end) do
      consume_uploaded_entries(socket, :file, fn %{path: path}, entry ->
        document = Documents.create_document({path, entry.client_type}, organization_id)

        case document do
          {:ok, document} -> Documents.start_extraction_job(document.id, organization_id)
        end

        {:ok, nil}
      end)

      socket =
        socket
        |> assign(
          :documents_pending_extraction,
          Documents.list_documents_without_metadata(organization_id)
        )

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
    filter = String.to_atom(filter)
    organization_id = socket.assigns.current_user.organization_id
    month = socket.assigns.month
    date_range_from = Date.beginning_of_month(month)
    date_range_to = Date.end_of_month(month)

    socket =
      socket
      |> assign(:filter, filter)
      |> assign(
        :invoice_matchers,
        InvoiceMatcher.get_invoice_matchers(
          organization_id,
          date_range_from,
          date_range_to,
          filter
        )
      )

    {:noreply, socket}
  end

  @impl true
  def handle_event("delete", %{"document-id" => document_id}, socket) do
    user = socket.assigns.current_user
    organization_id = user.organization_id

    Documents.delete_document(organization_id, document_id)

    LiveToast.send_toast(:info, "Dokument został usunięty.")

    socket =
      socket
      |> assign(
        :documents_pending_extraction,
        Documents.list_documents_without_metadata(organization_id)
      )

    {:noreply, socket}
  end

  @impl true
  def handle_event("change-month", %{"month" => month}, socket) do
    user = socket.assigns.current_user
    organization_id = user.organization_id

    month = Date.from_iso8601!(month)

    socket =
      socket
      |> assign(:month, month)
      |> push_patch(to: ~p"/?month=#{month |> Date.to_iso8601()}")

    filter = socket.assigns.filter
    date_range_from = Date.beginning_of_month(month)
    date_range_to = Date.end_of_month(month)

    socket =
      socket
      |> assign(
        :invoice_matchers,
        InvoiceMatcher.get_invoice_matchers(
          organization_id,
          date_range_from,
          date_range_to,
          filter
        )
      )

    {:noreply, socket}
  end

  @impl true
  def handle_event("skip-invoicing", %{"invoice-matcher" => invoice_matcher}, socket) do
    user = socket.assigns.current_user
    organization_id = user.organization_id

    case String.split(invoice_matcher, "|") do
      [document_id, " "] ->
        document_id =
          document_id
          |> String.trim()
          |> String.to_integer()

        Documents.update_document(
          organization_id,
          document_id,
          %{
            skip_invoicing: !Documents.get_document(organization_id, document_id).skip_invoicing
          }
        )

      [" ", imported_transaction_id] ->
        imported_transaction_id =
          imported_transaction_id
          |> String.trim()
          |> String.to_integer()

        Finances.update_imported_transaction(
          organization_id,
          imported_transaction_id,
          %{
            skip_invoicing:
              !Finances.get_imported_transaction!(
                organization_id,
                imported_transaction_id
              ).skip_invoicing
          }
        )
    end

    month = socket.assigns.month

    filter = socket.assigns.filter
    date_range_from = Date.beginning_of_month(month)
    date_range_to = Date.end_of_month(month)

    socket =
      socket
      |> assign(
        :invoice_matchers,
        InvoiceMatcher.get_invoice_matchers(
          organization_id,
          date_range_from,
          date_range_to,
          filter
        )
      )

    {:noreply, socket}
  end

  @impl true
  def handle_info({:document_changed, _}, socket) do
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
        :documents_pending_extraction,
        Documents.list_documents_without_metadata(organization_id)
      )

    {:noreply, socket}
  end

  def handle_info({:document_metadata_added, _, issue_date}, socket) do
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
        :documents_pending_extraction,
        Documents.list_documents_without_metadata(organization_id)
      )

    LiveToast.send_toast(
      :info,
      "Dokument został załadowany.",
      action: fn assigns ->
        assigns =
          assigns
          |> assign(:issue_date, issue_date |> Date.beginning_of_month() |> Date.to_iso8601())

        ~H"""
        <.link class="text-sm text-bold underline" navigate={~p"/?month=#{@issue_date}"}>
          Wyświetl <.icon name="hero-arrow-right-solid" class="h-3 w-3" />
        </.link>
        """
      end
    )

    {:noreply, socket}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Dokumenty")
  end
end
