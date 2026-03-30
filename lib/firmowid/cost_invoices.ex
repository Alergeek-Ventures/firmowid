defmodule Firmowid.CostInvoices do
  @moduledoc false
  @behaviour Bodyguard.Policy

  import Ecto.Query, warn: false

  alias Ash.Error.Unknown
  alias Ash.Error.Unknown.UnknownError
  alias Ecto.Multi
  alias Firmowid.Ash.Billing.Limits, as: AshLimits
  alias Firmowid.Ash.Blobs.Blob, as: AshBlob
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
        as: :invoice,
        where: i.issue_date >= ^from and i.issue_date <= ^to,
        order_by: [desc: i.issue_date]

    query
    |> exclude_linked_corrections()
    |> Repo.all()
    |> Repo.preload([:transactions, :correction_invoices])
    |> Enum.map(&merge_corrections_into_original_invoice/1)
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
      not is_nil(d.blob_id) and
        ((d.issue_date >= ^from and d.issue_date <= ^to) or
           (d.sale_date >= ^from and d.sale_date <= ^to))
    )
    |> Repo.all()
    |> Repo.preload(:blob)
    |> Enum.map(&Map.put(&1, :file_url, AshBlob.get_url!(&1.blob_id, blob_opts())))
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
        as: :invoice,
        left_join: t in assoc(i, :transactions),
        where: is_nil(t.id),
        where: i.skip_invoicing == false,
        where: i.due_date >= ^from and i.due_date <= ^to,
        order_by: [desc: i.issue_date]

    query
    |> exclude_linked_corrections()
    |> Repo.all(organization_id: organization_id)
    |> Repo.preload([:transactions, :correction_invoices])
    |> Enum.map(&merge_corrections_into_original_invoice/1)
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
      |> Repo.preload([:transactions, :blob, :original_invoice, correction_invoices: :blob])

    blob_url =
      case cost_invoice.blob do
        nil -> nil
        _ -> AshBlob.get_url!(cost_invoice.blob_id, blob_opts())
      end

    correction_invoices =
      Enum.map(cost_invoice.correction_invoices, fn
        %{blob: nil} = correction -> correction
        correction -> %{correction | blob_url: AshBlob.get_url!(correction.blob_id, blob_opts())}
      end)

    %{
      cost_invoice
      | blob_url: blob_url,
        correction_invoices: correction_invoices
    }
  end

  def get_cost_invoice_with_blob_url!(cost_invoice_id) do
    cost_invoice =
      CostInvoice
      |> Repo.get!(cost_invoice_id)
      |> Repo.preload([:transactions, :blob, :original_invoice, correction_invoices: :blob])

    %{
      cost_invoice
      | blob_url: AshBlob.get_url!(cost_invoice.blob_id, blob_opts()),
        correction_invoices:
          Enum.map(cost_invoice.correction_invoices, &%{&1 | blob_url: AshBlob.get_url!(&1.blob_id, blob_opts())})
    }
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
      case AshLimits.decrement(organization_id, :cost_invoices, authorize?: false, actor: %{}) do
        {:ok, _} -> :ok
        {:error, reason} -> Logger.warning("Failed to decrement cost_invoices limit: #{inspect(reason)}")
      end
    end

    blob_id = cost_invoice.blob_id
    AshBlob.destroy_blob!(blob_id, blob_opts())

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
      case AshBlob.create_blob(upload_path, content_type, original_filename, blob_opts()) do
        {:ok, blob} ->
          enqueue_extraction_job(blob, inbound_email_id)
          broadcast_cost_invoice_list_updated(blob.organization_id)
          blob

        {:error, error} ->
          handle_blob_create_error(error)
      end
    end)
  end

  defp handle_blob_create_error(%Unknown{} = error) do
    if blob_already_exists_error?(error) do
      Repo.rollback({:blob_already_exists, nil})
    else
      Logger.error("Failed to upload cost invoice: #{inspect(error)}")
      Repo.rollback(:failure)
    end
  end

  defp handle_blob_create_error(reason) do
    Logger.error("Failed to upload cost invoice: #{inspect(reason)}")
    Repo.rollback(:failure)
  end

  defp blob_already_exists_error?(%Unknown{errors: errors}) do
    Enum.any?(errors, fn
      %UnknownError{error: %Ecto.ConstraintError{constraint: constraint}} ->
        String.contains?(constraint, "blob_checksum")

      %UnknownError{error: %Ecto.Changeset{errors: changeset_errors}} ->
        Keyword.has_key?(changeset_errors, :blob_checksum)

      %UnknownError{error: error} when is_binary(error) ->
        String.contains?(error, "blob_checksum") and String.contains?(error, "has already been taken")

      _ ->
        false
    end)
  end

  defp blob_already_exists_error?(_), do: false

  defp enqueue_extraction_job(blob, inbound_email_id) do
    %{name: "extract_cost_invoice_metadata", blob_id: blob.id, organization_id: blob.organization_id}
    |> then(fn args ->
      if inbound_email_id, do: Map.put(args, :inbound_email_id, inbound_email_id), else: args
    end)
    |> Firmowid.CostInvoices.Worker.new()
    |> Firmowid.Oban.insert!()
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
      case AshLimits.increment(organization_id, :cost_invoices, authorize?: false, actor: %{}) do
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

  defp exclude_linked_corrections(query) do
    query
    |> join(
      :left,
      [],
      original_invoice in CostInvoice,
      on: original_invoice.ksef_number == as(:invoice).original_invoice_ksef_number,
      as: :original_invoice
    )
    |> where([], is_nil(as(:invoice).original_invoice_ksef_number) or is_nil(as(:original_invoice).id))
  end

  defp merge_corrections_into_original_invoice(%CostInvoice{correction_invoices: []} = invoice), do: invoice

  defp merge_corrections_into_original_invoice(%CostInvoice{} = invoice) do
    currency_changed? =
      Enum.any?(invoice.correction_invoices, fn correction ->
        correction.currency != invoice.currency
      end)

    total_amount =
      if currency_changed? do
        invoice.total_amount
      else
        Enum.reduce(invoice.correction_invoices, invoice.total_amount, fn correction, acc ->
          Decimal.add(acc, correction.total_amount)
        end)
      end

    latest_snapshot =
      Enum.max_by(invoice.correction_invoices, & &1.ksef_permanent_storage_date, NaiveDateTime, fn -> invoice end)

    %{
      invoice
      | total_amount: total_amount,
        currency: latest_snapshot.currency,
        sale_date: latest_snapshot.sale_date,
        due_date: latest_snapshot.due_date,
        seller: latest_snapshot.seller,
        seller_address: latest_snapshot.seller_address,
        seller_display_name: latest_snapshot.seller_display_name,
        seller_nip: latest_snapshot.seller_nip,
        seller_country_code: latest_snapshot.seller_country_code,
        seller_email: latest_snapshot.seller_email,
        seller_phone: latest_snapshot.seller_phone,
        payment_method: latest_snapshot.payment_method,
        account_number: latest_snapshot.account_number
    }
  end

  defp correction_invoice?(%CostInvoice{invoice_type: invoice_type}) do
    invoice_type in @correction_invoice_types
  end

  # sobelow_skip ["Traversal.FileModule"]
  # Path comes from Briefly.create/1 (OS-managed temp directory), not user input.
  def hydrate_invoice_with_fa3_blob(%CostInvoice{ksef_number: ksef_number, blob_id: blob_id} = invoice)
      when not is_nil(ksef_number) and is_nil(blob_id) do
    with {:ok, xml} <- Ksef.get_invoice_xml_by_ksef_number(ksef_number),
         {:ok, path} <- Briefly.create(extname: ".xml"),
         :ok <- File.write(path, xml),
         {:ok, blob} <- AshBlob.create_blob(path, "application/xml", "#{ksef_number}.xml", blob_opts()) do
      try do
        invoice
        |> CostInvoice.changeset(%{blob_id: blob.id})
        |> Repo.update!()
        |> Repo.preload(:blob, force: true)
        |> Map.put(:blob_url, AshBlob.get_url!(blob.id, blob_opts()))
      rescue
        error ->
          AshBlob.destroy_blob!(blob.id, blob_opts())
          reraise error, __STACKTRACE__
      end
    else
      {:error, reason} ->
        Logger.error("Failed to fetch KSeF XML for cost invoice #{invoice.id}: #{inspect(reason)}")
        invoice
    end
  end

  def hydrate_invoice_with_fa3_blob(%CostInvoice{} = invoice), do: invoice

  # TODO: replace authorize?: false with system actor once available
  # TODO: replace authorize?: false + actor: %{} with system actor once available
  defp blob_opts, do: [tenant: Repo.get_org_id(), authorize?: false, actor: %{}]
end
