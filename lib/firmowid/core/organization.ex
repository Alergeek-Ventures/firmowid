# credo:disable-for-this-file AshCredo.Check.Refactor.LargeResource
# `:read_global` and `:end_trial` run only from the AshOban trigger.
# credo:disable-for-this-file AshCredo.Check.Design.MissingCodeInterface
defmodule Firmowid.Core.Organization do
  @moduledoc """
  Ash resource for the `organizations` table.

  No multitenancy — organizations are the identity layer.
  Owns members, invites, and organization configuration.
  """
  use Ash.Resource,
    domain: Firmowid.Core,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshOban]

  use Gettext, backend: Firmowid.Gettext

  alias AshOban.Checks.AshObanInteraction
  alias Firmowid.Analysis.IndustryTemplate
  alias Firmowid.Billing.PlanCatalog
  alias Firmowid.Billing.PlanLimits
  alias Firmowid.Billing.Subscription
  alias Firmowid.Blobs.Blob
  alias Firmowid.Checks.ActorRole
  alias Firmowid.Checks.AtLeastRole
  alias Firmowid.Checks.SystemActorRole
  alias Firmowid.Core
  alias Firmowid.Core.Changes.CleanupOldAvatarBlob
  alias Firmowid.Core.Changes.ClearVatExemptionFields
  alias Firmowid.Core.Changes.DefaultDisplayName
  alias Firmowid.Core.Changes.GenerateAvatarVariants
  alias Firmowid.Core.Changes.SetTrialEnd
  alias Firmowid.Core.User
  alias Firmowid.Core.Validations.NoActiveSubscription
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

  oban do
    triggers do
      # Before the 08:00 charges and the 09:00 plan limits check, which then sees the Free plan.
      trigger :end_trial do
        action :end_trial
        read_action :read_global
        where expr(trial_ends_on < fragment("(now() AT TIME ZONE 'Europe/Warsaw')::date"))
        scheduler_cron "0 5 * * *"
        max_attempts 3
        queue :billing_renewals

        worker_module_name Firmowid.Core.Organization.Worker.EndTrial
        scheduler_module_name Firmowid.Core.Organization.Scheduler.EndTrial
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

    read :read_global do
      description "Read for AshOban schedulers, across all organizations."
      pagination keyset?: true
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

      pipe_through [:company_details]
      change set_attribute(:owner_id, actor(:id))

      change set_attribute(:onboarding_completed_at, &DateTime.utc_now/0),
        where: [argument_equals(:start_onboarding, false)]

      change after_action(fn changeset, organization, _context ->
               owner_name = Ash.Changeset.get_argument(changeset, :owner_name)

               Core.add_to_organization!(
                 organization.owner_id,
                 organization.id,
                 :admin,
                 owner_name
               )

               {:ok, organization}
             end)
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

      pipe_through [:company_details]
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

      pipe_through [:company_details]

      change set_attribute(:correspondence_address, nil),
        where: [argument_equals(:is_same_correspondence_address, true)]
    end

    update :complete_onboarding do
      description "Mark the first steps of a just created organization as done."
      accept []
      change set_attribute(:onboarding_completed_at, &DateTime.utc_now/0)
    end

    update :remember_cash_accounting do
      description "Remember whether the last domestic invoice used cash accounting, for the next one to start with."
      accept [:is_cash_account]
    end

    update :update_billing_plan do
      description "Update the billing plan assigned to an organization; it replaces a running trial."
      accept [:billing_plan]
      require_atomic? false

      # A plan set by hand or bought is not taken away when the trial would have ended.
      change set_attribute(:trial_ends_on, nil)
      pipe_through [:plan_change]
    end

    update :grant_trial do
      description "Give a company that does not pay a paid plan for a number of months, without a card; granting again sets a new end."
      accept []
      require_atomic? false

      argument :plan, :atom, allow_nil?: false, constraints: [one_of: Subscription.plans()]
      argument :months, :integer, allow_nil?: false, constraints: [min: 1, max: 12]

      validate NoActiveSubscription
      change set_attribute(:billing_plan, arg(:plan))
      change SetTrialEnd, only_when_valid?: true
      change set_attribute(:trial_granted_at, &DateTime.utc_now/0)
      pipe_through [:plan_change]
    end

    update :end_trial do
      description "Return the organization to the Free plan once its trial has ended."
      accept []
      require_atomic? false

      change set_attribute(:billing_plan, :free)
      change set_attribute(:trial_ends_on, nil)
      pipe_through [:plan_change]
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
      change GenerateAvatarVariants
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

    bypass [AshObanInteraction, action([:read_global, :end_trial])] do
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

    bypass [{SystemActorRole, roles: [:billing]}, action([:read, :update_billing_plan])] do
      authorize_if expr(id == ^actor(:org_id))
    end

    # Actors built for one organization read only that organization; the classifier reads the
    # industry whose categories it chooses from, the invoice processor the seller of its invoices.
    bypass [
      {SystemActorRole,
       roles: [
         :analysis_classifier,
         :billing_snapshotter,
         :ksef_session,
         :sales_invoice_processor
       ]},
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

    # Whoever issues an invoice records its cash accounting for the next one.
    policy [action(:remember_cash_accounting), {AtLeastRole, role: :accountant}] do
      authorize_if expr(id == ^actor([:member, :organization_id]))
    end

    policy action([:update_billing_plan, :grant_trial]) do
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

    attribute :trial_ends_on, :date,
      public?: true,
      description:
        "The last day of a running trial of a paid plan granted without a card; the next day the plan returns to Free."

    attribute :trial_granted_at, :utc_datetime_usec,
      public?: true,
      description:
        "When a superuser last granted a trial; a company that had one gets no free month with its first subscription."

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

    attribute :is_cash_account, :boolean,
      public?: true,
      allow_nil?: false,
      default: false,
      description: "Whether the last domestic invoice used cash accounting (metoda kasowa); a new one starts with it."

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
    has_many :subscriptions, Subscription
  end

  pipelines do
    # Normalizes and validates the company details in every action that edits them.
    pipeline :company_details do
      change ClearVatExemptionFields
      change DefaultDisplayName
      validate match(:nip, ~r/^[0-9]{10}$/)
      validate {ValidateNip, field: :nip}
    end

    # Every change of the plan: a higher plan brings back what the lower one switched off, and a
    # subscription for another plan ends.
    pipeline :plan_change do
      # Qualified: the section also imports the preparation `after_action/1`.
      change Ash.Resource.Change.Builtins.after_action(fn changeset, organization, _context ->
               PlanLimits.plan_changed(organization, changeset.data.billing_plan)
             end)

      change Subscription.Changes.EndForOtherPlan
    end
  end

  calculations do
    calculate :vat_eu, :string, expr("PL" <> nip)

    calculate :on_trial?, :boolean, expr(inserted_at >= ago(@trial_days, :day))

    # A paid plan nobody pays for: set by hand, not bought.
    calculate :plan_granted?,
              :boolean,
              expr(billing_plan in ^Subscription.plans() and not has_active_subscription?)

    # A subscription starts with a free month until one was ever activated or a trial granted.
    calculate :free_month_available?,
              :boolean,
              expr(not has_activated_subscription? and is_nil(trial_granted_at))
  end

  # Plan limits are facts about the organization, so they do not depend on who may read its
  # subscriptions (a member, the plan limits job).
  aggregates do
    exists :has_active_subscription?, :subscriptions do
      filter expr(status == :active)
      authorize? false
    end

    exists :has_activated_subscription?, :subscriptions do
      filter expr(not is_nil(activated_at))
      authorize? false
    end
  end
end
