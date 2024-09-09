defmodule Firmowid.Documents do
  @pubsub_topic "documents"

  import Ecto.Query, warn: false

  alias ExAws.S3
  alias MIME

  alias Firmowid.Repo
  alias Firmowid.Documents.Document
  alias Firmowid.Documents.Reducto
  alias Firmowid.Documents.DocumentsTransactions

  def subscribe() do
    Phoenix.PubSub.subscribe(Firmowid.PubSub, @pubsub_topic)
  end

  def broadcast_document_update(document) do
    Phoenix.PubSub.broadcast(Firmowid.PubSub, @pubsub_topic, {:document_updated, document})
  end

  def list_documents_with_metadata(from \\ Date.utc_today(), to \\ Date.utc_today()) do
    Document
    # the ones with total_amount not being null
    |> where([d], not is_nil(d.total_amount))
    |> where(
      [d],
      (d.issue_date >= ^from and d.issue_date <= ^to) or
        (d.due_date >= ^from and d.due_date <= ^to)
    )
    |> order_by(desc: :issue_date)
    |> Repo.all()
    |> Repo.preload(:imported_transactions)
    |> Enum.map(&Map.put(&1, :file_url, get_file_url(&1.id)))
    |> Enum.map(
      &Map.put(
        &1,
        :amount,
        Money.from_float!(
          &1.total_amount,
          &1.currency
        )
      )
    )
  end

  def list_documents_without_metadata() do
    Document
    |> where([d], is_nil(d.total_amount))
    |> Repo.all()
    |> Enum.map(&Map.put(&1, :file_url, get_file_url(&1.id)))
  end

  def get_file_url(document_id) do
    document =
      Repo.get!(Document, document_id)

    {:ok, url} =
      :s3
      |> ExAws.Config.new([])
      |> S3.presigned_url(:get, "firmowid-documents", document.file_name, expires_in: 200)

    url
  end

  def create_document({upload_path, content_type}) do
    {:ok, document} =
      %Document{}
      |> Repo.insert()

    possible_extensions = MIME.extensions(content_type)
    extension = Enum.at(possible_extensions, 0, "pdf")
    file_name = Path.basename("#{document.id}.#{extension}")

    upload_path
    |> S3.Upload.stream_file()
    |> S3.upload("firmowid-documents", file_name)
    |> ExAws.request!()

    document
    |> Document.changeset(%{file_name: file_name})
    |> Repo.update()

    # TODO: add proper error handling (e.g. removal of document in case of upload
    # file)
  end

  def start_extraction_job(document_id) do
    Reducto.start_extraction_job(document_id)
  end

  def update_document(document_id, attrs) do
    result =
      Repo.get!(Document, document_id)
      |> Document.changeset(attrs)
      |> Repo.update!()

    broadcast_document_update(result)

    result
  end

  def delete_document(id) do
    changeset = Repo.get!(Document, id)

    S3.delete_object("firmowid-documents", changeset.file_name, version_id: nil)
    |> ExAws.request!()

    Repo.delete!(changeset)
  end

  def get_document(id) do
    document =
      Repo.get!(Document, id)
      |> Repo.preload(:imported_transactions)

    document =
      Map.merge(
        document,
        %{
          file_url: get_file_url(document.id),
          amount:
            Money.from_float!(
              document.currency,
              document.total_amount
            )
        }
      )

    document
  end

  def create_documents_imported_transactions_connection(document_id, imported_transaction_id) do
    %DocumentsTransactions{}
    |> DocumentsTransactions.changeset(%{
      document_id: document_id,
      imported_transaction_id: imported_transaction_id
    })
    |> Repo.insert!()
  end

  def delete_documents_imported_transactions_connection(document_id, imported_transaction_id) do
    Repo.get_by!(DocumentsTransactions,
      document_id: document_id,
      imported_transaction_id: imported_transaction_id
    )
    |> Repo.delete!()
  end
end
