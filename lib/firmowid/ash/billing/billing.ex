defmodule Firmowid.Ash.Billing do
  @moduledoc """
  Ash domain for organization billing limits.

  Provides soft limits for cost invoices, sales invoices, and bank connections.
  Limits are checked but not enforced — actions proceed with warnings when over
  limit. Monthly invoice counters are reset by `Firmowid.Ash.Billing.ResetWorker`
  on the 1st of each month.
  """
  use Ash.Domain

  resources do
    resource Firmowid.Ash.Billing.Limits do
      define :create_limits, action: :create
      define :get_limits, action: :read, get?: true
      define :increment_counter
      define :decrement_counter
    end
  end

  authorization do
    authorize :by_default
    require_actor? true
  end
end
