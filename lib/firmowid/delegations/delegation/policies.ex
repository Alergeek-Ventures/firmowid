defmodule Firmowid.Delegations.Delegation.Policies do
  @moduledoc "Authorization policies for business trip delegations."
  use Spark.Dsl.Fragment, of: Ash.Resource, authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Checks.ActorRole
  alias Firmowid.Checks.SystemActorRole
  alias Firmowid.Delegations.Signals

  policies do
    bypass [{SystemActorRole, roles: [:avatar_cleanup]}, action(:read)] do
      authorize_if expr(
                     signed_command_blob_id == ^actor(:blob_id) or
                       signed_settlement_blob_id == ^actor(:blob_id)
                   )
    end

    bypass {ActorRole, role: :admin} do
      authorize_if always()
    end

    bypass {SystemActorRole, roles: [:leave_notifier]} do
      authorize_if action_type(:read)
    end

    policy action(:create) do
      authorize_if actor_present()
    end

    policy action(:notify_admins) do
      authorize_if signal_in(Signals, :delegation_submitted)
    end

    policy action(:notify_employee) do
      authorize_if signal_in(Signals, :delegation_approved)
    end

    policy action(:notify_admins_about_settlement) do
      authorize_if signal_in(Signals, :settlement_submitted)
    end

    policy action(:notify_employee_about_settlement) do
      authorize_if signal_in(Signals, :settlement_reviewed)
    end

    policy action_type(:read) do
      authorize_if expr(member_id == ^actor([:member, :id]))
    end

    policy action(:approve) do
      forbid_if always()
    end

    policy action(:prepare_command) do
      forbid_if always()
    end

    policy action([:prepare_settlement, :save_draft]) do
      authorize_if expr(status == :in_progress and member_id == ^actor([:member, :id]))
    end

    policy action(:edit_settlement) do
      authorize_if expr(status == :awaiting_signature and member_id == ^actor([:member, :id]))
    end

    policy action(:submit_for_review) do
      authorize_if expr(status == :awaiting_signature and member_id == ^actor([:member, :id]))
    end

    policy action([:accept_settlement, :return_settlement]) do
      forbid_if always()
    end

    policy action(:detect_dates) do
      authorize_if expr(status == :in_progress and member_id == ^actor([:member, :id]))
    end
  end
end
