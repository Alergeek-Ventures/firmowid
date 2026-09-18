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

  alias Firmowid.Ash.Billing.PlanCatalog
  alias Firmowid.Ash.Blobs.Blob
  alias Firmowid.Ash.Checks.SystemActorRole
  alias Firmowid.Ash.Core.Changes.CleanupOldAvatarBlob
  alias Firmowid.Ash.Core.Changes.ClearVatExemptionFields
  alias Firmowid.Ash.Core.Changes.GenerateNickname
  alias Firmowid.Ash.Core.Changes.SetOwnerOrganization
  alias Firmowid.Ash.Core.User
  alias Firmowid.Ash.Core.Validations.ValidateNip
  alias Firmowid.Ash.Invoicing.VatExemption
  alias Firmowid.Ash.Resource

  require Resource

  @trial_days 30

  postgres do
    table "organizations"
    repo Firmowid.Repo

    custom_statements do
      statement :organizations_paradedb_search_idx do
        up """
        CREATE INDEX IF NOT EXISTS organizations_search_idx
        ON organizations
        USING bm25 (id, name, nip)
        WITH (key_field='id', text_fields='{
          "name": {"tokenizer": {"type": "ngram", "min_gram": 2, "max_gram": 4, "prefix_only": false}},
          "nip": {"tokenizer": {"type": "ngram", "min_gram": 2, "max_gram": 10, "prefix_only": true}}
        }');
        """

        down """
        DROP INDEX IF EXISTS organizations_search_idx;
        """
      end
    end
  end

  code_interface do
    define :destroy, action: :destroy
  end

  actions do
    defaults [:read]

    read :list do
      description "List organizations with optional search and plan filters."

      argument :search, :string

      argument :billing_plan, :atom do
        constraints one_of: PlanCatalog.plans()
      end

      prepare build(filter: expr(billing_plan == ^arg(:billing_plan))) do
        where present(:billing_plan)
      end

      prepare {Firmowid.Ash.Preparations.ParadeDBSearch, columns: ~w(name nip), argument: :search}
    end

    # ── Create ──────────────────────────────────────────────────────
    create :create do
      description "Create a new organization and assign its owner."

      accept [
        :name,
        :nip,
        :address,
        :is_vat_payer
      ]

      change set_attribute(:owner_id, actor(:id))
      change GenerateNickname
      change SetOwnerOrganization

      validate match(:nip, ~r/^[0-9]{10}$/)
      validate {ValidateNip, field: :nip}
    end

    # ── General update ──────────────────────────────────────────────
    update :update do
      description "Update general organization settings."
      primary? true
      require_atomic? false

      accept [
        :name,
        :nip,
        :address,
        :correspondence_address,
        :is_vat_payer,
        :allowed_sender_emails,
        :vat_exemption_type,
        :vat_exemption_basis
      ]

      change {ClearVatExemptionFields, []}

      validate match(:nip, ~r/^[0-9]{10}$/)
      validate {ValidateNip, field: :nip}
    end

    # ── Scoped updates ──────────────────────────────────────────────
    update :update_basic_info do
      description "Update the basic business details for an organization."
      require_atomic? false

      accept [
        :nip,
        :address,
        :correspondence_address,
        :name,
        :is_vat_payer,
        :vat_exemption_type,
        :vat_exemption_basis
      ]

      argument :is_same_correspondence_address, :boolean

      change {ClearVatExemptionFields, []}

      change set_attribute(:correspondence_address, nil),
        where: [argument_equals(:is_same_correspondence_address, true)]

      validate match(:nip, ~r/^[0-9]{10}$/)
      validate {ValidateNip, field: :nip}
    end

    update :update_billing_plan do
      description "Update the billing plan assigned to an organization."
      accept [:billing_plan]
    end

    update :update_avatar do
      description "Replace the organization's avatar blob."
      accept [:avatar_blob_id]
      require_atomic? false

      change CleanupOldAvatarBlob
    end

    # ── Sender email management ─────────────────────────────────────
    update :add_sender_email do
      description "Add an allowed sender email for organization email workflows."
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
      description "Remove an allowed sender email from the organization."
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
      description "Regenerate the inbound-email nickname for the organization."
      accept []
      require_atomic? false

      change GenerateNickname
    end

    # ── Destroy ─────────────────────────────────────────────────────
    destroy :destroy do
      description "Delete an organization and its dependent data."
      require_atomic? false
    end
  end

  policies do
    bypass actor_attribute_equals(:system_role, :superuser) do
      authorize_if always()
    end

    bypass {SystemActorRole, roles: [:billing_snapshotter, :cross_tenant_reader, :ksef_session]} do
      authorize_if action_type(:read)
    end

    policy action_type(:read) do
      authorize_if expr(id == ^actor(:organization_id))
    end

    # Organization onboarding is available only to an authenticated user who has
    # not joined an organization yet. The owner is always the acting user.
    policy [action_type(:create), actor_attribute_equals(:organization_id, nil)] do
      authorize_if always()
    end

    policy [
      action([
        :update,
        :update_basic_info,
        :update_avatar,
        :add_sender_email,
        :remove_sender_email,
        :regenerate_nickname
      ]),
      actor_attribute_equals(:role, :admin)
    ] do
      authorize_if expr(id == ^actor(:organization_id))
    end

    policy action(:update_billing_plan) do
      authorize_if actor_attribute_equals(:system_role, :superuser)
    end

    policy [action_type(:destroy), actor_attribute_equals(:role, :admin)] do
      authorize_if expr(id == ^actor(:organization_id))
    end
  end

  validations do
    validate present(:vat_exemption_basis) do
      where [attribute_equals(:vat_exemption_type, :other)]
      message "Podaj podstawę prawną zwolnienia z VAT."
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :name, :string, public?: true, allow_nil?: false
    attribute :nip, :string, public?: true, allow_nil?: false
    attribute :address, :string, public?: true
    attribute :correspondence_address, :string, public?: true
    attribute :is_vat_payer, :boolean, public?: true, default: true
    attribute :allowed_sender_emails, {:array, :string}, public?: true, default: []
    attribute :inbound_email_nickname, :string, public?: true, allow_nil?: false
    attribute :avatar_blob_id, :uuid, public?: true

    attribute :billing_plan, :atom,
      public?: true,
      allow_nil?: false,
      default: :przedsiebiorca,
      constraints: [one_of: PlanCatalog.plans()]

    attribute :vat_exemption_type, :atom,
      public?: true,
      allow_nil?: true,
      constraints: [one_of: VatExemption.valid_types()]

    attribute :vat_exemption_basis, :string,
      public?: true,
      allow_nil?: true,
      constraints: [max_length: 256, trim?: true, allow_empty?: false]

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :owner, User do
      allow_nil? false
      attribute_writable? true
    end

    belongs_to :avatar_blob, Blob do
      allow_nil? true
      attribute_writable? true
      define_attribute? false
      source_attribute :avatar_blob_id
    end

    has_many :users, User
  end

  calculations do
    calculate :vat_eu, :string, expr("PL" <> nip)

    calculate :on_trial?, :boolean, expr(inserted_at >= ago(@trial_days, :day))
  end

  identities do
    identity :unique_nickname, [:inbound_email_nickname]
  end
end
