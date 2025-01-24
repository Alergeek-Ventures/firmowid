defmodule Firmowid.Documents do
  import Ecto.Query, warn: false

  require Logger

  alias Firmowid.Documents.Blob
  alias MIME

  alias Firmowid.Repo
  alias Firmowid.Blobs

  alias Firmowid.Documents.CostInvoice
  alias Firmowid.Documents.CostInvoicesTransactions

  @cost_invoice_broadcast_topic "cost_invoice_broadcast_topic"

  ## TODO: standardize pubsub / subscriptions / broadcasts
  def subscribe_cost_invoice_broadcast(organization_id) do
    Phoenix.PubSub.subscribe(
      Firmowid.PubSub,
      "#{@cost_invoice_broadcast_topic}:#{organization_id}"
    )
  end

  def broadcast_cost_invoice_added(cost_invoice) do
    Phoenix.PubSub.broadcast(
      Firmowid.PubSub,
      "#{@cost_invoice_broadcast_topic}:#{cost_invoice.organization_id}",
      {:cost_invoice_added, cost_invoice}
    )
  end

  def broadcast_cost_invoice_list_updated(organization_id) do
    Phoenix.PubSub.broadcast(
      Firmowid.PubSub,
      "#{@cost_invoice_broadcast_topic}:#{organization_id}",
      :cost_invoice_list_updated
    )
  end

  def broadcast_cost_invoice_failed_to_process(original_filename, organization_id) do
    Phoenix.PubSub.broadcast(
      Firmowid.PubSub,
      "#{@cost_invoice_broadcast_topic}:#{organization_id}",
      {:cost_invoice_failed_to_process, original_filename}
    )
  end

  def get_cost_invoice_by_checksum!(blob_checksum) do
    from(c in CostInvoice,
      join: b in Blob,
      on: b.id == c.blob_id,
      where: b.blob_checksum == ^blob_checksum
    )
    |> Repo.one()
    |> Repo.preload(:blob)
  end

  def get_processing_blobs_count() do
    Oban.Job
    |> where(
      [j],
      j.state in ["available", "scheduled", "executing"] and
        fragment("args->>'name' = ?", "extract_cost_invoice_metadata")
    )
    |> Repo.aggregate(:count, skip_organization_id: true, prefix: "oban")
  end

  def list_cost_invoices(
        from \\ Date.utc_today(),
        to \\ Date.utc_today()
      ) do
    CostInvoice
    |> where(
      [d],
      (d.issue_date >= ^from and d.issue_date <= ^to) or
        (d.due_date >= ^from and d.due_date <= ^to) or
        (d.sale_date >= ^from and d.sale_date <= ^to)
    )
    |> order_by(desc: :issue_date)
    |> Repo.all()
    |> Repo.preload(:transactions)
    |> Enum.map(&Map.put(&1, :file_url, Blobs.get_blob_url(&1.blob_id, Repo.get_org_id())))
    |> Enum.map(
      &Map.put(
        &1,
        :amount,
        Money.new(
          &1.total_amount,
          &1.currency
        )
      )
    )
  end

  def list_invoices_issued_in_date_range(from, to) do
    CostInvoice
    |> where(
      [d],
      d.issue_date >= ^from and d.issue_date <= ^to
    )
    |> Repo.all()
    |> Enum.map(&Map.put(&1, :file_url, Blobs.get_blob_url(&1.blob_id, Repo.get_org_id())))
  end

  def list_unmatched_cost_invoices() do
    organization_id = Repo.get_org_id()

    if is_nil(organization_id) do
      raise "Organization id is not set"
    end

    list_unmatched_cost_invoices(organization_id)
  end

  def list_unmatched_cost_invoices(organization_id) do
    CostInvoice
    |> where([d], is_nil(d.blob_id))
    |> Repo.all(organization_id: organization_id)
    |> Repo.preload(:transactions)
    |> Enum.map(&Map.put(&1, :file_url, Blobs.get_blob_url(&1.id, organization_id)))
    |> Enum.map(
      &Map.put(
        &1,
        :amount,
        Money.new(
          &1.total_amount,
          &1.currency
        )
      )
    )
  end

  def get_cost_invoice!(cost_invoice_id) do
    cost_invoice =
      CostInvoice
      |> Repo.get!(cost_invoice_id)
      |> Repo.preload(:transactions)
      |> Repo.preload(:blob)

    cost_invoice
    |> Map.put(:file_url, Blobs.get_blob_url(cost_invoice.blob_id))
    |> Map.put(
      :amount,
      Money.new(
        cost_invoice.total_amount,
        cost_invoice.currency
      )
    )
  end

  def delete_cost_invoice(cost_invoice_id) do
    # use SQL cascading
    cost_invoice =
      CostInvoice
      |> Repo.get!(cost_invoice_id)
      |> Repo.preload(:blob)

    organization_id = cost_invoice.organization_id

    blob_id = cost_invoice.blob_id
    Blobs.delete_blob(blob_id, cost_invoice.organization_id)

    broadcast_cost_invoice_list_updated(organization_id)
  end

  def toggle_skip_invoicing(:cost_invoice, id) do
    cost_invoice = get_cost_invoice!(id)

    cost_invoice =
      cost_invoice
      |> CostInvoice.changeset(%{skip_invoicing: !cost_invoice.skip_invoicing})
      |> Repo.update!()

    broadcast_cost_invoice_list_updated(cost_invoice.organization_id)

    cost_invoice
  end

  def upload_cost_invoice(upload_path, content_type, original_filename) do
    Repo.transaction(fn ->
      case Blobs.create_blob(upload_path, content_type, original_filename) do
        {:ok, blob} ->
          %{
            name: "extract_cost_invoice_metadata",
            blob_id: blob.id,
            organization_id: blob.organization_id
          }
          |> Firmowid.Documents.Worker.new()
          |> Oban.insert!()

          broadcast_cost_invoice_list_updated(blob.organization_id)

          blob

        {:error,
         %Ecto.Changeset{
           changes: %{blob_checksum: blob_checksum},
           errors: [blob_checksum: {"has already been taken", _}]
         }} ->
          Repo.rollback({:blob_already_exists, blob_checksum})

        {:error, reason} ->
          Logger.error("Failed to upload cost invoice: #{inspect(reason)}")
          Repo.rollback(:failure)
      end
    end)
  end

  def create_cost_invoice(extracted_metadata) do
    # allow worker to insert the invoice
    organization_id = Map.get(extracted_metadata, "organization_id", Repo.get_org_id())

    cost_invoice =
      %CostInvoice{}
      |> CostInvoice.changeset(extracted_metadata)
      |> Firmowid.Repo.insert!(organization_id: organization_id)

    broadcast_cost_invoice_added(cost_invoice)
  end

  def create_cost_invoices_transactions_connection(
        cost_invoice_id,
        transaction_id,
        organization_id
      ) do
    CostInvoicesTransactions.changeset(%{
      cost_invoice_id: cost_invoice_id,
      transaction_id: transaction_id,
      organization_id: organization_id
    })
    |> Repo.insert!()
  end

  def delete_cost_invoices_transactions_connection(
        organization_id,
        cost_invoice_id,
        transaction_id
      ) do
    Repo.get_by!(
      CostInvoicesTransactions,
      [cost_invoice_id: cost_invoice_id, transaction_id: transaction_id],
      organization_id: organization_id
    )
    |> Repo.delete!()

    broadcast_cost_invoice_list_updated(organization_id)
  end
end
