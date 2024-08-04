defmodule Firmowid.Documents do
  import Ecto.Query, warn: false
  alias ExAws.S3
  alias MIME

  alias Firmowid.Repo
  alias Firmowid.Documents.Document

  def list_documents_with_metadata() do
    # the ones with total_amount not being null
    Document
    |> where([d], not is_nil(d.total_amount))
    |> order_by(desc: :issue_date)
    |> Repo.all()
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

  defp get_file_url(document_id) do
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

  def delete_document(id) do
    changeset = Repo.get!(Document, id)

    S3.delete_object("firmowid-documents", changeset.file_name, version_id: nil)
    |> ExAws.request!()

    Repo.delete!(changeset)
  end

  def extract_invoice_info(document_id) do
    file_url = get_file_url(document_id)

    invoice_extraction_schema = %{
      type: "object",
      properties: %{
        sale_date: %{
          type: "string",
          format: "date",
          description: "The date of the sale"
        },
        issue_date: %{
          type: "string",
          format: "date",
          description: "The issue date of the invoice"
        },
        due_date: %{
          type: "string",
          format: "date",
          description: "The payment deadline date"
        },
        seller: %{
          type: "string",
          description: "From whom the invoice is"
        },
        total_amount: %{
          type: "number",
          description: "The total amount of the invoice"
        },
        currency: %{
          type: "string",
          description:
            "The currency of the total amount of the invoice, as three letter ISO 4217 code"
        }
      },
      required: [
        "seller",
        "sale_date",
        "issue_date",
        "due_date",
        "total_amount",
        "currency"
      ]
    }

    dbg(invoice_extraction_schema)

    reducto_extract_response =
      Req.post!(
        "https://v1.api.reducto.ai/extract",
        auth:
          {:bearer,
           "f6db515168d1b7c99dcecfd0517062dcbfd083a6ba1e42d0e3bcc623d832288087949aa99728f0d65ff5da7044e9fecc"},
        json: %{
          document_url: file_url,
          async: %{
            enabled: false
          },
          schema: invoice_extraction_schema
        }
      )

    [extracted_metadata] = reducto_extract_response.body["result"]
    dbg(extracted_metadata)

    document = Repo.get!(Document, document_id)

    document
    |> Document.changeset(extracted_metadata)
    |> Repo.update!()
  end
end
