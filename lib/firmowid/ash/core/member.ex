defmodule Firmowid.Ash.Core.Member do
  @moduledoc """
  A user's membership in an organization.

  The account (`User`) authenticates; the member is that person inside one
  organization and carries their role there. Created when the user creates or
  joins the organization and removed together with the account or the
  organization.

  Scoped by `organization_id` (attribute multitenancy).
  """
  use Ash.Resource,
    domain: Firmowid.Ash.Core,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Ash.Checks.AccountCleanup
  alias Firmowid.Ash.Checks.OrganizationAdmin
  alias Firmowid.Ash.Checks.SystemActorRole
  alias Firmowid.Ash.Core.Member.Changes.DisconnectLiveSessions
  alias Firmowid.Ash.Core.UserRole
  alias Firmowid.Ash.Resource

  require Resource

  postgres do
    table "members"
    repo Firmowid.Repo
  end

  code_interface do
    define :create, action: :create
    define :list, action: :read
    define :destroy, action: :destroy
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      description "Add a user to the organization."
      accept [:user_id, :role]
    end

    update :update_role do
      description "Update the member's organization role."
      accept [:role]

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

      authorize_if AccountCleanup
    end

    policy action(:destroy) do
      authorize_if AccountCleanup
    end

    policy action(:update_role) do
      forbid_if expr(organization.owner_id == user_id)
      forbid_if expr(user_id == ^actor(:id))
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
