defmodule Firmowid.Delegations.Delegation.List do
  @moduledoc "Composable, policy-scoped business trip listing filters."

  use Spark.Dsl.Fragment, of: Ash.Resource

  actions do
    read :list do
      description "List business trips with optional member, status and end-date filters."
      argument :member_id, :uuid

      argument :statuses, {:array, :atom},
        constraints: [
          items: [one_of: [:pending, :in_progress, :awaiting_signature, :submitted, :complete]]
        ]

      argument :ended_before, :date

      prepare build(sort: [inserted_at: :desc, id: :desc])

      prepare build(filter: expr(member_id == ^arg(:member_id))) do
        where present(:member_id)
      end

      prepare build(filter: expr(status in ^arg(:statuses))) do
        where present(:statuses)
      end

      prepare build(filter: expr(end_date < ^arg(:ended_before))) do
        where present(:ended_before)
      end
    end
  end
end
