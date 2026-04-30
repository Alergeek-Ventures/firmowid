defmodule Firmowid.Ash.Assistant.PendingMatch.InvoiceRef do
  @moduledoc """
  Typed embedded reference to an invoice selected for assistant matching.
  """

  use Ash.Resource,
    data_layer: :embedded,
    embed_nil_values?: false

  actions do
    defaults create: [:type, :id]

    read :read do
      primary? true
    end

    destroy :destroy do
      primary? true
    end
  end

  attributes do
    attribute :type, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:cost_invoice, :sales_invoice]
    end

    attribute :id, :uuid do
      allow_nil? false
      public? true
    end
  end
end
