defmodule Firmowid.Documents do
  import Ecto.Query, warn: false

  alias ExAws.S3
  alias MIME

  alias Firmowid.Repo
  alias Firmowid.Documents.Document
  alias Firmowid.Documents.Reducto
  alias Firmowid.Documents.DocumentsTransactions

  @pub_sub_topic "documents"

  def subscribe_to_documents_changes() do
    Phoenix.PubSub.subscribe(Firmowid.PubSub, @pub_sub_topic)
  end

  def broadcast_document_change(document_id) do
    Phoenix.PubSub.broadcast(
      Firmowid.PubSub,
      @pub_sub_topic,
      {:document_changed, document_id}
    )
  end

  def list_documents_with_metadata(
        organization_id,
        from \\ Date.utc_today(),
        to \\ Date.utc_today()
      ) do
    Document
    # the ones with total_amount not being null
    |> where([d], not is_nil(d.total_amount))
    |> where(
      [d],
      (d.issue_date >= ^from and d.issue_date <= ^to) or
        (d.due_date >= ^from and d.due_date <= ^to) or
        (d.sale_date >= ^from and d.sale_date <= ^to)
    )
    |> order_by(desc: :issue_date)
    |> Repo.all(organization_id: organization_id)
    |> Repo.preload(:imported_transactions, organization_id: organization_id)
    |> Enum.map(&Map.put(&1, :file_url, get_file_url(&1.id, organization_id)))
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
    |> Enum.filter(fn document ->
      # don't include documents that are issued for previous month and were
      # paid in previous month

      was_paid =
        document.imported_transactions != [] or
          document.skip_invoicing == true

      was_issued_in_date_range =
        Date.compare(from, document.issue_date) == :lt and
          Date.compare(to, document.issue_date) == :gt

      !was_paid or (was_paid and was_issued_in_date_range)
    end)
  end

  def list_documents_without_metadata(organization_id) do
    Document
    |> where([d], is_nil(d.total_amount))
    |> Repo.all(organization_id: organization_id)
    |> Enum.map(&Map.put(&1, :file_url, get_file_url(&1.id, organization_id)))
  end

  def list_unmatched_documents(organization_id) do
    from(d in Document,
      left_join: i in assoc(d, :imported_transactions),
      where: not is_nil(d.total_amount),
      group_by: d.id,
      having: count(i.id) == 0,
      select: d
    )
    |> Repo.all(organization_id: organization_id)
    |> Enum.map(&Map.put(&1, :file_url, get_file_url(&1.id, organization_id)))
  end

  def get_file_url(document_id, organization_id) do
    document =
      Repo.get!(Document, document_id, organization_id: organization_id)

    {:ok, url} =
      :s3
      |> ExAws.Config.new([])
      |> S3.presigned_url(
        :get,
        Application.get_env(:firmowid, :uploads_bucket),
        document.file_name,
        expires_in: 200
      )

    url
  end

  def create_document({upload_path, content_type}, organization_id) do
    case Repo.insert(%Document{organization_id: organization_id}) do
      {:ok, document} ->
        possible_extensions = MIME.extensions(content_type)
        extension = Enum.at(possible_extensions, 0, "pdf")

        upload_path =
          if extension != "pdf" do
            {:ok, path} = Briefly.create()

            # resize image down, so that's it's max size is 1000x1000
            image = Image.open!(upload_path)
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

            # Ensure extension starts without a dot
            clean_extension = String.trim_leading(extension, ".")

            # Convert stream to binary data before writing
            binary_data =
              resized_image
              |> Image.stream!(suffix: ".#{clean_extension}")
              |> Enum.to_list()
              |> IO.iodata_to_binary()

            File.write!(path, binary_data)

            path
          else
            upload_path
          end

        file_name = "#{organization_id}/#{Path.basename("#{document.id}.#{extension}")}"

        with _ <-
               upload_path
               |> S3.Upload.stream_file()
               |> S3.upload(
                 Application.get_env(:firmowid, :uploads_bucket),
                 file_name
               )
               |> ExAws.request!(),
             {:ok, _} <-
               document
               |> Document.changeset(%{file_name: file_name})
               |> Repo.update() do
          {:ok, document}
        else
          _ ->
            Repo.delete!(document)
            {:error, :operation_failed}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def start_extraction_job(document_id, organization_id) do
    Reducto.start_extraction_job(document_id, organization_id)
  end

  def update_document(organization_id, document_id, attrs) do
    result =
      Repo.get!(Document, document_id, organization_id: organization_id)
      |> Document.changeset(attrs)
      |> Repo.update!()

    broadcast_document_change(document_id)

    result
  end

  def delete_document(organization_id, id) do
    changeset = Repo.get!(Document, id, organization_id: organization_id)

    S3.delete_object(
      Application.get_env(:firmowid, :uploads_bucket),
      changeset.file_name,
      version_id: nil
    )
    |> ExAws.request!()

    Repo.delete!(changeset, organization_id: organization_id)

    broadcast_document_change(id)
  end

  def get_document(organization_id, id) do
    document =
      Repo.get!(Document, id, organization_id: organization_id)
      |> Repo.preload(:imported_transactions, organization_id: organization_id)

    document =
      Map.merge(
        document,
        %{
          file_url: get_file_url(document.id, organization_id),
          amount:
            Money.new(
              document.currency,
              document.total_amount
            )
        }
      )

    document
  end

  def create_documents_imported_transactions_connection(
        document_id,
        imported_transaction_id,
        organization_id
      ) do
    %DocumentsTransactions{}
    |> DocumentsTransactions.changeset(%{
      document_id: document_id,
      imported_transaction_id: imported_transaction_id,
      organization_id: organization_id
    })
    |> Repo.insert!()

    broadcast_document_change(document_id)
  end

  def delete_documents_imported_transactions_connection(
        organization_id,
        document_id,
        imported_transaction_id
      ) do
    Repo.get_by!(
      DocumentsTransactions,
      [document_id: document_id, imported_transaction_id: imported_transaction_id],
      organization_id: organization_id
    )
    |> Repo.delete!()

    broadcast_document_change(document_id)
  end
end
