defmodule Firmowid.Ash.Payroll do
  @moduledoc """
  Ash domain for payroll and compensation.

  Manages employee salary records and payroll reporting. Separated from
  Timetracker because salary is an HR/payroll concern — not time-tracking.
  Cost calculations that combine salary with session data reference this
  domain's resources via cross-domain Ecto joins.
  """
  use Ash.Domain

  resources do
    resource Firmowid.Ash.Payroll.UserSalary do
      define :create_salary, action: :create
      define :bulk_create_salaries, action: :bulk_create_salaries, args: [:entries]
      define :list_salaries, action: :read
    end

    resource Firmowid.Ash.Payroll.UserEmploymentContract do
      define :create_employment_contract, action: :create
      define :list_employment_contracts, action: :read, args: [:user_id, :search]
      define :get_employment_contract, action: :get_by_id, args: [:id]
    end
  end

  authorization do
    authorize :by_default
    require_actor? true
  end
end
