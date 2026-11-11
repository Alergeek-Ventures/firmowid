defmodule Firmowid.Invoicing.Workers.VatIdCheckWorker do
  @moduledoc """
  Periodically checks the EU VAT numbers of saved counterparties.

  The daily cron run (no `organization_id`) queues one job per organization. An
  organization's job checks each counterparty whose number was never checked or
  was last checked more than a week ago: first the country's rules
  (`EuVatNumber`), then VIES. The result is stored on the counterparty, and the
  inbox lists the ones that are invalid or inactive. When VIES does not answer,
  the previous result stays and the number is tried again on the next run.
  """
  use Oban.Worker, queue: :invoicing, max_attempts: 3

  alias Firmowid.Core
  alias Firmowid.Invoicing
  alias Firmowid.Invoicing.EuVatNumber
  alias Firmowid.Invoicing.EuVatReview
  alias Firmowid.Scope
  alias Firmowid.SystemActor

  @recheck_after_days 7

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"organization_id" => organization_id}}) do
    scope = %Scope{
      actor: %SystemActor{org_id: organization_id, role: :vat_id_checker},
      tenant: organization_id
    }

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
    |> Oban.insert_all()

    :ok
  end

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
