defmodule Firmowid.Ash.Payroll do
  @moduledoc """
  Ash domain for payroll and compensation.

  Manages employee salary records and payroll reporting. Separated from
  Timetracker because salary is an HR/payroll concern — not time-tracking.
  Cost calculations that combine salary with session data reference this
  domain's resources via cross-domain Ecto joins.
  """
  use Ash.Domain

  authorization do
    authorize(:by_default)
    require_actor?(true)
  end

  resources do
    resource(Firmowid.Ash.Payroll.UserSalary)
  end
end
