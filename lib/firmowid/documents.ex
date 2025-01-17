defmodule Firmowid.Documents do
  import Ecto.Query, only: [from: 2, where: 3, order_by: 2]

  alias ExAws.S3
  alias MIME

  alias Firmowid.Repo
  alias Firmowid.Documents.Blob
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

  def get_processing_blobs_count() do
    # all blobs that exist and don't have cost_invoice metadata
    # they will be either processed or removed by Oban worker

    query =
      from b in Blob,
        left_join: ci in CostInvoice,
        on: b.id == ci.blob_id,
        where: is_nil(ci.id),
        select: b.id

    Repo.aggregate(query, :count, :id)
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
    |> Enum.map(&Map.put(&1, :file_url, get_blob_url(&1.blob_id, Repo.get_org_id())))
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
    |> Enum.map(&Map.put(&1, :file_url, get_blob_url(&1.blob_id, Repo.get_org_id())))
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
    |> Enum.map(&Map.put(&1, :file_url, get_blob_url(&1.id, organization_id)))
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
    |> Map.put(:file_url, get_blob_url(cost_invoice.blob_id, Repo.get_org_id()))
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
    delete_blob(blob_id, cost_invoice.organization_id)

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
    with {:ok, blob} <-
           Repo.transaction(fn ->
             {:ok, blob} = create_blob(upload_path, content_type, original_filename)

             %{
               name: "extract_cost_invoice_metadata",
               blob_id: blob.id,
               organization_id: blob.organization_id
             }
             |> Firmowid.Documents.Worker.new()
             |> Oban.insert!()

             broadcast_cost_invoice_list_updated(blob.organization_id)

             blob
           end) do
      {:ok, blob}
    else
      {:error, error} ->
        Sentry.capture_exception(error)

        {:error, :error}
    end
  end

  def get_blob!(id, organization_id) do
    Blob
    |> Repo.get!(id, organization_id: organization_id)
  end

  def delete_blob(id, organization_id) do
    blob =
      Blob
      |> Repo.get!(id, organization_id: organization_id)

    S3.delete_object(
      Application.get_env(:firmowid, :uploads_bucket),
      blob.blob_path,
      version_id: nil
    )
    |> ExAws.request!()

    blob
    |> Repo.delete!()
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

  def create_blob(upload_path, content_type, original_filename) do
    with organization_id <- Repo.get_org_id(),
         {:ok, blob} <-
           Repo.transaction(fn ->
             possible_extensions = MIME.extensions(content_type)
             extension = Enum.at(possible_extensions, 0, "pdf")
             upload_path = preprocess_blob(upload_path, extension)

             blob_id = UUIDv7.autogenerate()
             blob_path = "#{organization_id}/#{Path.basename("#{blob_id}.#{extension}")}"

             upload_path
             |> S3.Upload.stream_file()
             |> S3.upload(
               Application.get_env(:firmowid, :uploads_bucket),
               blob_path
             )
             |> ExAws.request!()

             %Blob{}
             |> Blob.changeset(%{
               id: blob_id,
               blob_path: blob_path,
               original_filename: original_filename,
               organization_id: organization_id
             })
             |> Repo.insert!()
           end) do
      {:ok, blob}
    else
      {:error, error} ->
        Sentry.capture_exception(error)

        {:error, :blob_creation_failed}
    end
  end

  def get_blob_url(id, organization_id) do
    blob =
      if organization_id == :skip_organization_id do
        Repo.get!(Blob, id, skip_organization_id: true)
      else
        Repo.get!(Blob, id, organization_id: organization_id)
      end

    {:ok, url} =
      :s3
      |> ExAws.Config.new([])
      |> S3.presigned_url(
        :get,
        Application.get_env(:firmowid, :uploads_bucket),
        blob.blob_path,
        expires_in: 200
      )

    url
  end

  def preprocess_blob(path, "pdf"), do: path

  # we only allow pdf and image/* in the upload
  def preprocess_blob(path, image_extension), do: shrink_image(path, image_extension)

  def shrink_image(image_path, image_extension) do
    with {:ok, path} <- Briefly.create(),
         image = Image.open!(image_path) do
      width = Image.width(image)
      height = Image.height(image)

      # Calculate scale while preventing division by zero
      scale =
        cond do
          width == 0 or height == 0 -> 1.0
          width > height -> min(1.0, 1000 / width)
          true -> min(1.0, 1000 / height)
        end

      # Only resize if the image is larger than 1000px
      resized_image =
        if scale < 1.0 do
          Image.resize!(image, scale)
        else
          image
        end

      # Convert stream to binary data before writing
      binary_data =
        resized_image
        |> Image.stream!(suffix: ".#{image_extension}")
        |> Enum.to_list()
        |> IO.iodata_to_binary()

      File.write!(path, binary_data)

      path
    end
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
