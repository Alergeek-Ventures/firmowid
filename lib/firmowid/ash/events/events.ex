defmodule Firmowid.Ash.Events do
  @moduledoc """
  Ash domain for the centralized event log.

  Currently used by BankAccount for sync status derivation.
  Other resources can opt into event tracking later.
  """
  use Ash.Domain

  resources do
    resource Firmowid.Ash.Events.Event
  end

  authorization do
    authorize :by_default
    require_actor? true
  end
end
