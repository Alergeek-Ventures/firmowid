defmodule Firmowid.Ash.Assistant.InvoiceMatchingAgent do
  @moduledoc """
  Jido AI agent for universal invoice-to-transaction matching.
  """

  use Jido.AI.Agent,
    name: "firmowid_invoice_matching_agent",
    model: :capable,
    max_iterations: 30,
    system_prompt: "Pomagasz łączyć faktury z transakcjami.",
    tools: []
end
