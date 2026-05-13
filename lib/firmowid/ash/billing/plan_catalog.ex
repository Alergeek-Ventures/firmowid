defmodule Firmowid.Ash.Billing.PlanCatalog do
  @moduledoc """
  Shared source of truth for billing plan rules.

  The catalog intentionally exposes structured numeric billing data and rule
  markers only, so it can be reused by future billing admin and landing-page
  pricing code without embedding marketing prose.
  """

  @type plan :: :no_plan | :start | :przedsiebiorca | :firma
  @type money_amount :: Decimal.t()

  @type quantity_rule :: %{
          included_units: non_neg_integer(),
          billing:
            :unsupported
            | %{unit_price_pln: money_amount()}
            | %{pack_size: pos_integer(), pack_price_pln: money_amount()}
        }

  @type plan_rules :: %{
          plan: plan(),
          monthly_price_pln: money_amount(),
          yearly_price_pln: money_amount() | nil,
          manual_external_invoices: quantity_rule(),
          synced_bank_accounts: quantity_rule(),
          active_non_owner_users: quantity_rule()
        }

  @plans [:no_plan, :start, :przedsiebiorca, :firma]

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
      yearly_price_pln: nil,
      manual_external_invoices: %{included_units: 0, billing: :unsupported},
      synced_bank_accounts: %{included_units: 0, billing: :unsupported},
      active_non_owner_users: %{included_units: 0, billing: :unsupported}
    }
  end

  def plan!(:start) do
    %{
      plan: :start,
      monthly_price_pln: decimal("5"),
      yearly_price_pln: decimal("48"),
      manual_external_invoices: %{included_units: 0, billing: :unsupported},
      synced_bank_accounts: %{included_units: 0, billing: %{unit_price_pln: decimal("10")}},
      active_non_owner_users: %{included_units: 0, billing: :unsupported}
    }
  end

  def plan!(:przedsiebiorca) do
    %{
      plan: :przedsiebiorca,
      monthly_price_pln: decimal("29"),
      yearly_price_pln: decimal("276"),
      manual_external_invoices: %{
        included_units: 20,
        billing: %{pack_size: 10, pack_price_pln: decimal("25")}
      },
      synced_bank_accounts: %{included_units: 3, billing: %{unit_price_pln: decimal("5")}},
      active_non_owner_users: %{included_units: 5, billing: %{unit_price_pln: decimal("5")}}
    }
  end

  def plan!(:firma) do
    %{
      plan: :firma,
      monthly_price_pln: decimal("69"),
      yearly_price_pln: decimal("660"),
      manual_external_invoices: %{
        included_units: 100,
        billing: %{pack_size: 100, pack_price_pln: decimal("50")}
      },
      synced_bank_accounts: %{included_units: 10, billing: %{unit_price_pln: decimal("3")}},
      active_non_owner_users: %{included_units: 20, billing: %{unit_price_pln: decimal("3")}}
    }
  end

  @doc """
  Returns all plan rules keyed by plan identifier.
  """
  @spec all() :: %{required(plan()) => plan_rules()}
  def all do
    Map.new(@plans, &{&1, plan!(&1)})
  end

  defp decimal(value), do: Decimal.new(value)
end
