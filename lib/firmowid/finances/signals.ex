defmodule Firmowid.Finances.Signals do
  @moduledoc """
  Signals emitted by the Finances domain for other resources to react to.
  """

  use Ash.Signals

  signals do
    signal :bank_account_synced do
      description "Transactions of a bank account were synced from the bank."
      argument :bank_account_id, :uuid, allow_nil?: false
      argument :organization_id, :uuid, allow_nil?: false
    end
  end
end
