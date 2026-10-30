defmodule Firmowid.Delegations.Delegation.PerDiemAttributes do
  @moduledoc "Trip times, provided meals, lump-sum claims and the NBP rate a delegation's per diem is calculated from."
  use Spark.Dsl.Fragment, of: Ash.Resource

  attributes do
    attribute :trip_started_at, :naive_datetime, public?: true
    attribute :trip_ended_at, :naive_datetime, public?: true
    attribute :abroad_started_at, :naive_datetime, public?: true
    attribute :abroad_ended_at, :naive_datetime, public?: true

    attribute :provided_breakfasts, :integer,
      allow_nil?: false,
      default: 0,
      public?: true,
      constraints: [min: 0]

    attribute :provided_lunches, :integer,
      allow_nil?: false,
      default: 0,
      public?: true,
      constraints: [min: 0]

    attribute :provided_dinners, :integer,
      allow_nil?: false,
      default: 0,
      public?: true,
      constraints: [min: 0]

    attribute :lump_sum_nights, :integer,
      allow_nil?: false,
      default: 0,
      public?: true,
      constraints: [min: 0],
      description: "Nights without an accommodation receipt, settled with the statutory lump sum."

    attribute :local_transport_lump_sum, :boolean,
      allow_nil?: false,
      default: false,
      public?: true,
      description: "Whether the employee claims the local transport lump sum."

    attribute :station_transfers, :integer,
      allow_nil?: false,
      default: 0,
      public?: true,
      constraints: [min: 0],
      description: "One-way transfers to or from a station or airport abroad."

    attribute :per_diem_nbp_rate, :decimal, public?: true
    attribute :per_diem_nbp_rate_date, :date, public?: true
  end
end
