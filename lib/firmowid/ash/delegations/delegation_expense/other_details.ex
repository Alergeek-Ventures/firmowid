defmodule Firmowid.Ash.Delegations.DelegationExpense.OtherDetails do
  @moduledoc "Other-expense details stored on a delegation expense."

  use Ash.Resource, data_layer: :embedded, embed_nil_values?: false

  attributes do
    attribute :description, :string,
      allow_nil?: false,
      default: "",
      constraints: [allow_empty?: true],
      public?: true
  end
end
