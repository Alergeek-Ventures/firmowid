defmodule Firmowid.Documents.Reducto do
  use GenServer

  alias Firmowid.Documents

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def start_extraction_job(document_id) do
    GenServer.cast(__MODULE__, {:extract_invoice_info, document_id})
  end

  @impl true
  def init(nil) do
    {:ok, nil}
  end

  @impl true
  def handle_cast({:extract_invoice_info, document_id}, state) do
    extract_invoice_info(document_id)

    {:noreply, state}
  end

  defp extract_invoice_info(document_id) do
    # file_url = Documents.get_file_url(document_id)
    #
    # invoice_extraction_schema = %{
    #   type: "object",
    #   properties: %{
    #     sale_date: %{
    #       type: "string",
    #       format: "date",
    #       description: "The date of the sale"
    #     },
    #     issue_date: %{
    #       type: "string",
    #       format: "date",
    #       description: "The issue date of the invoice"
    #     },
    #     due_date: %{
    #       type: "string",
    #       format: "date",
    #       description: "The payment deadline date"
    #     },
    #     seller: %{
    #       type: "string",
    #       description: "From whom the invoice is"
    #     },
    #     total_amount: %{
    #       type: "number",
    #       description: "The total amount of the invoice"
    #     },
    #     currency: %{
    #       type: "string",
    #       description:
    #         "The currency of the total amount of the invoice, as three letter ISO 4217 code"
    #     }
    #   },
    #   required: [
    #     "seller",
    #     "sale_date",
    #     "issue_date",
    #     "due_date",
    #     "total_amount",
    #     "currency"
    #   ]
    # }
    #
    # reducto_extract_response =
    #   Req.post!(
    #     "https://v1.api.reducto.ai/extract",
    #     auth:
    #       {:bearer,
    #        "f6db515168d1b7c99dcecfd0517062dcbfd083a6ba1e42d0e3bcc623d832288087949aa99728f0d65ff5da7044e9fecc"},
    #     json: %{
    #       document_url: file_url,
    #       async: %{
    #         enabled: false
    #       },
    #       schema: invoice_extraction_schema
    #     }
    #   )
    #
    # [extracted_metadata] = reducto_extract_response.body["result"]

    Process.sleep(5000)

    extracted_metadata = %{
      id: document_id,
      seller: "Reducto",
      issue_date: ~D[2020-01-01],
      sale_date: ~D[2020-01-01],
      due_date: ~D[2020-01-01],
      total_amount: 100.0,
      currency: "PLN"
    }

    Documents.update_document(document_id, extracted_metadata)
  end
end
