defmodule Firmowid.Timetracker.Signals do
  @moduledoc """
  Signals emitted by the Timetracker domain for other resources to react to.
  """

  use Ash.Signals

  signals do
    signal :leave_request_submitted do
      description "An employee submitted a leave or absence request."
      argument :leave_request_id, :uuid, allow_nil?: false
      argument :organization_id, :uuid, allow_nil?: false
    end

    signal :hours_record_change_requested do
      description "An employee asked to correct or cancel a submitted hours record."
      argument :hours_record_id, :uuid, allow_nil?: false
      argument :organization_id, :uuid, allow_nil?: false
    end
  end
end
