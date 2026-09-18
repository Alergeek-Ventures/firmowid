defmodule Firmowid.Ash.Delegations.DelegationExpense.Trip do
  @moduledoc "One route segment recorded on a transport expense document."

  use Ash.Resource, data_layer: :embedded, embed_nil_values?: false

  validations do
    validate compare(:arrival_datetime, greater_than_or_equal_to: :departure_datetime),
      where: [present(:arrival_datetime), present(:departure_datetime)],
      message: "musi być po lub o tej samej godzinie co wyjazd"
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :departure_city, :string,
      allow_nil?: false,
      default: "",
      constraints: [allow_empty?: true],
      public?: true

    attribute :departure_datetime, :utc_datetime, public?: true

    attribute :arrival_city, :string,
      allow_nil?: false,
      default: "",
      constraints: [allow_empty?: true],
      public?: true

    attribute :arrival_datetime, :utc_datetime, public?: true
    attribute :description, :string, public?: true
  end
end
