defmodule Firmowid.Ash.Assistant.Actions.ReadSalesInvoiceById do
  @moduledoc """
  Reads a single sales invoice by id for assistant use.
  """

  use Jido.Action,
    name: "get_sales_invoice_by_id",
    description: "Pobiera fakturę sprzedażową po identyfikatorze.",
    schema: [
      id: [type: :string, required: true]
    ],
    output_schema: [
      result: [type: {:list, :map}, required: true]
    ]

  alias Firmowid.Ash.Assistant.Actions.InvoiceSerialization
  alias Firmowid.Ash.Invoicing
  alias Firmowid.Ash.Scope

  @impl true
  def run(%{id: id}, %{scope: %Scope{} = scope}) do
    with {:ok, invoice} <- Invoicing.get_sales_invoice(id, load: [:gross_value], scope: scope) do
      {:ok, %{result: [InvoiceSerialization.serialize_sales_invoice(invoice)]}}
    end
  end

  def run(_params, _context), do: {:error, "Brakuje kontekstu uprawnień."}
end
