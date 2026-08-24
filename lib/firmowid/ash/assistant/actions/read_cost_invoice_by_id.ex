defmodule Firmowid.Ash.Assistant.Actions.ReadCostInvoiceById do
  @moduledoc """
  Reads a single cost invoice by id for assistant use.
  """

  use Jido.Action,
    name: "get_cost_invoice_by_id",
    description: "Pobiera fakturę kosztową po identyfikatorze.",
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
    with {:ok, invoice} <- Invoicing.get_cost_invoice(id, load: [:effective_amount], scope: scope) do
      {:ok, %{result: [InvoiceSerialization.serialize_cost_invoice(invoice)]}}
    end
  end

  def run(_params, _context), do: {:error, "Brakuje kontekstu uprawnień."}
end
