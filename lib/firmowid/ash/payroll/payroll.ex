defmodule Firmowid.Ash.Payroll do
  @moduledoc """
  Ash domain for payroll and compensation.

  Manages employee salary records and payroll reporting. Separated from
  Timetracker because salary is an HR/payroll concern — not time-tracking.
  Cost calculations that combine salary with session data reference this
  domain's resources via cross-domain Ecto joins.
  """
  use Ash.Domain

  alias Firmowid.Ash.Payroll.UserEmploymentContract

  resources do
    resource Firmowid.Ash.Payroll.UserSalary do
      define :create_salary, action: :create
      define :bulk_create_salaries, action: :bulk_create_salaries, args: [:entries]
      define :list_salaries, action: :read
    end

    resource UserEmploymentContract do
      define :create_employment_contract, action: :create
      define :list_employment_contracts, action: :read
      define :get_employment_contract, action: :get_by_id, args: [:id]

      define :load_pending_contract,
        action: :load_pending_contract,
        args: [:user_id],
        get?: true,
        not_found_error?: false

      define :load_latest_contract,
        action: :load_latest_contract,
        args: [:user_id],
        get?: true,
        not_found_error?: false

      define :update_employment_contract, action: :update
      define :submit_signed, action: :submit_signed, args: [:upload_path, :upload_filename]
      define :activate, action: :activate
    end
  end

  authorization do
    authorize :by_default
    require_actor? true
  end
end
