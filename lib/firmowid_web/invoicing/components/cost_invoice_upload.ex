defmodule FirmowidWeb.Invoicing.Components.CostInvoiceUpload do
  @moduledoc """
  Turns files uploaded in a LiveView into cost invoices: each becomes a blob
  that is read in the background. Tells the user about a file that is already
  in the system, already being read, or that could not be read, and shows on
  the upload control how many files are still on their way.
  """

  use FirmowidWeb, :html

  alias Ash.Notifier.Notification
  alias Firmowid.Blobs
  alias Firmowid.Blobs.Blob
  alias FirmowidWeb.Billing.Utilities.OcrLimit
  alias FirmowidWeb.Infrastructure.Components.BlobProcessingToasts
  alias FirmowidWeb.Invoicing.Utilities.Navigation
  alias Phoenix.LiveView

  @doc "What `Phoenix.LiveView.allow_upload/3` accepts as a cost invoice."
  @spec upload_options() :: keyword()
  def upload_options, do: [max_entries: 50, accept: ["application/pdf", "image/*"], auto_upload: true]

  @doc """
  Assigns how many files of the `:file` upload are still being sent
  (`currently_uploading_count`) and how many cost invoice files the
  organization is still reading (`processing_blobs_count`).
  """
  @spec assign_counts(LiveView.Socket.t()) :: LiveView.Socket.t()
  def assign_counts(socket) do
    currently_uploading_count =
      case socket.assigns do
        %{uploads: %{file: upload}} -> Enum.count(upload.entries, &(!&1.done?))
        _no_upload -> 0
      end

    assign(socket,
      currently_uploading_count: currently_uploading_count,
      processing_blobs_count: Blobs.get_processing_blobs_count(:cost_invoice, socket.assigns.ash_scope)
    )
  end

  @doc """
  The pulsing badge in the corner of an upload control while files are sent
  or read: an arrow while sending or for one file, the count for more. Its
  parent must be positioned (`relative`). Renders nothing when all is done.
  """
  attr :id, :string, required: true
  attr :uploading, :integer, required: true
  attr :processing, :integer, required: true

  def processing_badge(assigns) do
    ~H"""
    <span
      :if={@uploading > 0 or @processing > 0}
      id={@id}
      phx-hook="Tippy"
      data-tippy-content={
        gettext("The files are being processed and will be available in Firmowid in a few moments")
      }
      class="absolute -top-3 -right-3 flex size-7 items-center justify-center overflow-hidden rounded-full bg-grey-100"
    >
      <span class="absolute block size-full animate-pulse bg-rust-600" />
      <span class="z-10 flex size-5 items-center justify-center rounded-full bg-grey-100">
        <Lucideicons.arrow_up
          :if={@uploading > 0 or @processing == 1}
          class="size-4 leading-none text-rust-900"
        />
        <span :if={@uploading == 0 and @processing > 1}>{@processing}</span>
      </span>
    </span>
    """
  end

  @doc """
  Consumes the uploaded entries and returns what became of each, as
  `Firmowid.Blobs.create_or_retry_cost_invoice_blob/4` reports it.
  """
  @spec consume(LiveView.Socket.t(), [Phoenix.LiveView.UploadEntry.t()]) :: [term()]
  def consume(socket, entries) do
    scope = socket.assigns.ash_scope

    for entry <- entries do
      LiveView.consume_uploaded_entry(socket, entry, fn %{path: path} ->
        result =
          Blobs.create_or_retry_cost_invoice_blob(path, entry.client_type, entry.client_name, scope: scope)

        toast(result)
        with {:error, error} <- result, do: OcrLimit.toast_refusal(error, entry.client_name)
        {:ok, result}
      end)
    end
  end

  @doc """
  Tells the user when a blob notification says a cost invoice file could not
  be read. Views subscribed to the organization's `blob:updated` and
  `blob:destroyed` topics pass their notifications here.
  """
  @spec toast_failure(Notification.t()) :: :ok
  def toast_failure(%Notification{resource: Blob, data: %{processing_target: :cost_invoice} = blob} = notification) do
    case notification do
      %{action: %{type: :update}} when blob.processing_state == :failed ->
        BlobProcessingToasts.show_failure_toast(blob)

      %{action: %{type: :destroy}, metadata: %{reason: :processing_failed}} ->
        LiveToast.send_toast(:error, blob.original_filename, title: gettext("Failed to upload the file"))

      %{action: %{type: :destroy}, metadata: %{reason: :invalid_document}} ->
        LiveToast.send_toast(
          :error,
          gettext(
            "The file %{filename} does not contain the required data. Make sure you are uploading an invoice, receipt or bill.",
            filename: blob.original_filename
          ),
          title: gettext("Invalid document")
        )

      _other ->
        nil
    end

    :ok
  end

  def toast_failure(%Notification{}), do: :ok

  defp toast({:ok, {:existing_cost_invoice, cost_invoice}}) do
    LiveToast.send_toast(
      :info,
      gettext("This invoice is already in the system"),
      title: gettext("Duplicate file"),
      action: fn assigns ->
        assigns = assign(assigns, :cost_invoice_id, cost_invoice.id)

        ~H"""
        <FirmowidWeb.Core.Toast.view_action navigate={Navigation.cost_invoice_show_path(@cost_invoice_id)} />
        """
      end
    )
  end

  defp toast({:ok, :blob_already_processing}) do
    LiveToast.send_toast(:info, gettext("This file is already being processed"))
  end

  defp toast({:ok, :blob_reprocessing_started}) do
    LiveToast.send_toast(:info, gettext("The file was added to the processing queue again"))
  end

  defp toast({:error, :blob_already_exists}) do
    LiveToast.send_toast(:info, gettext("This invoice is already in the system"))
  end

  defp toast(_created_or_failed), do: nil
end
