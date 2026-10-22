defmodule Firmowid.Ash.Finances.Transaction.Policies do
  @moduledoc "Authorization policies for bank transactions."
  use Spark.Dsl.Fragment, of: Ash.Resource, authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Ash.Checks.ActorRole
  alias Firmowid.Ash.Checks.AtLeastRole
  alias Firmowid.Ash.Checks.SystemActorRole

  policies do
    bypass {ActorRole, role: :admin} do
      authorize_if always()
    end

    bypass [{SystemActorRole, roles: [:invoice_matcher]}, action_type(:read)] do
      authorize_if always()
    end

    bypass {SystemActorRole, roles: [:bank_sync]} do
      authorize_if action(:upsert_from_sync)
      authorize_if action_type(:read)
    end

    bypass {SystemActorRole, roles: [:analysis_reader, :ksef_digest]} do
      authorize_if action_type(:read)
    end

    # :invoicing and :accountant: read-only
    policy [action_type(:read), {AtLeastRole, role: :invoicing}] do
      authorize_if always()
    end

    policy [action(:invoice_suggestions), {AtLeastRole, role: :invoicing}] do
      authorize_if always()
    end

    # :accountant+: skipping and restoring transactions for matching
    policy [
      action([:set_skip_invoicing, :restore_for_matching]),
      {AtLeastRole, role: :accountant}
    ] do
      authorize_if always()
    end

    policy action([:connect_salary, :disconnect_salary, :salary_suggestions, :monthly_salaries]) do
      authorize_if {ActorRole, role: :admin}
    end

    # Write actions (non-system, non-admin): admin only
    policy action_type([:create, :destroy]) do
      authorize_if {ActorRole, role: :admin}
    end
  end
end
