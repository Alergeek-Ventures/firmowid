defmodule Firmowid.Ash.Invoicing.Changes.SetIsCashAccount do
  @moduledoc """
  Ash change that sets `is_cash_account` based on `payment_method`.

  `is_cash_account` is `true` when `payment_method` is `:cash`, `false` otherwise.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    payment_method = Ash.Changeset.get_attribute(changeset, :payment_method)
    is_cash = payment_method == :cash

    Ash.Changeset.force_change_attribute(changeset, :is_cash_account, is_cash)
  end
end
