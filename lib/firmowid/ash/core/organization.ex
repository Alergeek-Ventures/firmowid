defmodule Firmowid.Ash.Core.Organization do
  @moduledoc """
  Ash resource for the `organizations` table.

  No multitenancy — organizations are the identity layer.
  Owns users, invites, and configuration like allowed sender emails
  and inbound email nickname.
  """
  use Ash.Resource,
    domain: Firmowid.Ash.Core,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Ash.Blobs.Blob
  alias Firmowid.Ash.Core.Changes.CleanupOldAvatarBlob
  alias Firmowid.Ash.Core.Changes.GenerateNickname
  alias Firmowid.Ash.Core.Changes.NullifyOrganizationUsers
  alias Firmowid.Ash.Core.Changes.SetOwnerOrganization
  alias Firmowid.Ash.Core.User
  alias Firmowid.Ash.Core.Validations.ValidateNip
  alias Firmowid.Ash.Resource

  require Resource

  postgres do
    table "organizations"
    repo Firmowid.Repo
    migrate? false
  end

  actions do
    defaults [:read]

    # ── Create ──────────────────────────────────────────────────────
    create :create do
      accept [
        :name,
        :nip,
        :address,
        :phone_number,
        :organization_type,
        :is_vat_payer
      ]

      argument :owner_id, :uuid, allow_nil?: false
      change manage_relationship(:owner_id, :owner, type: :append)
      change GenerateNickname
      change SetOwnerOrganization

      validate match(:nip, ~r/^[0-9]{10}$/)
      validate {ValidateNip, field: :nip}
    end

    # ── General update ──────────────────────────────────────────────
    update :update do
      accept [
        :name,
        :nip,
        :address,
        :phone_number,
        :organization_type,
        :correspondence_name,
        :correspondence_address,
        :is_vat_payer,
        :allowed_sender_emails
      ]

      validate match(:nip, ~r/^[0-9]{10}$/)
      validate {ValidateNip, field: :nip}
    end

    # ── Scoped updates ──────────────────────────────────────────────
    update :update_basic_info do
      accept [
        :nip,
        :address,
        :name,
        :phone_number,
        :organization_type,
        :is_vat_payer
      ]

      validate match(:nip, ~r/^[0-9]{10}$/)
      validate {ValidateNip, field: :nip}
    end

    update :update_correspondence do
      accept [:correspondence_name, :correspondence_address]
    end

    update :update_avatar do
      accept [:avatar_blob_id]
      require_atomic? false

      change CleanupOldAvatarBlob
    end

    # ── Sender email management ─────────────────────────────────────
    update :add_sender_email do
      accept []
      require_atomic? false
      argument :email, :string, allow_nil?: false

      change fn changeset, _context ->
        email = Ash.Changeset.get_argument(changeset, :email)
        current = Ash.Changeset.get_data(changeset, :allowed_sender_emails) || []

        if email in current do
          changeset
        else
          Ash.Changeset.change_attribute(changeset, :allowed_sender_emails, current ++ [email])
        end
      end
    end

    update :remove_sender_email do
      accept []
      require_atomic? false
      argument :email, :string, allow_nil?: false

      change fn changeset, _context ->
        email = Ash.Changeset.get_argument(changeset, :email)
        current = Ash.Changeset.get_data(changeset, :allowed_sender_emails) || []

        Ash.Changeset.change_attribute(
          changeset,
          :allowed_sender_emails,
          Enum.reject(current, &(&1 == email))
        )
      end
    end

    # ── Nickname regeneration ───────────────────────────────────────
    update :regenerate_nickname do
      accept []
      require_atomic? false

      change GenerateNickname
    end

    # ── Destroy ─────────────────────────────────────────────────────
    destroy :destroy do
      require_atomic? false

      change NullifyOrganizationUsers
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    # Org creation at registration — anyone can create an org
    policy action_type(:create) do
      authorize_if always()
    end

    policy action_type(:update) do
      authorize_if actor_attribute_equals(:role, :admin)
    end

    policy action_type(:destroy) do
      authorize_if actor_attribute_equals(:role, :admin)
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :name, :string, public?: true, allow_nil?: false
    attribute :nip, :string, public?: true, allow_nil?: false
    attribute :address, :string, public?: true
    attribute :phone_number, :string, public?: true
    attribute :organization_type, :string, public?: true
    attribute :correspondence_name, :string, public?: true
    attribute :correspondence_address, :string, public?: true
    attribute :is_vat_payer, :boolean, public?: true, default: true
    attribute :allowed_sender_emails, {:array, :string}, public?: true, default: []
    attribute :inbound_email_nickname, :string, public?: true, allow_nil?: false
    attribute :avatar_blob_id, :uuid, public?: true

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :owner, User do
      allow_nil? false
      attribute_writable? true
    end

    belongs_to :avatar_blob, Blob do
      attribute_writable? true
      define_attribute? false
      source_attribute :avatar_blob_id
    end

    has_many :users, User
  end

  calculations do
    calculate :vat_eu, :string, expr("PL" <> nip)
  end

  identities do
    identity :unique_nickname, [:inbound_email_nickname]
  end
end
