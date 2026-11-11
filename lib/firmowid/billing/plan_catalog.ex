defmodule Firmowid.Billing.PlanCatalog do
  @moduledoc """
  Shared source of truth for billing plan rules: the price of each plan and the
  limits it includes, as the pricing page offers them.

  `:no_plan` is not an offer. It marks an organization whose access is blocked
  (see the `:access_block` calculation on `Firmowid.Core.User`).
  """

  @type plan :: :no_plan | :free | :przedsiebiorca | :firma
  @type offered_plan :: :free | :przedsiebiorca | :firma
  @type money_amount :: Decimal.t()
  @type limited :: :users | :synced_bank_accounts | :active_projects
  @type limit :: non_neg_integer() | :unlimited

  @type plan_rules :: %{
          plan: plan(),
          monthly_price_pln: money_amount(),
          yearly_price_pln: money_amount(),
          limits: %{required(limited()) => limit()}
        }

  @typedoc """
  What an organization uses of each limited thing. `active_projects` is `nil`
  for months frozen before projects were counted.
  """
  @type usage :: %{
          users: non_neg_integer(),
          synced_bank_accounts: non_neg_integer(),
          active_projects: non_neg_integer() | nil
        }

  @plans [:no_plan, :free, :przedsiebiorca, :firma]

  # Cheapest first, so the first plan that covers the usage is the cheapest one.
  @offered_plans [:free, :przedsiebiorca, :firma]

  @doc """
  Returns all supported billing plans in stable order.
  """
  @spec plans() :: [plan()]
  def plans, do: @plans

  @doc """
  Returns structured billing rules for a single plan.
  """
  @spec plan!(plan()) :: plan_rules()
  def plan!(:no_plan) do
    %{
      plan: :no_plan,
      monthly_price_pln: decimal("0"),
      yearly_price_pln: decimal("0"),
      limits: %{users: 0, synced_bank_accounts: 0, active_projects: 0}
    }
  end

  def plan!(:free) do
    %{
      plan: :free,
      monthly_price_pln: decimal("0"),
      yearly_price_pln: decimal("0"),
      limits: %{users: 2, synced_bank_accounts: 1, active_projects: 3}
    }
  end

  def plan!(:przedsiebiorca) do
    %{
      plan: :przedsiebiorca,
      monthly_price_pln: decimal("29"),
      yearly_price_pln: decimal("276"),
      limits: %{users: 5, synced_bank_accounts: 3, active_projects: :unlimited}
    }
  end

  def plan!(:firma) do
    %{
      plan: :firma,
      monthly_price_pln: decimal("149"),
      yearly_price_pln: decimal("1428"),
      limits: %{users: :unlimited, synced_bank_accounts: :unlimited, active_projects: :unlimited}
    }
  end

  @doc """
  Returns all plan rules keyed by plan identifier.
  """
  @spec all() :: %{required(plan()) => plan_rules()}
  def all do
    Map.new(@plans, &{&1, plan!(&1)})
  end

  @doc """
  Maps the usage facts of a billing snapshot to the things the plans limit.

  The owner counts as a user, as on the pricing page.
  """
  @spec usage(%{
          required(:synced_bank_accounts_count) => non_neg_integer(),
          required(:active_non_owner_users_count) => non_neg_integer(),
          optional(atom()) => term()
        }) :: usage()
  def usage(%{synced_bank_accounts_count: bank_accounts, active_non_owner_users_count: non_owner_users} = facts) do
    %{
      users: non_owner_users + 1,
      synced_bank_accounts: bank_accounts,
      active_projects: Map.get(facts, :active_projects_count)
    }
  end

  @doc """
  Returns the cheapest offered plan whose limits cover the usage.
  """
  @spec fitting_plan(usage()) :: offered_plan()
  def fitting_plan(usage) do
    Enum.find(@offered_plans, fn plan ->
      Enum.all?(plan!(plan).limits, fn {limited, limit} -> within?(usage[limited], limit) end)
    end)
  end

  defp within?(_count, :unlimited), do: true
  defp within?(nil, _limit), do: true
  defp within?(count, limit), do: count <= limit

  defp decimal(value), do: Decimal.new(value)
end
