defmodule Firmowid.Payroll.Signals do
  @moduledoc """
  Signals emitted by the Payroll domain for other resources to react to.
  """

  use Ash.Signals

  signals do
    signal :employment_contract_signed do
      description "An employee submitted their signed employment contract."
      argument :contract_id, :uuid, allow_nil?: false
      argument :organization_id, :uuid, allow_nil?: false
    end
  end
end
