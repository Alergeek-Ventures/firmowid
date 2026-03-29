defmodule Firmowid.Ash.Finances do
  @moduledoc """
  Ash domain for bank accounts and transactions.

  Manages bank account CRUD, transaction synchronization from bank APIs,
  transaction search (ParadeDB), and invoicing-related transaction queries.

  PubSub helpers live here as plain functions — they orchestrate cross-action
  broadcasts (e.g. single broadcast after a bulk upsert) which don't fit the
  per-action `Ash.Notifier.PubSub` model.
  """
  use Ash.Domain

  resources do
    resource Firmowid.Ash.Finances.BankAccount
    resource Firmowid.Ash.Finances.Transaction
  end

  authorization do
    authorize :by_default
    require_actor? true
  end

  # ── PubSub helpers ──────────────────────────────────────────────────

  @transaction_broadcast_topic "transaction_broadcast_topic"

  @doc """
  Subscribes the calling process to transaction list updates for an organization.

  Used by LiveViews that display transaction lists (e.g. InvoicingLive).
  """
  @spec subscribe_transaction_broadcast(String.t()) :: :ok | {:error, term()}
  def subscribe_transaction_broadcast(organization_id) do
    Phoenix.PubSub.subscribe(
      Firmowid.PubSub,
      "#{@transaction_broadcast_topic}:#{organization_id}"
    )
  end

  @doc """
  Broadcasts that the transaction list was updated for an organization.

  Called after bulk operations (bank sync upsert) and single-record updates
  (toggle_skip_invoicing) to notify listening LiveViews.
  """
  @spec broadcast_transaction_list_updated(String.t()) :: :ok | {:error, term()}
  def broadcast_transaction_list_updated(organization_id) do
    Phoenix.PubSub.broadcast(
      Firmowid.PubSub,
      "#{@transaction_broadcast_topic}:#{organization_id}",
      :transaction_list_updated
    )
  end
end
