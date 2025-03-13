defmodule Firmowid.CostInvoices do
  import Ecto.Query, warn: false

  require Logger

  alias Firmowid.Accounts.User
  alias Firmowid.Blobs.Blob
  alias MIME

  alias Firmowid.Repo
  alias Firmowid.Blobs

  alias Firmowid.CostInvoices.CostInvoice
  alias Firmowid.CostInvoices.CostInvoicesTransactions

  @behaviour Bodyguard.Policy

  @cost_invoice_broadcast_topic "cost_invoice_broadcast_topic"

  def authorize(_, %User{role: :admin}, _), do: true
  def authorize(_, _, _), do: false

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

  def get_processing_cost_invoices_count() do
    Oban.Job
    |> where(
      [j],
      j.state in ["available", "scheduled", "executing"] and
        fragment("args->>'name' = ?", "extract_cost_invoice_metadata")
    )
    |> Repo.aggregate(:count, skip_organization_id: true, prefix: "oban")
  end

  def list_cost_invoices(
        from,
        to
      ) do
    query =
      from i in CostInvoice,
        where: i.issue_date >= ^from and i.issue_date <= ^to,
        order_by: [desc: i.issue_date]

    query
    |> Repo.all()
    |> Repo.preload(:transactions)
  end

  def list_invoices_issued_in_date_range(from, to) do
    CostInvoice
    |> where(
      [d],
      d.issue_date >= ^from and d.issue_date <= ^to
    )
    |> Repo.all()
    |> Repo.preload(:blob)
    |> Enum.map(&Map.put(&1, :file_url, Blobs.get_blob_url(&1.blob_id, Repo.get_org_id())))
  end

  @doc """
  Unmatched means - not assigned to a transaction and not skipped.
  If date range is provided - due in the given date range.
  """
  def list_unmatched_cost_invoices() do
    organization_id = Repo.get_org_id()

    if is_nil(organization_id) do
      raise "Organization id is not set"
    end

    list_unmatched_cost_invoices(~D[1970-01-01], ~D[2100-01-01], organization_id)
  end

  def list_unmatched_cost_invoices(from, to) do
    organization_id = Repo.get_org_id()

    if is_nil(organization_id) do
      raise "Organization id is not set"
    end

    list_unmatched_cost_invoices(from, to, organization_id)
  end

  def list_unmatched_cost_invoices(from, to, organization_id) do
    query =
      from i in CostInvoice,
        left_join: t in assoc(i, :transactions),
        where: is_nil(t.id),
        where: i.skip_invoicing == false,
        where: i.due_date >= ^from and i.due_date <= ^to,
        order_by: [desc: i.issue_date]

    query
    |> Repo.all(organization_id: organization_id)
    |> Repo.preload(:transactions)
  end

  def get_cost_invoice!(cost_invoice_id) do
    cost_invoice =
      CostInvoice
      |> Repo.get!(cost_invoice_id)
      |> Repo.preload(:transactions)
      |> Repo.preload(:blob)

    cost_invoice
    |> Map.put(:blob_url, Blobs.get_blob_url(cost_invoice.blob_id))
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

  def toggle_skip_invoicing(id) do
    cost_invoice = get_cost_invoice!(id)

    cost_invoice =
      cost_invoice
      |> CostInvoice.changeset(%{skip_invoicing: !cost_invoice.skip_invoicing})
      |> Repo.update!()

    broadcast_cost_invoice_list_updated(cost_invoice.organization_id)

    cost_invoice
  end

  def upload_cost_invoice(upload_path, "image/" <> _ext = content_type, original_filename) do
    create_cost_invoice_job(upload_path, content_type, original_filename)
  end

  def upload_cost_invoice(upload_path, "application/pdf" = content_type, original_filename) do
    create_cost_invoice_job(upload_path, content_type, original_filename)
  end

  def upload_cost_invoice(_upload_path, _content_type, _original_filename) do
    {:error, :unsupported_content_type}
  end

  defp create_cost_invoice_job(upload_path, content_type, original_filename) do
    Repo.transaction(fn ->
      case Blobs.create_blob(upload_path, content_type, original_filename) do
        {:ok, blob} ->
          %{
            name: "extract_cost_invoice_metadata",
            blob_id: blob.id,
            organization_id: blob.organization_id
          }
          |> Firmowid.CostInvoices.Worker.new()
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

  def delete_cost_invoices_transactions_connections(cost_invoice_id) do
    query = from(CostInvoicesTransactions) |> where([c], c.cost_invoice_id == ^cost_invoice_id)

    query
    |> Repo.delete_all()

    organization_id = Repo.get_org_id()
    broadcast_cost_invoice_list_updated(organization_id)
  end
end
