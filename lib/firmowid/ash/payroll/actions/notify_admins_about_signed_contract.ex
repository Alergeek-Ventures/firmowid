defmodule Firmowid.Ash.Payroll.Actions.NotifyAdminsAboutSignedContract do
  @moduledoc """
  Emails active organization admins after an employee submits a signed
  employment contract.
  """

  use Ash.Resource.Actions.Implementation

  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Payroll
  alias Firmowid.Ash.Payroll.EmploymentContractEmails
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.SystemActor

  require Logger

  @impl true
  def run(%{arguments: %{signal: signal}}, _opts, _context) do
    contract_id = signal.contract_id

    scope = %Scope{
      actor: %SystemActor{org_id: signal.organization_id, role: :employment_contract_notifier},
      tenant: signal.organization_id
    }

    Logger.info("Sending employment contract admin email contract_id=#{contract_id}")

    case Payroll.get_employment_contract(contract_id,
           scope: scope,
           load: [member: :user],
           not_found_error?: false
         ) do
      {:ok, nil} ->
        Logger.warning("Employment contract not found contract_id=#{contract_id}")
        :ok

      {:ok, contract} ->
        notify_admins(contract, scope)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp notify_admins(contract, scope) do
    admins = list_admins(contract, scope)

    if Enum.empty?(admins) do
      Logger.info("No admin recipients for employment contract contract_id=#{contract.id}")
      :ok
    else
      with {:ok, _email} <-
             EmploymentContractEmails.deliver_signed_submitted_to_admins(
               admins,
               contract,
               contract.member
             ),
           do: :ok
    end
  end

  defp list_admins(contract, scope) do
    Core.list_users!(
      %{status: :active, role: :admin},
      query: [filter: [id: [not_eq: contract.member.user_id]]],
      scope: scope
    )
  end
end
