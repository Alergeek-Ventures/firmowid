defmodule Firmowid.Billing.Workers.PlanLimitsWorker do
  @moduledoc """
  Brings every organization's plan-limit decision up to date (see
  `Firmowid.Billing.PlanLimits.check/2`): starts a decision when usage goes above
  the plan, switches the excess off when the decision is overdue and ends it
  when usage fits again.

  Scheduling this job is what turns the plan limits on: without it no
  organization ever gets a decision day, so nobody is held or switched off. It
  runs daily at 09:00, after the 08:00 charges, so an organization that fell back
  to the free plan because its card was declined is checked the same day. Admins
  can buy a higher plan before they are asked to choose.
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
