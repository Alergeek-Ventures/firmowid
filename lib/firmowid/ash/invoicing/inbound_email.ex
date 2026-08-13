defmodule Firmowid.Ash.Invoicing.InboundEmail do
  @moduledoc """
  Ash resource for inbound emails received via Resend webhook.

  Each inbound email may produce zero or more cost invoices after processing.
  The worker validates the sender, downloads attachments, and marks the record
  as processed (with an optional failure reason).

  ## Actions

    * `:read` — default read
    * `:by_id` — fetch a single record by ID
    * `:list_all` — all emails ordered by `received_at` desc, with cost invoices preloaded
    * `:create` — webhook handler creates the record
    * `:mark_processed` — sets `processed_at` and optional `failure_reason`

  """
  use Ash.Resource,
    domain: Firmowid.Ash.Invoicing,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Ash.Checks.SystemActorRole
  alias Firmowid.Ash.Resource

  require Resource

  postgres do
    table "inbound_emails"
    repo Firmowid.Repo
  end

  code_interface do
    define :read, action: :read
    define :list_all, action: :list_all
    define :get, args: [:id], action: :by_id
    define :create
    define :mark_processed, args: [{:optional, :failure_reason}]
  end

  actions do
    defaults [:read]

    read :by_id do
      description "Fetch an inbound email by ID."
      get_by [:id]
    end

    read :list_all do
      description "List inbound emails ordered from newest to oldest."
      prepare build(sort: [received_at: :desc])
    end

    create :create do
      description "Create an inbound email record before processing attachments."

      accept [
        :resend_email_id,
        :sender_email,
        :subject,
        :body,
        :received_at
      ]
    end

    update :mark_processed do
      description "Mark an inbound email as processed with an optional failure reason."
      require_atomic? false
      accept []

      argument :failure_reason, :atom, constraints: [one_of: [:unexpected_sender, :no_attachment, :processing_failed]]

      change set_attribute(:processed_at, &DateTime.utc_now/0)

      change fn changeset, _context ->
        case Ash.Changeset.get_argument(changeset, :failure_reason) do
          nil -> changeset
          reason -> Ash.Changeset.force_change_attribute(changeset, :failure_reason, reason)
        end
      end
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :admin) do
      authorize_if always()
    end

    # cost_invoice_processor: read + mark_processed
    bypass {SystemActorRole, roles: [:cost_invoice_processor]} do
      authorize_if action_type(:read)
    end

    bypass {SystemActorRole, roles: [:cost_invoice_processor]} do
      authorize_if action(:create)
    end

    bypass {SystemActorRole, roles: [:cost_invoice_processor]} do
      authorize_if action(:mark_processed)
    end

    # Other system actors: no access
    policy Firmowid.Ash.Checks.IsSystemActor do
      forbid_if always()
    end

    # :invoicing and :accountant: read-only
    policy [action_type(:read), {Firmowid.Ash.Checks.AtLeastRole, role: :invoicing}] do
      authorize_if always()
    end
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :resend_email_id, :string, allow_nil?: false, public?: true
    attribute :sender_email, :string, allow_nil?: false, public?: true
    attribute :subject, :string, public?: true
    attribute :body, :string, public?: true
    attribute :received_at, :utc_datetime, allow_nil?: false, public?: true
    attribute :processed_at, :utc_datetime, public?: true

    attribute :failure_reason, :atom,
      public?: true,
      constraints: [one_of: [:unexpected_sender, :no_attachment, :processing_failed]]

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :organization, Firmowid.Ash.Core.Organization do
      allow_nil? false
    end

    has_many :cost_invoices, Firmowid.Ash.Invoicing.CostInvoice
  end

  identities do
    identity :unique_resend_email_id, [:resend_email_id]
  end
end
