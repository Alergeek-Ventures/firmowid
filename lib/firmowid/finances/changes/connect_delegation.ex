defmodule Firmowid.Finances.Changes.ConnectDelegation do
  @moduledoc """
  Links a transaction to an approved delegation of the same organization.

  Repeating an existing link succeeds without changes. The update only applies to a pending
  transaction or one already linked to the same delegation, so a concurrent link cannot be
  overwritten.
  """

  use Ash.Resource.Change
  use Gettext, backend: Firmowid.Gettext

  import Ash.Expr

  alias Firmowid.Delegations
  alias Firmowid.Finances
  alias Firmowid.Scope

  @impl true
  def change(changeset, _opts, context) do
    delegation_id = Ash.Changeset.get_attribute(changeset, :delegation_id)

    changeset
    |> Ash.Changeset.filter(expr(reconciliation_status == :pending or delegation_id == ^delegation_id))
    |> Ash.Changeset.before_action(fn changeset ->
      scope = Scope.new!(context.actor, context.tenant)

      case conflict(changeset.data.id, delegation_id, scope) do
        nil -> changeset
        message -> Ash.Changeset.add_error(changeset, field: :delegation_id, message: message)
      end
    end)
  end

  defp conflict(transaction_id, delegation_id, scope) do
    transaction = Finances.get_transaction!(transaction_id, scope: scope)

    cond do
      transaction.delegation_id == delegation_id ->
        nil

      transaction.skip_invoicing ->
        gettext_noop("The transaction is skipped. Restore it for matching first.")

      approved?(delegation_id, scope) ->
        nil

      true ->
        gettext_noop("Only an approved delegation of this company can be linked.")
    end
  end

  # The read is tenant-scoped, so another organization's delegation is not found.
  defp approved?(delegation_id, scope) do
    case Delegations.get_delegation(delegation_id, scope: scope) do
      {:ok, delegation} -> delegation.status != :pending
      {:error, _error} -> false
    end
  end
end
