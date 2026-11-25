defmodule Firmowid.Checks.PlanIncludes do
  @moduledoc """
  Policy check that returns true when the billing plan of the actor's
  organization includes a feature (see `Firmowid.Billing.PlanCatalog`).

  A `User` actor carries the plan on its member's organization, which
  `Firmowid.Core.load_member/2` loads; the member counts only inside its
  organization, as in `ActorRole.member/2`. A `SystemActor` always passes: the
  plans limit what people start, and background work finishes what they started.

  ## Options

  - `feature` — the feature the plan must include (required)

  ## Usage

  Declare it before an admin bypass, which would otherwise skip it:

      policy action(:create) do
        forbid_unless {PlanIncludes, feature: :delegations}
        authorize_if always()
      end
  """
  use Ash.Policy.SimpleCheck

  alias Firmowid.Billing.PlanCatalog
  alias Firmowid.Checks.ActorRole
  alias Firmowid.SystemActor

  @impl true
  def describe(opts), do: "the organization's plan includes #{inspect(Keyword.get(opts, :feature))}"

  @impl true
  def match?(%SystemActor{}, _context, _opts), do: {:ok, true}

  def match?(actor, context, opts) do
    case ActorRole.member(actor, context) do
      %{organization: %{billing_plan: plan}} ->
        {:ok, PlanCatalog.includes?(plan, Keyword.fetch!(opts, :feature))}

      %{id: id} ->
        raise ArgumentError, "the organization of the actor's member is not loaded: member #{id}"

      nil ->
        {:ok, false}
    end
  end
end
