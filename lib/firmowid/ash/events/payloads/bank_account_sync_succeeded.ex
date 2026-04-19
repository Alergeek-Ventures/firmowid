defmodule Firmowid.Ash.Events.Payloads.BankAccountSyncSucceeded do
  @moduledoc """
  Typed payload for `BankAccount.sync_from_gocardless` events.
  """

  use Ash.Resource,
    data_layer: :embedded,
    embed_nil_values?: false

  actions do
    defaults create: []
  end
end
