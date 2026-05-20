defmodule Firmowid.Ash.Assistant.PendingMatch do
  @moduledoc """
  Typed embedded proposal for a pending assistant invoice-to-transaction match.
  """

  use Ash.Resource,
    data_layer: :embedded,
    embed_nil_values?: false

  alias Firmowid.Ash.Assistant.PendingMatch.InvoiceRef

  actions do
    defaults create: [:message, :transaction_ids, :invoice_refs]

    read :read do
      description "Read embedded pending-match payloads."
      primary? true
    end

    destroy :destroy do
      description "Delete an embedded pending-match payload."
      primary? true
    end
  end

  attributes do
    attribute :message, :string do
      allow_nil? false
      public? true
    end

    attribute :transaction_ids, {:array, :uuid} do
      allow_nil? false
      public? true
      default []
    end

    attribute :invoice_refs, {:array, InvoiceRef} do
      allow_nil? false
      public? true
      default []
    end
  end
end
