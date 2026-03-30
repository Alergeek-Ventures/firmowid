defmodule Firmowid.Ash.Billing do
  @moduledoc """
  Ash domain for organization billing limits.

  Provides soft limits for cost invoices, sales invoices, and bank connections.
  Limits are checked but not enforced — actions proceed with warnings when over
  limit. Monthly invoice counters are reset by `Firmowid.Ash.Billing.ResetWorker`
  on the 1st of each month.

  This is a PoC feature — kept intentionally simple.
  """
  use Ash.Domain

  resources do
    resource Firmowid.Ash.Billing.Limits
  end

  authorization do
    authorize :by_default
    require_actor? true
  end
end
