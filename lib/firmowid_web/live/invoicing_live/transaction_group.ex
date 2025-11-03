defmodule FirmowidWeb.InvoicingLive.TransactionGroup do
  @moduledoc """
  Represents a group of cost transactions from the same party.
  Used for display purposes in the invoicing entries table.
  """

  defstruct [:id, :party, :total, :count, :currency, :date, :transactions]

  @type t :: %__MODULE__{
          id: String.t(),
          party: String.t(),
          total: Decimal.t(),
          count: integer(),
          currency: String.t(),
          date: Date.t(),
          transactions: [Firmowid.Finances.Transaction.t()]
        }
end
