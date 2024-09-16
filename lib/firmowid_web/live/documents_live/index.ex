defmodule FirmowidWeb.DocumentsLive.Index do
  use FirmowidWeb, :live_view

  alias Firmowid.Documents
  alias Firmowid.Finances
  alias Firmowid.InvoiceMatcher

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Documents.subscribe()

    # previous_month_date = Date.utc_today() |> Date.add(-Date.days_in_month(Date.utc_today()))
    # date_range_from = Date.beginning_of_month(previous_month_date)
    # date_range_to = Date.end_of_month(previous_month_date)

    date_range_from = ~D[2024-07-01]
    date_range_to = ~D[2024-08-31]

    socket =
      socket
      # uploading indicator
      |> assign(:documents_pending_extraction, Documents.list_documents_without_metadata())
      # upload form
      |> allow_upload(:file, accept: ~w(.pdf), progress: &handle_progress/3, auto_upload: true)
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
          date_range_from,
          date_range_to
        )
      )

    {:ok, socket}
  end

  defp handle_progress(:file, entry, socket) do
    if entry.done? do
      consume_uploaded_entries(socket, :file, fn %{path: path}, _entry ->
        {:ok, document} =
          Documents.create_document({path, ".pdf"})

        Documents.start_extraction_job(document.id)

        {:ok, nil}
      end)

      socket =
        socket
        |> put_flash(:info, "Dokument został dodany")
        |> assign(:documents, Documents.list_documents_with_metadata())
        |> assign(:documents_pending_extraction, Documents.list_documents_without_metadata())

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
    Documents.delete_document(document_id)

    socket =
      socket
      |> put_flash(:info, "Dokument został usunięty.")
      |> assign(:documents, Documents.list_documents_with_metadata())
      |> assign(:documents_pending_extraction, Documents.list_documents_without_metadata())

    {:noreply, socket}
  end

  @impl true
  def handle_event("change-date", date_range_form, socket) do
    socket =
      socket
      |> assign(:date_range_form, to_form(date_range_form))

    socket =
      socket
      |> assign(
        :invoice_matchers,
        InvoiceMatcher.get_invoice_matchers(
          Date.from_iso8601!(date_range_form["from"]),
          Date.from_iso8601!(date_range_form["to"])
        )
      )

    {:noreply, socket}
  end

  @impl true
  def handle_event("skip-invoicing", invoice_matcher, socket) do
    case String.split(invoice_matcher["invoice-matcher"], "|") do
      [document_id, " "] ->
        document_id
        |> String.trim()
        |> String.to_integer()
        |> Documents.update_document(%{
          skip_invoicing: true
        })

      [" ", imported_transaction_id] ->
        imported_transaction_id
        |> String.trim()
        |> String.to_integer()
        |> Finances.update_imported_transaction(%{
          skip_invoicing: true
        })
    end

    date_range_form = socket.assigns.date_range_form

    socket =
      socket
      |> assign(
        :invoice_matchers,
        InvoiceMatcher.get_invoice_matchers(
          Date.from_iso8601!(date_range_form["from"].value),
          Date.from_iso8601!(date_range_form["to"].value)
        )
      )

    {:noreply, socket}
  end

  @impl true
  def handle_info({:document_updated, _}, socket) do
    socket =
      socket
      |> assign(:documents, Documents.list_documents_with_metadata())
      |> assign(:documents_pending_extraction, Documents.list_documents_without_metadata())

    {:noreply, socket}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Dokumenty")
  end
end
