defmodule Firmowid.Assistant.Message do
  @moduledoc "Append-only, ordered messages belonging to an authorized assistant session."
  use Ash.Resource,
    domain: Firmowid.Assistant,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  alias AshOban.Checks.AshObanInteraction
  alias Firmowid.Assistant.Conversation
  alias Firmowid.Checks.AtLeastRole

  postgres do
    table "assistant_messages"
    repo Firmowid.Repo

    references do
      reference :conversation, on_delete: :delete
      reference :organization, on_delete: :delete
    end

    custom_indexes do
      index [:conversation_id, :id]
    end
  end

  code_interface do
    define :create
    define :read
  end

  actions do
    defaults [:read]

    create :create do
      description "Appends a message through an authorized conversation relationship."
      primary? true
      accept [:role, :parts]
    end

    read :list do
      description "Lists authorized messages in their UUIDv7 order, optionally within a session."
      argument :conversation_id, :uuid
      filter expr(is_nil(^arg(:conversation_id)) or conversation_id == ^arg(:conversation_id))
      prepare build(sort: [id: :asc])

      pagination do
        required? false
        keyset? true
        default_limit 100
        max_page_size 100
      end
    end
  end

  policies do
    policy action_type(:create) do
      description "Only an authorized session action may append a message through its relationship."
      authorize_if accessing_from(Conversation, :messages)
    end

    policy action([:read, :list]) do
      authorize_if AshObanInteraction
      authorize_if relates_to_actor_via([:conversation, :user])
    end

    policy action([:read, :list]) do
      authorize_if AshObanInteraction
      authorize_if {AtLeastRole, role: :employee}
    end
  end

  pub_sub do
    module Phoenix.PubSub
    name Firmowid.PubSub
    prefix "assistant:conversation"
    transform fn notification -> {:assistant_updated, notification.data.conversation_id} end
    publish_all :create, [:conversation_id]
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  # Messages are append-only with no update action, so only their creation time is meaningful.
  # credo:disable-for-next-line AshCredo.Check.Design.MissingTimestamps
  attributes do
    uuid_v7_primary_key :id

    attribute :role, :atom,
      allow_nil?: false,
      constraints: [one_of: [:user, :assistant, :tool]]

    attribute :parts, {:array, :map}, allow_nil?: false, constraints: [min_length: 1]
    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :conversation, Conversation, allow_nil?: false
    belongs_to :organization, Firmowid.Core.Organization, allow_nil?: false
  end
end
