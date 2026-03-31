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

  ## Notes

  `cost_invoices` is not a proper Ash relationship because `CostInvoice` is still
  an Ecto schema (migrating in Slice 4). The `:list_all` action uses `Repo.preload`
  in an after-action hook to load them.
  """
  use Ash.Resource,
    domain: Firmowid.Ash.Invoicing,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Ash.Resource

  require Ecto.Query
  require Resource

  postgres do
    table "inbound_emails"
    repo Firmowid.Repo
    migrate? false
  end

  code_interface do
    define :list_all, action: :list_all
    define :get, args: [:id], action: :by_id
    define :create
    define :mark_processed, args: [{:optional, :failure_reason}]
  end

  actions do
    defaults [:read]

    read :by_id do
      get_by [:id]
    end

    read :list_all do
      prepare build(sort: [received_at: :desc])

      prepare after_action(fn _query, results, _context ->
                ids = Enum.map(results, & &1.id)

                cost_invoices_by_email =
                  Firmowid.CostInvoices.CostInvoice
                  |> Ecto.Query.where([c], c.inbound_email_id in ^ids)
                  |> Firmowid.Repo.all()
                  |> Enum.group_by(& &1.inbound_email_id)

                results =
                  Enum.map(results, fn email ->
                    Map.put(email, :cost_invoices, Map.get(cost_invoices_by_email, email.id, []))
                  end)

                {:ok, results}
              end)
    end

    create :create do
      accept [
        :resend_email_id,
        :sender_email,
        :subject,
        :body,
        :received_at
      ]
    end

    update :mark_processed do
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
    policy action_type(:read) do
      authorize_if always()
    end

    policy action_type(:create) do
      authorize_if always()
    end

    policy action_type(:update) do
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
  end

  identities do
    identity :unique_resend_email_id, [:resend_email_id]
  end
end
