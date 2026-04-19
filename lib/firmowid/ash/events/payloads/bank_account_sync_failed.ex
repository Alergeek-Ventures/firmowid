defmodule Firmowid.Ash.Events.Payloads.BankAccountSyncFailed do
  @moduledoc """
  Typed payload for `BankAccount.mark_sync_failed` events.
  """

  use Ash.Resource,
    data_layer: :embedded,
    embed_nil_values?: false

  actions do
    defaults create: []
  end
end
