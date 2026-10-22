defmodule Firmowid.Ash.Core.Member do
  @moduledoc """
  A user's membership in an organization.

  The account (`User`) authenticates; the member is that person inside one
  organization and carries their name, avatar, role and profile details
  (contact, bank account, birthday, addresses) there. Created when the user
  creates or joins the organization and removed together with the account (by
  the database) or the organization.

  The account's non-archived member is its active one: it decides which
  organization the account works in. An account has at most one: joining and
  restoring check it (see `RequireNoActiveMember`). Archiving a member detaches the account
  from the organization: it keeps signing in, but no longer reaches the
  organization until it is restored.

  Scoped by `organization_id` (attribute multitenancy).
  """
  use Ash.Resource,
    domain: Firmowid.Ash.Core,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Ash.Checks.OrganizationAdmin
  alias Firmowid.Ash.Checks.SystemActorRole
  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Core.Calculations.AcceptedLeaveDaysForYear
  alias Firmowid.Ash.Core.Calculations.SharedBirthday
  alias Firmowid.Ash.Core.Changes.RequireNoActiveMember
  alias Firmowid.Ash.Core.Member.Changes.DisconnectLiveSessions
  alias Firmowid.Ash.Core.UserRole
  alias Firmowid.Ash.Core.Validations.ValidateIban
  alias Firmowid.Ash.Resource

  require Resource

  postgres do
    table "members"
    repo Firmowid.Repo

    references do
      reference :user, on_delete: :delete
      reference :avatar_blob, on_delete: :nilify
    end
  end

  # The name, avatar and profile details carry the readers they had on the account:
  # the person, an organization admin, a superuser and the system actors that read
  # accounts. Other member readers (e.g. analysis) see only the membership itself.
  field_policies do
    private_fields :include

    field_policy [
      :name,
      :display_name,
      :avatar_blob_id,
      :phone,
      :slack_url,
      :bank_account_number,
      :birthday,
      :birthday_visibility,
      :correspondence_address,
      :residence_address,
      :shared_birthday
    ] do
      authorize_if expr(user_id == ^actor(:id))
      authorize_if OrganizationAdmin
      authorize_if actor_attribute_equals(:system_role, :superuser)

      authorize_if {SystemActorRole,
                    roles: [
                      :actor_member_loader,
                      :organization_cleanup,
                      :ksef_digest,
                      :billing_snapshotter,
                      :leave_notifier,
                      :hours_record_change_notifier,
                      :document_blob_processor,
                      :employment_contract_notifier
                    ]}
    end

    field_policy :* do
      authorize_if always()
    end
  end

  code_interface do
    define :create, action: :create
    define :get_active, action: :active, args: [:user_id], get?: true
    define :update_avatar, action: :update_avatar
    define :list, action: :read
    define :destroy, action: :destroy
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      description "Add a user to the organization, restoring their archived membership."
      accept [:user_id, :role, :name]
      upsert? true
      upsert_identity :unique_user
      upsert_fields [:role, :archived_at]
      change set_attribute(:archived_at, nil)
    end

    read :active do
      description "Read the account's active member, in whichever organization it is."
      get? true
      multitenancy :bypass

      argument :user_id, :uuid, allow_nil?: false

      filter expr(user_id == ^arg(:user_id) and is_nil(archived_at))

      # Accounts that joined two organizations before joining checked for an active
      # member keep the most recently updated one (the drop_user_organization
      # migration touches the one that was the account's organization).
      prepare build(sort: [updated_at: :desc, id: :desc], limit: 1)
    end

    update :update_role do
      description "Update the member's organization role."
      primary? true
      accept [:role]

      change DisconnectLiveSessions
    end

    update :update_profile do
      description "Update the member's profile details."
      require_atomic? false

      accept [
        :name,
        :phone,
        :slack_url,
        :bank_account_number,
        :birthday,
        :birthday_visibility,
        :correspondence_address,
        :residence_address
      ]

      argument :is_same_correspondence_address, :boolean

      validate present(:name), where: [changing(:name)]

      change update_change(:bank_account_number, fn
               nil ->
                 nil

               value ->
                 case String.trim(value) do
                   "" -> nil
                   trimmed -> trimmed
                 end
             end),
             where: [changing(:bank_account_number)]

      validate ValidateIban, where: [changing(:bank_account_number)]

      change set_attribute(:correspondence_address, nil),
        where: [argument_equals(:is_same_correspondence_address, true)]
    end

    update :update_avatar do
      description "Replace the member's avatar blob and clean up the previous one."
      accept [:avatar_blob_id]
      require_atomic? false

      validate Firmowid.Ash.Core.Validations.AvatarBlobInOrganization

      change Firmowid.Ash.Core.Changes.CleanupOldAvatarBlob
    end

    update :archive do
      description "Archive the member and cut their account's sessions."
      accept []
      require_atomic? false

      validate Firmowid.Ash.Core.Validations.NotSelfArchive

      # Only an active member is archived: the stored row must still be active, so
      # re-archiving an old membership cannot cut the sessions the account has in
      # the organization it works in now.
      change filter(expr(is_nil(archived_at)))
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
      description "Restore an archived member, making it their account's active member."
      accept []
      require_atomic? false

      change filter(expr(not is_nil(archived_at)))
      change {RequireNoActiveMember, user_id: :user_id}
      change set_attribute(:archived_at, nil)

      change DisconnectLiveSessions
    end
  end

  policies do
    bypass {SystemActorRole, roles: [:organization_owner_setup]} do
      authorize_if action(:create)
    end

    bypass [{SystemActorRole, roles: [:actor_member_loader]}, action(:active)] do
      authorize_if expr(user_id == ^actor(:user_id))
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
                      :analysis_reader,
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

    policy action(:update_profile) do
      authorize_if expr(id == ^actor([:member, :id]))
      authorize_if OrganizationAdmin
      authorize_if {SystemActorRole, roles: [:document_blob_processor]}
    end

    policy action(:update_avatar) do
      authorize_if expr(id == ^actor([:member, :id]))
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

    attribute :name, :string, public?: true
    attribute :avatar_blob_id, :uuid, public?: true

    attribute :phone, :string, public?: true
    attribute :slack_url, :string, public?: true
    attribute :bank_account_number, :string, public?: true
    attribute :birthday, :date, public?: false

    attribute :birthday_visibility, :atom,
      public?: true,
      allow_nil?: false,
      default: :not_shared,
      constraints: [one_of: [:not_shared, :day_with_month, :full_date]]

    attribute :correspondence_address, :string, public?: true
    attribute :residence_address, :string, public?: true

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

    belongs_to :avatar_blob, Firmowid.Ash.Blobs.Blob do
      allow_nil? true
      attribute_writable? true
      define_attribute? false
      source_attribute :avatar_blob_id
    end

    many_to_many :projects, Firmowid.Ash.Timetracker.Project do
      through Firmowid.Ash.Timetracker.ProjectUser
      source_attribute_on_join_resource :member_id
      destination_attribute_on_join_resource :project_id
    end

    has_many :leave_requests, Firmowid.Ash.Timetracker.LeaveRequest
    has_many :delegations, Firmowid.Ash.Delegations.Delegation
  end

  calculations do
    calculate :display_name,
              :string,
              expr(if(is_nil(name) or name == "", do: user.email, else: name)) do
      public? true
    end

    calculate :accepted_leave_days_for_year,
              :integer,
              {AcceptedLeaveDaysForYear, []} do
      public? true
      argument :year, :integer, allow_nil?: false
    end

    calculate :shared_birthday, :map, SharedBirthday do
      public? true
    end
  end

  identities do
    identity :unique_user, [:user_id]
  end
end
