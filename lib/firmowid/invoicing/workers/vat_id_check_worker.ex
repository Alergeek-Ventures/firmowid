defmodule Firmowid.Invoicing.Workers.VatIdCheckWorker do
  @moduledoc """
  Checks the tax IDs of saved counterparties, EU VAT numbers and Polish NIPs,
  and the organization's own NIP: right after a number is saved
  (`EnqueueVatIdCheck`, `EnqueueNipCheck`) and again every week.

  An EU VAT number is checked against its country's rules (`EuVatNumber`), then
  in VIES; a NIP in the VAT white list, KRS and CEIDG (`NipRegistration`). The
  result, with each register's answer for a NIP, is stored on the counterparty or
  the organization, and the inbox lists the problems.

  The daily cron run (no `organization_id`) queues one job per organization,
  which re-checks every counterparty and the organization's NIP never checked
  or last checked more than a week ago. A job with `counterparty_id` checks that
  counterparty only. When a register does not answer, the previous result stays
  and the next daily run tries again.
  """
  use Oban.Worker, queue: :vat_id_checks, max_attempts: 3

  alias Firmowid.Core
  alias Firmowid.Invoicing
  alias Firmowid.Invoicing.EuVatNumber
  alias Firmowid.Invoicing.EuVatReview
  alias Firmowid.Invoicing.NipRegistration
  alias Firmowid.Scope
  alias Firmowid.SystemActor

  require Ash.Query

  @recheck_after_days 7

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"organization_id" => organization_id, "counterparty_id" => counterparty_id}}) do
    scope = scope(organization_id)

    # Saving a new number clears its check, so it is due now.
    %{vat_id_due_before: DateTime.utc_now()}
    |> Invoicing.query_to_list_counterparties(scope: scope)
    |> Ash.Query.filter(id == ^counterparty_id)
    |> then(&Invoicing.list_counterparties!(%{}, scope: scope, query: &1))
    |> Enum.each(&check(&1, scope))
  end

  def perform(%Oban.Job{args: %{"organization_id" => organization_id}}) do
    scope = scope(organization_id)
    due_before = DateTime.shift(DateTime.utc_now(), day: -@recheck_after_days)

    %{vat_id_due_before: due_before}
    |> Invoicing.list_counterparties!(scope: scope)
    |> Enum.each(&check(&1, scope))

    # After the counterparties, so a failure here does not hold up their checks.
    organization = Core.get_organization!(organization_id, scope: scope)

    if is_nil(organization.nip_checked_at) or
         DateTime.before?(organization.nip_checked_at, due_before),
       do: check_organization(organization, scope),
       else: :ok
  end

  def perform(%Oban.Job{}), do: Firmowid.Oban.insert_per_organization(__MODULE__)

  defp scope(organization_id),
    do: %Scope{actor: %SystemActor{org_id: organization_id, role: :vat_id_checker}, tenant: organization_id}

  defp check(counterparty, scope) do
    case result(counterparty) do
      :unavailable ->
        :ok

      {status, registers} ->
        Invoicing.record_counterparty_vat_id_check!(
          counterparty,
          %{
            vat_id_status: status,
            nip_registers: registers,
            vat_id_checked_at: DateTime.utc_now()
          },
          scope: scope
        )
    end
  end

  defp check_organization(organization, scope) do
    case NipRegistration.check(organization.nip) do
      :unavailable ->
        :ok

      {status, registers} ->
        organization
        |> Core.record_organization_nip_check(
          %{nip_status: status, nip_registers: registers, nip_checked_at: DateTime.utc_now()},
          scope: scope
        )
        |> case do
          {:ok, _organization} -> :ok
          # The NIP changed meanwhile; its own check records the answer.
          {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Changes.StaleRecord{}]}} -> :ok
          {:error, error} -> raise error
        end
    end
  end

  defp result(%{country: "PL", tax_id: nip}), do: NipRegistration.check(nip)

  defp result(counterparty) do
    case EuVatNumber.check(counterparty.country, counterparty.tax_id) do
      {:ok, number} -> eu_result(EuVatReview.check_registration(counterparty.country, number))
      {:error, _rule, _suggestions} -> {:invalid, nil}
    end
  end

  defp eu_result(:unavailable), do: :unavailable
  defp eu_result(status), do: {status, nil}
end
