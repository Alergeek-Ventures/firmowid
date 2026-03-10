defmodule Firmowid.CostInvoices do
  @moduledoc false
  @behaviour Bodyguard.Policy

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Firmowid.Billing
  alias Firmowid.Blobs
  alias Firmowid.Blobs.Blob
  alias Firmowid.CostInvoices.CostInvoice
  alias Firmowid.CostInvoices.CostInvoicesTransactions
  alias Firmowid.CostInvoices.InboundEmail
  alias Firmowid.Ksef
  alias Firmowid.Repo

  require Logger

  @correction_invoice_types [:kor, :kor_zal, :kor_roz]

  @cost_invoice_broadcast_topic "cost_invoice_broadcast_topic"

  def authorize(action, %{role: :admin, organization_id: org_id}, %{organization_id: org_id})
      when action in [:show, :update, :delete], do: true

  def authorize(:upload, %{role: :admin}, _), do: true
  def authorize(:read_inbox, %{role: :admin}, _), do: true
  def authorize(_, _, _), do: false

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

  def broadcast_invalid_document_uploaded(original_filename, organization_id) do
    Phoenix.PubSub.broadcast(
      Firmowid.PubSub,
      "#{@cost_invoice_broadcast_topic}:#{organization_id}",
      {:invalid_document_uploaded, original_filename}
    )
  end

  def get_cost_invoice_by_checksum!(blob_checksum) do
    from(c in CostInvoice,
      join: b in Blob,
      on: b.id == c.blob_id,
      where: b.blob_checksum == ^blob_checksum
    )
    |> Repo.one!()
    |> Repo.preload(:blob)
  end

  def get_processing_cost_invoices_count do
    Oban.Job
    |> where(
      [j],
      j.state in ["available", "scheduled", "executing"] and
        fragment("args->>'name' = ?", "extract_cost_invoice_metadata")
    )
    |> Repo.aggregate(:count, oban_jobs: true)
  end

  def list_cost_invoices(from, to) do
    query =
      from i in CostInvoice,
        where: i.issue_date >= ^from and i.issue_date <= ^to,
        order_by: [desc: i.issue_date]

    query
    |> Repo.all()
    |> Repo.preload(:transactions)
  end

  @doc """
  Lists cost invoices whose sale falls within the given date range.

  `sale_date` is NOT NULL at the DB level for cost invoices.
  """
  @spec list_cost_invoices_by_sale_date(Date.t(), Date.t()) :: [CostInvoice.t()]
  def list_cost_invoices_by_sale_date(from, to) do
    query =
      from i in CostInvoice,
        where: i.sale_date >= ^from and i.sale_date <= ^to,
        order_by: [desc: i.sale_date]

    query
    |> Repo.all()
    |> Repo.preload(:transactions)
  end

  def list_invoices_in_date_range(from, to) do
    CostInvoice
    |> where(
      [d],
      (d.issue_date >= ^from and d.issue_date <= ^to) or
        (d.sale_date >= ^from and d.sale_date <= ^to)
    )
    |> Repo.all()
    |> Repo.preload(:blob)
    |> Enum.map(&Map.put(&1, :file_url, Blobs.get_blob_url(&1.blob_id)))
  end

  @doc """
  Unmatched means - not assigned to a transaction and not skipped.
  If date range is provided - due in the given date range.
  """
  def list_unmatched_cost_invoices do
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

  def get_cost_invoice(cost_invoice_id) do
    CostInvoice
    |> Repo.get(cost_invoice_id)
    |> Repo.preload(:transactions)
  end

  def get_cost_invoice!(cost_invoice_id) do
    CostInvoice
    |> Repo.get!(cost_invoice_id)
    |> Repo.preload(:transactions)
  end

  def get_cost_invoice_with_blob_url(cost_invoice_id) do
    cost_invoice =
      CostInvoice
      |> Repo.get!(cost_invoice_id)
      |> Repo.preload([:transactions, :blob, :original_invoice, :correction_invoices])

    blob_url =
      case cost_invoice.blob do
        nil -> nil
        _ -> Blobs.get_blob_url(cost_invoice.blob_id)
      end

    %{cost_invoice | blob_url: blob_url}
  end

  def get_cost_invoice_with_blob_url!(cost_invoice_id) do
    cost_invoice =
      CostInvoice
      |> Repo.get!(cost_invoice_id)
      |> Repo.preload([:transactions, :blob, :original_invoice, :correction_invoices])

    %{cost_invoice | blob_url: Blobs.get_blob_url(cost_invoice.blob_id)}
  end

  @doc """
  Deletes a cost invoice by ID.

  Note: The billing counter decrement happens outside the delete transaction.
  This is intentional - billing limits are soft limits (informational only),
  so we prioritize successful invoice deletion over counter accuracy.
  If the decrement fails, a warning is logged but the invoice is still deleted.
  Counter drift is acceptable for soft limit tracking.
  """
  def delete_cost_invoice(cost_invoice_id) do
    # use SQL cascading
    cost_invoice =
      CostInvoice
      |> Repo.get!(cost_invoice_id)
      |> Repo.preload(:blob)

    if CostInvoice.ksef_imported?(cost_invoice) do
      raise "Cost invoice #{cost_invoice_id} is imported from KSeF and cannot be deleted"
    end

    organization_id = cost_invoice.organization_id

    if !correction_invoice?(cost_invoice) do
      case Billing.decrement(organization_id, :cost_invoices) do
        {:ok, _} -> :ok
        {:error, reason} -> Logger.warning("Failed to decrement cost_invoices limit: #{inspect(reason)}")
      end
    end

    blob_id = cost_invoice.blob_id
    Blobs.delete_blob(blob_id)

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

  def upload_cost_invoice(upload_path, content_type, original_filename, inbound_email_id \\ nil)

  def upload_cost_invoice(upload_path, "image/" <> _ext = content_type, original_filename, inbound_email_id) do
    create_cost_invoice_job(upload_path, content_type, original_filename, inbound_email_id)
  end

  def upload_cost_invoice(upload_path, "application/pdf" = content_type, original_filename, inbound_email_id) do
    create_cost_invoice_job(upload_path, content_type, original_filename, inbound_email_id)
  end

  def upload_cost_invoice(_upload_path, _content_type, _original_filename, _inbound_email_id) do
    {:error, :unsupported_content_type}
  end

  defp create_cost_invoice_job(upload_path, content_type, original_filename, inbound_email_id) do
    Repo.transaction(fn ->
      case Blobs.create_blob(upload_path, content_type, original_filename) do
        {:ok, blob} ->
          worker_args = %{
            name: "extract_cost_invoice_metadata",
            blob_id: blob.id,
            organization_id: blob.organization_id
          }

          worker_args =
            if inbound_email_id do
              Map.put(worker_args, :inbound_email_id, inbound_email_id)
            else
              worker_args
            end

          worker_args
          |> Firmowid.CostInvoices.Worker.new()
          |> Firmowid.Oban.insert!()

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

  @doc """
  Creates a cost invoice from extracted metadata.

  Note: The billing counter increment happens outside the insert transaction.
  This is intentional - billing limits are soft limits (informational only),
  so we prioritize successful invoice creation over counter accuracy.
  If the increment fails, a warning is logged but the invoice is still created.
  Counter drift is acceptable for soft limit tracking.
  """
  def create_cost_invoice(extracted_metadata) do
    # allow worker to insert the invoice
    organization_id = Map.get(extracted_metadata, "organization_id", Repo.get_org_id())

    cost_invoice =
      %CostInvoice{}
      |> CostInvoice.changeset(extracted_metadata)
      |> Repo.insert!(organization_id: organization_id)

    if !correction_invoice?(cost_invoice) do
      case Billing.increment(organization_id, :cost_invoices) do
        {:ok, _} -> :ok
        {:error, reason} -> Logger.warning("Failed to increment cost_invoices limit: #{inspect(reason)}")
      end
    end

    broadcast_cost_invoice_added(cost_invoice)

    %{
      name: "match_cost_invoice",
      cost_invoice_id: cost_invoice.id,
      organization_id: organization_id
    }
    |> Firmowid.Invoicing.Worker.new()
    |> Firmowid.Oban.insert!()
  end

  def create_cost_invoices_transactions_connection(invoice_ids, transaction_ids, organization_id) do
    invoice_ids =
      if is_list(invoice_ids) do
        invoice_ids
      else
        [invoice_ids]
      end

    transaction_ids =
      if is_list(transaction_ids) do
        transaction_ids
      else
        [transaction_ids]
      end

    changesets =
      for invoice_id <- invoice_ids, transaction_id <- transaction_ids do
        CostInvoicesTransactions.changeset(%{
          cost_invoice_id: invoice_id,
          transaction_id: transaction_id,
          organization_id: organization_id
        })
      end

    changesets
    |> Enum.reduce(Multi.new(), fn %{changes: data} = changeset, acc ->
      Multi.insert(acc, {data.cost_invoice_id, data.transaction_id}, changeset)
    end)
    |> Repo.transaction()
  end

  def delete_cost_invoices_transactions_connections(cost_invoice_id) do
    query = where(from(CostInvoicesTransactions), [c], c.cost_invoice_id == ^cost_invoice_id)

    Repo.delete_all(query)
    organization_id = Repo.get_org_id()
    broadcast_cost_invoice_list_updated(organization_id)
  end

  def list_cost_invoices_by_ids(ids, date_from \\ nil, date_to \\ nil) do
    query = where(CostInvoice, [ci], ci.id in ^ids)

    query =
      if date_from do
        where(query, [ci], ci.issue_date >= ^date_from)
      else
        query
      end

    query =
      if date_to do
        where(query, [ci], ci.issue_date <= ^date_to)
      else
        query
      end

    query
    |> order_by(desc: :issue_date)
    |> Repo.all()
    |> Repo.preload(:transactions)
  end

  ## Inbound Email functions

  def list_inbound_emails do
    InboundEmail
    |> order_by([e], desc: e.received_at)
    |> Repo.all()
    |> Repo.preload(:cost_invoices)
  end

  def get_inbound_email!(id) do
    Repo.get!(InboundEmail, id)
  end

  def mark_inbound_email_processed(inbound_email, failure_reason \\ nil) do
    inbound_email
    |> InboundEmail.changeset(%{
      processed_at: DateTime.utc_now(),
      failure_reason: failure_reason
    })
    |> Repo.update!()
  end

  # Private functions

  defp correction_invoice?(%CostInvoice{invoice_type: invoice_type}) do
    invoice_type in @correction_invoice_types
  end

  def hydrate_invoice_with_fa3_blob(%CostInvoice{ksef_number: ksef_number, blob_id: blob_id} = invoice)
      when not is_nil(ksef_number) and is_nil(blob_id) do
    with {:ok, xml} <- Ksef.get_invoice_xml_by_ksef_number(ksef_number),
         {:ok, path} <- Briefly.create(extname: ".xml"),
         :ok <- File.write(path, xml),
         {:ok, blob} <- Blobs.create_blob(path, "application/xml", "#{ksef_number}.xml") do
      try do
        invoice
        |> CostInvoice.changeset(%{blob_id: blob.id})
        |> Repo.update!()
        |> Repo.preload(:blob, force: true)
        |> Map.put(:blob_url, Blobs.get_blob_url(blob.id))
      rescue
        error ->
          Blobs.delete_blob(blob.id)
          reraise error, __STACKTRACE__
      end
    else
      {:error, reason} ->
        Logger.error("Failed to fetch KSeF XML for cost invoice #{invoice.id}: #{inspect(reason)}")
        invoice
    end
  end

  def hydrate_invoice_with_fa3_blob(%CostInvoice{} = invoice), do: invoice
end
