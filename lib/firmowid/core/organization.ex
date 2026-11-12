defmodule Firmowid.Core.Organization do
  @moduledoc """
  Ash resource for the `organizations` table.

  No multitenancy — organizations are the identity layer.
  Owns members, invites, and organization configuration.
  """
  use Ash.Resource,
    domain: Firmowid.Core,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  use Gettext, backend: Firmowid.Gettext

  alias Firmowid.Analysis.IndustryTemplate
  alias Firmowid.Billing.PlanCatalog
  alias Firmowid.Billing.PlanLimits
  alias Firmowid.Blobs.Blob
  alias Firmowid.Checks.ActorRole
  alias Firmowid.Checks.SystemActorRole
  alias Firmowid.Core.Changes.CleanupOldAvatarBlob
  alias Firmowid.Core.Changes.ClearVatExemptionFields
  alias Firmowid.Core.Changes.DefaultDisplayName
  alias Firmowid.Core.Changes.SetOwnerOrganization
  alias Firmowid.Core.User
  alias Firmowid.Core.Validations.ValidateNip
  alias Firmowid.Invoicing.VatExemption
  alias Firmowid.Resource

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

      pagination keyset?: true, required?: false

      argument :search, :string

      argument :billing_plan, :atom do
        constraints one_of: PlanCatalog.plans()
      end

      prepare build(filter: expr(billing_plan == ^arg(:billing_plan))) do
        where present(:billing_plan)
      end

      prepare {Firmowid.Preparations.ParadeDBSearch, columns: ~w(name nip)a, argument: :search}
    end

    # ── Create ──────────────────────────────────────────────────────
    create :create do
      description "Create a new organization and assign its owner."

      accept [
        :name,
        :display_name,
        :nip,
        :address,
        :is_vat_payer,
        :vat_exemption_type,
        :vat_exemption_basis,
        :industry,
        :bills_hourly
      ]

      argument :owner_name, :string,
        allow_nil?: false,
        description: "The owner's name, stored on their member."

      argument :start_onboarding, :boolean,
        default: false,
        description: "Whether the owner still takes the first steps, which the app leads them back to."

      change {ClearVatExemptionFields, []}
      change DefaultDisplayName
      change set_attribute(:owner_id, actor(:id))

      change set_attribute(:onboarding_completed_at, &DateTime.utc_now/0),
        where: [argument_equals(:start_onboarding, false)]

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
        :display_name,
        :nip,
        :address,
        :correspondence_address,
        :is_vat_payer,
        :industry,
        :bills_hourly,
        :vat_exemption_type,
        :vat_exemption_basis
      ]

      change {ClearVatExemptionFields, []}
      change DefaultDisplayName

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
        :display_name,
        :is_vat_payer,
        :industry,
        :bills_hourly,
        :vat_exemption_type,
        :vat_exemption_basis
      ]

      argument :is_same_correspondence_address, :boolean

      change {ClearVatExemptionFields, []}
      change DefaultDisplayName

      change set_attribute(:correspondence_address, nil),
        where: [argument_equals(:is_same_correspondence_address, true)]

      validate match(:nip, ~r/^[0-9]{10}$/)
      validate {ValidateNip, field: :nip}
    end

    update :complete_onboarding do
      description "Mark the first steps of a just created organization as done."
      accept []
      change set_attribute(:onboarding_completed_at, &DateTime.utc_now/0)
    end

    update :update_billing_plan do
      description "Update the billing plan assigned to an organization."
      accept [:billing_plan]
      require_atomic? false

      # A higher plan brings back what the lower one switched off.
      change after_action(fn changeset, organization, _context ->
               PlanLimits.plan_changed(organization, changeset.data.billing_plan)
             end)
    end

    update :update_plan_limit_decision do
      description "Record when admins must decide about usage above the plan limits, or that it fits the plan again."
      accept [:plan_limit_decision_on, :plan_limit_free_month_used_at]
    end

    update :update_avatar do
      description "Replace the organization's avatar blob."
      accept [:avatar_blob_id]
      require_atomic? false

      change CleanupOldAvatarBlob
    end

    # ── Destroy ─────────────────────────────────────────────────────
    destroy :destroy do
      description "Delete an organization and its dependent data."
      require_atomic? false
    end
  end

  policies do
    bypass [{SystemActorRole, roles: [:avatar_cleanup]}, action(:read)] do
      authorize_if expr(id == ^actor(:org_id) and avatar_blob_id == ^actor(:blob_id))
    end

    bypass actor_attribute_equals(:system_role, :superuser) do
      authorize_if always()
    end

    bypass {SystemActorRole, roles: [:cross_tenant_reader]} do
      authorize_if action_type(:read)
    end

    bypass [
      {SystemActorRole, roles: [:plan_limits]},
      action([:read, :update_plan_limit_decision])
    ] do
      authorize_if expr(id == ^actor(:org_id))
    end

    # Actors built for one organization read only that organization; the classifier reads the
    # industry whose categories it chooses from.
    bypass [
      {SystemActorRole, roles: [:analysis_classifier, :billing_snapshotter, :ksef_session]},
      action_type(:read)
    ] do
      authorize_if expr(id == ^actor(:org_id))
    end

    # Names the organizations the account can switch between.
    bypass [{SystemActorRole, roles: [:actor_member_loader]}, action_type(:read)] do
      authorize_if expr(exists(members, user_id == ^actor(:user_id) and is_nil(archived_at)))
    end

    policy action_type(:read) do
      authorize_if expr(id == ^actor([:member, :organization_id]))
    end

    # Any authenticated user may create an organization, also next to the ones
    # they already belong to. The owner is always the acting user.
    policy action_type(:create) do
      authorize_if actor_present()
    end

    policy [
      action([
        :update,
        :update_basic_info,
        :update_avatar,
        :complete_onboarding
      ]),
      {ActorRole, role: :admin}
    ] do
      authorize_if expr(id == ^actor([:member, :organization_id]))
    end

    policy action(:update_billing_plan) do
      authorize_if actor_attribute_equals(:system_role, :superuser)
    end

    policy [action_type(:destroy), {ActorRole, role: :admin}] do
      authorize_if expr(id == ^actor([:member, :organization_id]))
    end
  end

  validations do
    validate present(:vat_exemption_basis) do
      where [attribute_equals(:vat_exemption_type, :other)]
      message gettext_noop("Provide the legal basis for the VAT exemption.")
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :name, :string,
      public?: true,
      allow_nil?: false,
      description: "The full registered name, which invoices and KSeF carry."

    attribute :display_name, :string,
      public?: true,
      allow_nil?: false,
      description: "The short name the app shows, the full `name` unless set."

    attribute :nip, :string, public?: true, allow_nil?: false
    attribute :address, :string, public?: true
    attribute :correspondence_address, :string, public?: true
    attribute :is_vat_payer, :boolean, public?: true, default: true

    attribute :industry, :atom,
      public?: true,
      allow_nil?: false,
      default: :services,
      description: "The industry template the financial analysis follows.",
      constraints: [one_of: IndustryTemplate.industries()]

    attribute :bills_hourly, :boolean,
      public?: true,
      allow_nil?: false,
      default: true,
      description: "Whether the company bills clients by the hour, which shows time tracking and projects."

    attribute :onboarding_completed_at, :utc_datetime_usec,
      public?: true,
      description: "When the owner finished the first steps; until then the app leads admins back to them."

    attribute :avatar_blob_id, :uuid, public?: true

    attribute :billing_plan, :atom,
      public?: true,
      allow_nil?: false,
      default: :free,
      constraints: [one_of: PlanCatalog.plans()]

    attribute :plan_limit_decision_on, :date,
      public?: true,
      description:
        "The day from which admins must buy a higher plan or choose what stays switched on; nil while usage fits the plan."

    attribute :plan_limit_free_month_used_at, :utc_datetime_usec,
      public?: true,
      description: "When usage first went above a plan limit, which postponed the decision to the next month, once."

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

    has_many :members, Firmowid.Core.Member
  end

  calculations do
    calculate :vat_eu, :string, expr("PL" <> nip)

    calculate :on_trial?, :boolean, expr(inserted_at >= ago(@trial_days, :day))
  end
end
