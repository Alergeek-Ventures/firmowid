defmodule Firmowid.Ash.Invoicing.Types.InvoiceItemInput do
  @moduledoc "Typed invoice line input shared by preview and issuance."
  use Ash.Type.NewType,
    subtype_of: :map,
    constraints: [
      fields: [
        index: [type: :integer],
        name: [type: :string, allow_nil?: false],
        quantity: [type: :decimal, allow_nil?: false],
        unit: [type: :string, allow_nil?: false],
        unit_price: [type: :decimal, allow_nil?: false],
        vat_rate: [type: :string]
      ]
    ]
end
