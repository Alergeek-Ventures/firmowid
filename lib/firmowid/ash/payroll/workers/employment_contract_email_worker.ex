defmodule Firmowid.Ash.Payroll.Workers.EmploymentContractEmailWorker do
  @moduledoc """
  Emails the employee about a contract waiting for their signature. Enqueued on
  contract creation when status is `pending_signature`, optionally scheduled for
  09:00 Europe/Warsaw on `signed_at`.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3

  alias Firmowid.Ash.Payroll
  alias Firmowid.Ash.Payroll.EmploymentContractEmails
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.SystemActor

  require Logger

  @doc "Enqueues employee notification email for a pending_signature contract."
  @spec enqueue(Ash.UUID.t(), Ash.UUID.t(), DateTime.t() | nil) ::
          {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue(contract_id, organization_id, scheduled_at \\ nil) do
    args = %{"contract_id" => contract_id, "organization_id" => organization_id}

    changeset =
      if scheduled_at do
        new(args, scheduled_at: scheduled_at)
      else
        new(args)
      end

    Firmowid.Oban.insert(changeset, organization_id: organization_id)
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    organization_id = args["organization_id"]
    contract_id = args["contract_id"]
    scope = scope(organization_id)

    Logger.info(
      "Sending employment contract employee email contract_id=#{contract_id} attempt=#{job.attempt}/#{job.max_attempts}"
    )

    case Payroll.get_employment_contract(contract_id,
           scope: scope,
           load: [:user],
           not_found_error?: false
         ) do
      {:ok, nil} ->
        Logger.warning("Employment contract not found contract_id=#{contract_id}")
        :ok

      {:ok, contract} ->
        handle_pending_signature_contract(contract, scope)

      {:error, reason} ->
        Logger.error("Failed to load employment contract contract_id=#{contract_id} reason=#{inspect(reason)}")

        {:error, reason}
    end
  end

  defp handle_pending_signature_contract(%{status: status} = contract, _scope) when status != :pending_signature do
    Logger.info(
      "Skipping employment contract employee email contract_id=#{contract.id} status=#{status} not pending_signature"
    )

    :ok
  end

  defp handle_pending_signature_contract(contract, scope) do
    signed_at = contract.signed_at || Date.utc_today()
    today = Date.utc_today()

    if Date.after?(signed_at, today) do
      Logger.info(
        "Skipping employment contract employee email contract_id=#{contract.id} signed_at=#{signed_at} not today=#{today}"
      )

      :ok
    else
      deliver_pending_signature(contract, scope)
    end
  end

  defp deliver_pending_signature(contract, scope) do
    case Ash.load(contract, :user, scope: scope) do
      {:ok, %{user: user}} when not is_nil(user) ->
        EmploymentContractEmails.deliver_pending_signature(user, contract)

      {:ok, %{user: nil}} ->
        Logger.warning("Employment contract has no user contract_id=#{contract.id}")
        :ok

      {:error, reason} ->
        Logger.error("Failed to load user for contract contract_id=#{contract.id} reason=#{inspect(reason)}")

        {:error, reason}
    end
  end

  defp scope(organization_id) do
    %Scope{
      actor: %SystemActor{org_id: organization_id, role: :employment_contract_notifier},
      tenant: organization_id
    }
  end
end
