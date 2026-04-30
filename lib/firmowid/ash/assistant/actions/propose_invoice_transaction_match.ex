defmodule Firmowid.Ash.Assistant.Actions.ProposeInvoiceTransactionMatch do
  @moduledoc """
  Saves a pending invoice-to-transaction match proposal for UI confirmation.
  """

  use Jido.Action,
    name: "propose_invoice_transaction_match",
    description: "Zapisuje propozycję połączenia faktur z transakcjami do potwierdzenia przez użytkownika.",
    schema: [
      message: [type: :string, required: true],
      transaction_ids: [type: {:list, :string}, required: true],
      cost_invoice_ids: [type: {:list, :string}, default: []],
      sales_invoice_ids: [type: {:list, :string}, default: []]
    ],
    output_schema: [
      status: [type: {:in, ["waiting_confirmation"]}, required: true],
      message: [type: :string, required: true],
      transaction_count: [type: :non_neg_integer, required: true],
      invoice_count: [type: :non_neg_integer, required: true]
    ]

  alias Firmowid.Ash.Assistant
  alias Firmowid.Ash.Assistant.InvoiceMatching.PendingMatches

  @impl true
  def run(params, %{session_id: session_id, scope: scope}) do
    with {:ok, session} <- Assistant.get_session(session_id, scope: scope),
         {:ok, pending_match} <- PendingMatches.build(params, scope),
         {:ok, _session} <-
           Assistant.propose_session_match(
             session,
             List.wrap(session.messages),
             pending_match,
             scope: scope
           ) do
      {:ok,
       %{
         status: "waiting_confirmation",
         message: pending_match.message,
         transaction_count: length(pending_match.transaction_ids),
         invoice_count: length(pending_match.invoice_refs)
       }}
    end
  end

  def run(_params, _context), do: {:error, "Brakuje kontekstu sesji asystenta."}
end
