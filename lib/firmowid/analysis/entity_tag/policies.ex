defmodule Firmowid.Analysis.EntityTag.Policies do
  @moduledoc "Authorization policies for entity tags."
  use Spark.Dsl.Fragment, of: Ash.Resource, authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Checks.ActorRole
  alias Firmowid.Checks.AtLeastRole
  alias Firmowid.Checks.SystemActorRole

  policies do
    bypass {ActorRole, role: :admin} do
      authorize_if always()
    end

    bypass {SystemActorRole, roles: [:invoice_matcher, :analysis_classifier]} do
      authorize_if action_type(:read)
    end

    policy Firmowid.Checks.IsSystemActor do
      forbid_if always()
    end

    policy action_type(:read) do
      authorize_if always()
    end

    policy [
      action_type([:create, :update, :destroy]),
      {AtLeastRole, role: :accountant}
    ] do
      authorize_if always()
    end

    policy [action_type(:action), {AtLeastRole, role: :accountant}] do
      authorize_if always()
    end
  end
end
