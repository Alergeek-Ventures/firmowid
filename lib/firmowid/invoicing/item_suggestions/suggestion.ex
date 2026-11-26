defmodule Firmowid.Invoicing.ItemSuggestions.Suggestion do
  @moduledoc """
  One suggested sales invoice item: its name and, when the organization has
  already invoiced it, the quantity, unit, net unit price and VAT rate of its
  latest issued invoice, which choosing the suggestion fills in.
  """

  use Ash.Resource, data_layer: :embedded, embed_nil_values?: false

  attributes do
    attribute :name, :string, allow_nil?: false, public?: true

    attribute :quantity, :decimal, public?: true
    attribute :unit, :string, public?: true

    attribute :unit_price, :decimal,
      public?: true,
      description: "Net unit price in `currency`, filled in only on an invoice in the same currency."

    attribute :currency, :string, public?: true

    attribute :vat_rate, :string,
      public?: true,
      description: ~s(KSeF VAT rate code, e.g. "23" or "zw".)
  end
end
