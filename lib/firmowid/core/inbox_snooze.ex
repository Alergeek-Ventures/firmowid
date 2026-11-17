defmodule Firmowid.Core.InboxSnooze do
  @moduledoc """
  An inbox item the company put aside: hidden for everyone in the organization
  until `until`, or for good when `until` is nil. Items are named by the inbox's
  item ids (`FirmowidWeb.Inbox.Utilities.Queue`), e.g. `bank-<account id>`, so
  an item comes back on its own once its time is up.
  """
  use Ash.Resource,
    domain: Firmowid.Core,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    simple_notifiers: [Firmowid.Core.Notifiers.InboxChanged]

  alias Firmowid.Checks.AtLeastRole
  alias Firmowid.Resource

  require Resource

  postgres do
    table "inbox_snoozes"
    repo Firmowid.Repo

    references do
      reference :organization, on_delete: :delete
    end
  end

  actions do
    defaults [:read]

    read :list do
      description "List the items put aside now: for good or until a moment still ahead."
      filter expr(is_nil(until) or until > now())
    end

    create :snooze do
      description "Put an inbox item aside for everyone in the organization, for some days or for good."
      accept [:item_id]
      upsert? true
      upsert_identity :unique_item
      upsert_fields [:until, :updated_at]

      argument :days, :integer,
        constraints: [min: 1],
        description: "How many days the item stays aside; nil puts it aside for good."

      change fn changeset, _context ->
        until =
          case Ash.Changeset.get_argument(changeset, :days) do
            nil -> nil
            days -> DateTime.shift(DateTime.utc_now(), day: days)
          end

        Ash.Changeset.force_change_attribute(changeset, :until, until)
      end
    end

    destroy :restore do
      description "Bring an item put aside back to the inbox."
    end
  end

  policies do
    # Whoever sees an inbox item may put it aside for the company, and bring it back.
    policy always() do
      authorize_if {AtLeastRole, role: :employee}
    end
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :item_id, :string,
      allow_nil?: false,
      public?: true,
      description: "The inbox item's id, as `FirmowidWeb.Inbox.Utilities.Queue` builds it."

    attribute :until, :utc_datetime_usec,
      public?: true,
      description: "When the item comes back to the inbox; nil keeps it aside for good."

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :organization, Firmowid.Core.Organization do
      allow_nil? false
    end
  end

  identities do
    identity :unique_item, [:item_id]
  end
end
