defmodule Firmowid.Ash.Delegations.DelegationExpense.AccommodationDetails do
  @moduledoc "Accommodation-specific details stored on a delegation expense."

  use Ash.Resource, data_layer: :embedded, embed_nil_values?: false

  attributes do
    attribute :locality, :string,
      allow_nil?: false,
      default: "",
      constraints: [allow_empty?: true],
      public?: true

    attribute :arrival_date, :date, public?: true
    attribute :departure_date, :date, public?: true
    attribute :description, :string, public?: true
  end
end
