defmodule Firmowid.Ash.Delegations.DelegationExpense.TransportDetails do
  @moduledoc "Transport-specific details stored on a delegation expense."

  use Ash.Resource, data_layer: :embedded, embed_nil_values?: false

  alias Firmowid.Ash.Delegations.DelegationExpense.Trip

  attributes do
    attribute :transport_type, :atom,
      allow_nil?: false,
      default: :other,
      public?: true,
      constraints: [one_of: [:railway, :airplane, :bus, :other]]

    attribute :trips, {:array, Trip}, allow_nil?: false, default: [], public?: true
  end
end
