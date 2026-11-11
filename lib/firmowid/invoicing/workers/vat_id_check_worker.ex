defmodule Firmowid.Invoicing.Workers.VatIdCheckWorker do
  @moduledoc """
  Checks the EU VAT numbers of saved counterparties: right after a number is saved
  (`EnqueueVatIdCheck`) and again every week.

  Each check applies the country's rules (`EuVatNumber`), then asks VIES. The
  result is stored on the counterparty, and the inbox lists the ones that are
  invalid or inactive.

  The daily cron run (no `organization_id`) queues one job per organization,
  which re-checks every counterparty never checked or last checked more than a
  week ago. A job with `counterparty_id` checks that counterparty only. When VIES
  does not answer, the previous result stays and the next daily run tries again.
  """
  use Oban.Worker, queue: :invoicing, max_attempts: 3

  alias Firmowid.Core
  alias Firmowid.Invoicing
  alias Firmowid.Invoicing.EuVatNumber
  alias Firmowid.Invoicing.EuVatReview
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
  end

  def perform(%Oban.Job{}) do
    # cross_tenant_reader: enumerate organization ids only; each check runs under
    # the organization's own vat_id_checker actor.
    [
      scope: %Scope{actor: %SystemActor{org_id: nil, role: :cross_tenant_reader}, tenant: nil}
    ]
    |> Core.list_organizations!()
    |> Enum.map(&new(%{organization_id: &1.id}))
    |> Firmowid.Oban.insert_all(skip_organization_id: true)

    :ok
  end

  defp scope(organization_id),
    do: %Scope{actor: %SystemActor{org_id: organization_id, role: :vat_id_checker}, tenant: organization_id}

  defp check(counterparty, scope) do
    case status(counterparty) do
      :unavailable ->
        :ok

      status ->
        Invoicing.record_counterparty_vat_id_check!(
          counterparty,
          %{vat_id_status: status, vat_id_checked_at: DateTime.utc_now()},
          scope: scope
        )
    end
  end

  defp status(counterparty) do
    case EuVatNumber.check(counterparty.country, counterparty.tax_id) do
      {:ok, number} -> EuVatReview.check_registration(counterparty.country, number)
      {:error, _rule, _suggestions} -> :invalid
    end
  end
end
