defmodule Firmowid.Ash.Core.Member do
  @moduledoc """
  A user's membership in an organization.

  The account (`User`) authenticates; the member is that person inside one
  organization and carries their role there. Created when the user creates or
  joins the organization and removed together with the account (by the
  database) or the organization.

  Archiving a member detaches the account from the organization: it keeps
  signing in, but no longer reaches the organization until it is restored.

  Scoped by `organization_id` (attribute multitenancy).
  """
  use Ash.Resource,
    domain: Firmowid.Ash.Core,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Ash.Checks.OrganizationAdmin
  alias Firmowid.Ash.Checks.SystemActorRole
  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Core.Member.Changes.DisconnectLiveSessions
  alias Firmowid.Ash.Core.UserRole
  alias Firmowid.Ash.Resource

  require Resource

  postgres do
    table "members"
    repo Firmowid.Repo

    references do
      reference :user, on_delete: :delete
    end
  end

  code_interface do
    define :create, action: :create
    define :list, action: :read
    define :destroy, action: :destroy
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      description "Add a user to the organization, restoring their archived membership."
      accept [:user_id, :role]
      upsert? true
      upsert_identity :unique_user
      upsert_fields [:role, :archived_at]
      change set_attribute(:archived_at, nil)
    end

    update :update_role do
      description "Update the member's organization role."
      primary? true
      accept [:role]

      change DisconnectLiveSessions
    end

    update :archive do
      description "Archive the member and detach their account from the organization."
      accept []
      require_atomic? false

      validate Firmowid.Ash.Core.Validations.NotSelfArchive
      change set_attribute(:archived_at, &Date.utc_today/0)

      change after_action(fn _changeset, member, context ->
               opts = Ash.Context.to_opts(context)

               with {:ok, user} <- Core.get_user(member.user_id, opts),
                    {:ok, _user} <- Core.leave_organization(user, opts) do
                 {:ok, member}
               end
             end)

      change DisconnectLiveSessions
    end

    update :unarchive do
      description "Restore an archived member and reattach their account to the organization."
      accept []
      require_atomic? false

      change set_attribute(:archived_at, nil)

      change after_action(fn _changeset, member, context ->
               opts = Ash.Context.to_opts(context)

               with {:ok, user} <- Core.get_user(member.user_id, opts),
                    {:ok, _user} <- Core.return_to_organization(user, opts) do
                 {:ok, member}
               end
             end)

      change DisconnectLiveSessions
    end
  end

  policies do
    bypass {SystemActorRole, roles: [:organization_owner_setup]} do
      authorize_if action(:create)
    end

    bypass [{SystemActorRole, roles: [:actor_member_loader]}, action(:read)] do
      authorize_if expr(
                     not is_nil(^actor(:org_id)) and organization_id == ^actor(:org_id) and
                       user_id == ^actor(:user_id)
                   )
    end

    bypass [{SystemActorRole, roles: [:organization_cleanup]}, action([:read, :destroy])] do
      authorize_if expr(not is_nil(^actor(:org_id)) and organization_id == ^actor(:org_id))
    end

    policy action(:read) do
      authorize_if expr(user_id == ^actor(:id))
      authorize_if OrganizationAdmin
      authorize_if actor_attribute_equals(:system_role, :superuser)

      authorize_if {SystemActorRole,
                    roles: [
                      :ksef_digest,
                      :billing_snapshotter,
                      :leave_notifier,
                      :hours_record_change_notifier,
                      :document_blob_processor,
                      :employment_contract_notifier
                    ]}
    end

    policy action(:update_role) do
      forbid_if expr(organization.owner_id == user_id)
      forbid_if expr(user_id == ^actor(:id))
      authorize_if OrganizationAdmin
    end

    policy action([:archive, :unarchive]) do
      forbid_if expr(organization.owner_id == user_id)
      authorize_if OrganizationAdmin
    end
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :role, :atom,
      public?: true,
      allow_nil?: false,
      constraints: [one_of: UserRole.roles()],
      default: :employee

    attribute :archived_at, :date, public?: true

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :user, Firmowid.Ash.Core.User do
      public? true
      allow_nil? false
      attribute_writable? true
    end

    belongs_to :organization, Firmowid.Ash.Core.Organization do
      allow_nil? false
    end
  end

  identities do
    identity :unique_user, [:user_id]
  end
end
