defmodule Firmowid.Billing.Workers.PlanLimitsWorker do
  @moduledoc """
  Brings every organization's plan-limit decision up to date (see
  `Firmowid.Billing.PlanLimits.check/2`): starts a decision when usage goes above
  the plan, switches the excess off when the decision is overdue and ends it
  when usage fits again.

  Scheduling this job is what turns the plan limits on: without it no
  organization ever gets a decision day, so nobody is held or switched off. It is
  deliberately not in the Oban crontab until card payments exist, since admins
  must be able to buy a higher plan before they are asked to choose. It gets
  scheduled together with the payments.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 1

  alias Firmowid.Billing.PlanLimits
  alias Firmowid.Core
  alias Firmowid.Scope
  alias Firmowid.SystemActor

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: Oban.Worker.result()
  def perform(%Oban.Job{}) do
    scope = %Scope{actor: %SystemActor{org_id: nil, role: :cross_tenant_reader}, tenant: nil}

    # An organization whose check returns an error does not hold up the others; the
    # job then fails with the first error. A raised error ends the whole run.
    [scope: scope]
    |> Core.list_organizations!()
    |> Enum.map(&PlanLimits.check/1)
    |> Enum.find(:ok, &match?({:error, _error}, &1))
  end
end
