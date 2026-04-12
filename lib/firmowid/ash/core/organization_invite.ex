defmodule Firmowid.Ash.Core.OrganizationInvite do
  @moduledoc """
  Ash resource for organization invites.

  Each invite has a unique code, an expiration date, and tracks who
  issued it and (optionally) who consumed it. Consuming an invite
  assigns the consuming user to the invite's organization.

  Scoped by `organization_id` (attribute multitenancy).
  """
  use Ash.Resource,
    domain: Firmowid.Ash.Core,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Ash.Core.Organization
  alias Firmowid.Ash.Core.User
  alias Firmowid.Ash.Resource
  alias Firmowid.Ash.SystemActor

  require Resource

  postgres do
    table "organization_invites"
    repo Firmowid.Repo
  end

  actions do
    defaults [:read]

    create :create do
      accept []

      argument :issued_by_id, :uuid, allow_nil?: false
      change manage_relationship(:issued_by_id, :issued_by, type: :append)

      change fn changeset, _context ->
        invite_code =
          20
          |> :crypto.strong_rand_bytes()
          |> Base.url_encode64()

        expires_at =
          DateTime.utc_now()
          |> DateTime.add(7, :day)
          |> DateTime.truncate(:second)

        changeset
        |> Ash.Changeset.change_attribute(:invite_code, invite_code)
        |> Ash.Changeset.change_attribute(:expires_at, expires_at)
      end
    end

    read :read_by_code do
      argument :invite_code, :string, allow_nil?: false

      filter expr(
               invite_code == ^arg(:invite_code) and
                 is_nil(consumed_by_id) and
                 is_nil(consumed_at) and
                 expires_at > now()
             )
    end

    update :consume do
      accept []
      require_atomic? false

      argument :user_id, :uuid, allow_nil?: false

      validate attribute_equals(:consumed_at, nil),
        message: "invite has already been consumed"

      change fn changeset, _context ->
        user_id = Ash.Changeset.get_argument(changeset, :user_id)

        changeset
        |> Ash.Changeset.change_attribute(:consumed_by_id, user_id)
        |> Ash.Changeset.change_attribute(
          :consumed_at,
          DateTime.truncate(DateTime.utc_now(), :second)
        )
      end

      change after_action(fn _changeset, invite, context ->
               user_id = invite.consumed_by_id
               organization_id = invite.organization_id

               bridge_opts =
                 case Map.get(context, :tenant) do
                   nil ->
                     [
                       actor: %SystemActor{
                         org_id: organization_id,
                         role: :organization_owner_setup,
                         user_id: user_id
                       }
                     ]

                   tenant ->
                     [
                       actor: %SystemActor{
                         org_id: organization_id,
                         role: :organization_owner_setup,
                         user_id: user_id
                       },
                       tenant: tenant
                     ]
                 end

               User
               |> Ash.get!(user_id, bridge_opts)
               |> Ash.Changeset.for_update(
                 :set_organization,
                 %{organization_id: organization_id},
                 bridge_opts
               )
               |> Ash.update!()

               {:ok, invite}
             end)
    end

    destroy :destroy do
    end
  end

  policies do
    # Default read — admin only (listing invites in org settings)
    policy action(:read) do
      authorize_if actor_attribute_equals(:role, :admin)
    end

    # Invite acceptance flow — anyone with the code can look up an invite
    policy action(:read_by_code) do
      authorize_if always()
    end

    policy action_type(:create) do
      authorize_if actor_attribute_equals(:role, :admin)
    end

    # Anyone with the code can consume the invite (the code is the auth)
    policy action(:consume) do
      authorize_if always()
    end

    policy action_type(:destroy) do
      authorize_if actor_attribute_equals(:role, :admin)
    end
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :expires_at, :utc_datetime, public?: true, allow_nil?: false
    attribute :consumed_at, :utc_datetime, public?: true
    attribute :invite_code, :string, public?: true, allow_nil?: false

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :organization, Organization do
      allow_nil? false
    end

    belongs_to :issued_by, User do
      allow_nil? false
      attribute_writable? true
    end

    belongs_to :consumed_by, User do
      attribute_writable? true
    end
  end
end
