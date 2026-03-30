defmodule Firmowid.Ash.Billing.Limits do
  @moduledoc """
  Ash resource for organization usage limits.

  Tracks monthly usage of cost/sales invoices and total bank connections.
  Invoice counts are reset by a cron job on the 1st of each month.

  No Ash multitenancy — billing operates cross-org by design. All operations
  take an explicit `organization_id` argument and bypass multitenancy filters.

  ## Design note: stored counters

  Usage counts (`*_used`) are stored as denormalized counters rather than
  derived from `COUNT(*)` on invoice/requisition tables. This is a deliberate
  trade-off for the PoC: O(1) reads, simple threshold checks, no cross-domain
  joins. The downside is a cron job for monthly resets and potential drift if
  an increment/decrement call is missed — acceptable for soft (informational)
  limits. If limits ever become hard-enforced, consider deriving counts from
  the source tables instead.

  ## Actions

    * `:read` — default read.
    * `:by_organization` — read: fetches limits for a given organization.
    * `:create` — creates a limits record for a new organization (called from
      `Accounts.create_organization`).
    * `:increment_counter` — update: atomically bumps a usage counter.
    * `:decrement_counter` — update: atomically decrements a usage counter (floor 0).
    * `:reset_counters` — update: sets monthly invoice counters to zero.
    * `:check` — generic action: checks if organization is within limits for a
      given resource type. Returns `:ok | {:warning, :over_limit, %{used, limit}}`.
    * `:increment` — generic action: reads record and runs `:increment_counter`.
    * `:decrement` — generic action: reads record and runs `:decrement_counter`.
    * `:usage_summary` — generic action: returns full usage summary map.
    * `:reset_monthly_counters` — generic action: bulk resets invoice counters.
  """
  use Ash.Resource,
    domain: Firmowid.Ash.Billing,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Ash.Resource

  require Resource

  @type limit_type :: :cost_invoices | :sales_invoices | :bank_connections

  postgres do
    table "organization_limits"
    repo Firmowid.Repo
    migrate? false
  end

  code_interface do
    define :create, args: [:organization_id], action: :create
    define :by_organization, args: [:organization_id], action: :by_organization
    define :check, args: [:organization_id, :type], action: :check
    define :increment, args: [:organization_id, :type], action: :increment
    define :decrement, args: [:organization_id, :type], action: :decrement
    define :usage_summary, args: [:organization_id], action: :usage_summary
    define :reset_monthly_counters, args: [], action: :reset_monthly_counters
  end

  actions do
    defaults [:read]

    create :create do
      accept [:organization_id]
      description "Create a limits record with defaults for a new organization."
    end

    read :by_organization do
      description "Fetch limits for a given organization."
      get? true

      argument :organization_id, :uuid_v7, allow_nil?: false

      filter expr(organization_id == ^arg(:organization_id))
    end

    update :increment_counter do
      description "Atomically increment the usage counter for a resource type."

      argument :type, :atom,
        allow_nil?: false,
        constraints: [one_of: [:cost_invoices, :sales_invoices, :bank_connections]]

      change Firmowid.Ash.Billing.Changes.IncrementCounter
    end

    update :decrement_counter do
      description "Atomically decrement the usage counter for a resource type (floor 0)."

      argument :type, :atom,
        allow_nil?: false,
        constraints: [one_of: [:cost_invoices, :sales_invoices, :bank_connections]]

      change Firmowid.Ash.Billing.Changes.DecrementCounter
    end

    update :reset_counters do
      description "Reset monthly invoice counters to zero."
      accept []

      change set_attribute(:cost_invoices_used, 0)
      change set_attribute(:sales_invoices_used, 0)
    end

    action :check, :term do
      description "Check if organization is within limits for a resource type."

      argument :organization_id, :uuid_v7, allow_nil?: false

      argument :type, :atom,
        allow_nil?: false,
        constraints: [one_of: [:cost_invoices, :sales_invoices, :bank_connections]]

      run fn input, context ->
        limits = get_limits!(input.arguments.organization_id, context)
        {used, limit} = get_usage_and_limit(limits, input.arguments.type)

        if used >= limit do
          {:ok, {:warning, :over_limit, %{used: used, limit: limit}}}
        else
          {:ok, :ok}
        end
      end
    end

    action :increment, :term do
      description "Increment the usage counter for a resource type."

      argument :organization_id, :uuid_v7, allow_nil?: false

      argument :type, :atom,
        allow_nil?: false,
        constraints: [one_of: [:cost_invoices, :sales_invoices, :bank_connections]]

      run fn input, context ->
        limits = get_limits!(input.arguments.organization_id, context)

        limits
        |> Ash.Changeset.for_update(:increment_counter, %{type: input.arguments.type},
          actor: context.actor,
          authorize?: false
        )
        |> Ash.update()
      end
    end

    action :decrement, :term do
      description "Decrement the usage counter for a resource type (floor 0)."

      argument :organization_id, :uuid_v7, allow_nil?: false

      argument :type, :atom,
        allow_nil?: false,
        constraints: [one_of: [:cost_invoices, :sales_invoices, :bank_connections]]

      run fn input, context ->
        limits = get_limits!(input.arguments.organization_id, context)

        limits
        |> Ash.Changeset.for_update(:decrement_counter, %{type: input.arguments.type},
          actor: context.actor,
          authorize?: false
        )
        |> Ash.update()
      end
    end

    action :usage_summary, :term do
      description "Returns full usage summary for an organization."

      argument :organization_id, :uuid_v7, allow_nil?: false

      run fn input, context ->
        limits = get_limits!(input.arguments.organization_id, context)

        {:ok,
         %{
           cost_invoices: build_usage_map(limits, :cost_invoices),
           sales_invoices: build_usage_map(limits, :sales_invoices),
           bank_connections: build_usage_map(limits, :bank_connections)
         }}
      end
    end

    action :reset_monthly_counters, :term do
      description "Reset monthly invoice counters for all organizations. Called by cron."

      run fn _input, context ->
        result =
          __MODULE__
          |> Ash.Query.new()
          |> Ash.bulk_update!(:reset_counters, %{},
            strategy: [:atomic],
            actor: context.actor,
            authorize?: false,
            return_records?: true,
            return_errors?: true
          )

        {:ok, %{reset_count: length(result.records)}}
      end
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if expr(organization_id == ^actor(:organization_id))
    end

    policy action_type(:action) do
      authorize_if actor_present()
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :organization_id, :uuid_v7, public?: true, allow_nil?: false

    attribute :cost_invoices_used, :integer, public?: true, default: 0
    attribute :cost_invoices_limit, :integer, public?: true, default: 100
    attribute :sales_invoices_used, :integer, public?: true, default: 0
    attribute :sales_invoices_limit, :integer, public?: true, default: 100
    attribute :bank_connections_used, :integer, public?: true, default: 0
    attribute :bank_connections_limit, :integer, public?: true, default: 5

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :organization, Firmowid.Ash.Core.Organization do
      define_attribute? false
      allow_nil? false
    end
  end

  identities do
    identity :unique_organization, [:organization_id]
  end

  # ── Private helpers ──────────────────────────────────────────────────

  defp get_limits!(organization_id, context) do
    __MODULE__
    |> Ash.Query.for_read(:by_organization, %{organization_id: organization_id},
      actor: context.actor,
      authorize?: false
    )
    |> Ash.read_one!()
  end

  defp get_usage_and_limit(limits, :cost_invoices), do: {limits.cost_invoices_used, limits.cost_invoices_limit}

  defp get_usage_and_limit(limits, :sales_invoices), do: {limits.sales_invoices_used, limits.sales_invoices_limit}

  defp get_usage_and_limit(limits, :bank_connections), do: {limits.bank_connections_used, limits.bank_connections_limit}

  defp build_usage_map(limits, type) do
    {used, limit} = get_usage_and_limit(limits, type)
    %{used: used, limit: limit, over_limit: used >= limit}
  end
end
