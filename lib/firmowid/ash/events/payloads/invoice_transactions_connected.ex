defmodule Firmowid.Ash.Events.Payloads.InvoiceTransactionsConnected do
  @moduledoc """
  Typed payload for `*.connect_transactions` invoice events.
  """

  use Ash.Resource,
    data_layer: :embedded,
    embed_nil_values?: false

  actions do
    defaults create: [:transaction_ids, :source, :confidence_score, :matched_by]
  end

  attributes do
    attribute :transaction_ids, {:array, :uuid}, allow_nil?: false, public?: true

    attribute :source, :atom do
      public? true
      constraints one_of: [:manual, :auto_match]
    end

    attribute :confidence_score, :float, public?: true
    attribute :matched_by, :uuid, public?: true
  end
end
