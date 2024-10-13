defmodule FirmowidWeb.DocumentsLive.Index do
  use FirmowidWeb, :live_view

  alias Firmowid.Documents
  alias Firmowid.Finances
  alias Firmowid.InvoiceMatcher

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Documents.subscribe_to_documents_changes()

    previous_month_date = Date.utc_today() |> Date.add(-Date.days_in_month(Date.utc_today()))
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
        accept: ~w(.pdf),
        progress: &handle_progress/3,
        auto_upload: true
      )
      # UI controls
      |> assign(
        :date_range_form,
        to_form(%{
          "from" => Date.to_iso8601(date_range_from),
          "to" => Date.to_iso8601(date_range_to)
        })
      )
      # actual data
      |> assign(
        :invoice_matchers,
        InvoiceMatcher.get_invoice_matchers(
          organization_id,
          date_range_from,
          date_range_to
        )
      )

    {:ok, socket}
  end

  defp handle_progress(:file, _entry, socket) do
    user = socket.assigns.current_user
    organization_id = user.organization_id

    if Enum.all?(socket.assigns.uploads.file.entries, fn entry -> entry.done? end) do
      consume_uploaded_entries(socket, :file, fn %{path: path}, _entry ->
        document = Documents.create_document({path, ".pdf"}, organization_id)

        case document do
          {:ok, document} -> Documents.start_extraction_job(document.id, organization_id)
        end

        {:ok, nil}
      end)

      LiveToast.send_toast(
        :info,
        if length(socket.assigns.uploads.file.entries) == 1 do
          "Dokument został załadowany."
        else
          if length(socket.assigns.uploads.file.entries) > 5 do
            "#{length(socket.assigns.uploads.file.entries)} dokumentów zostało załadowanych."
          else
            "#{length(socket.assigns.uploads.file.entries)} dokumenty zostały załadowane."
          end
        end
      )

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

    {:noreply, socket}
  end

  @impl true
  def handle_event("upload", _, socket) do
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
  def handle_event("change-date", date_range_form, socket) do
    user = socket.assigns.current_user
    organization_id = user.organization_id

    socket =
      socket
      |> assign(:date_range_form, to_form(date_range_form))

    socket =
      socket
      |> assign(
        :invoice_matchers,
        InvoiceMatcher.get_invoice_matchers(
          organization_id,
          Date.from_iso8601!(date_range_form["from"]),
          Date.from_iso8601!(date_range_form["to"])
        )
      )

    {:noreply, socket}
  end

  @impl true
  def handle_event("skip-invoicing", invoice_matcher, socket) do
    user = socket.assigns.current_user
    organization_id = user.organization_id

    case String.split(invoice_matcher["invoice-matcher"], "|") do
      [document_id, " "] ->
        document_id
        |> String.trim()
        |> String.to_integer()
        |> Documents.update_document(
          organization_id,
          %{
            skip_invoicing: true
          }
        )

      [" ", imported_transaction_id] ->
        imported_transaction_id
        |> String.trim()
        |> String.to_integer()
        |> Finances.update_imported_transaction(
          organization_id,
          %{
            skip_invoicing: true
          }
        )
    end

    date_range_form = socket.assigns.date_range_form

    socket =
      socket
      |> assign(
        :invoice_matchers,
        InvoiceMatcher.get_invoice_matchers(
          organization_id,
          Date.from_iso8601!(date_range_form["from"].value),
          Date.from_iso8601!(date_range_form["to"].value)
        )
      )

    {:noreply, socket}
  end

  @impl true
  def handle_info({:document_changed, _}, socket) do
    user = socket.assigns.current_user
    organization_id = user.organization_id

    date_range = socket.assigns.date_range_form
    date_range_from = Date.from_iso8601!(date_range["from"].value)
    date_range_to = Date.from_iso8601!(date_range["to"].value)

    socket =
      socket
      # actual data
      |> assign(
        :invoice_matchers,
        InvoiceMatcher.get_invoice_matchers(
          organization_id,
          date_range_from,
          date_range_to
        )
      )
      |> assign(
        :documents_pending_extraction,
        Documents.list_documents_without_metadata(organization_id)
      )

    {:noreply, socket}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Dokumenty")
  end
end
