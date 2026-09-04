defmodule Firmowid.Ash.Delegations.DelegationExpense.Details do
  @moduledoc "Typed details stored for a delegation expense category."

  use Ash.Type.NewType,
    subtype_of: :union,
    constraints: [
      types: [
        transport: [
          type: Firmowid.Ash.Delegations.DelegationExpense.TransportDetails,
          tag: :type,
          tag_value: "transport"
        ],
        accommodation: [
          type: Firmowid.Ash.Delegations.DelegationExpense.AccommodationDetails,
          tag: :type,
          tag_value: "accommodation"
        ],
        other: [
          type: Firmowid.Ash.Delegations.DelegationExpense.OtherDetails,
          tag: :type,
          tag_value: "other"
        ]
      ]
    ]
end
