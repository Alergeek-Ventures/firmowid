defmodule Firmowid.Core.ApiKey.Changes.DestroyServiceAccount do
  @moduledoc """
  Destroys the account of a revoked company key, which has no other key, as the actor who
  revokes it. A personal key has no account.
  """

  use Ash.Resource.Change

  alias Firmowid.Core

  # Revoking a person's keys on their departure destroys them atomically.
  @impl true
  def atomic(changeset, opts, context), do: {:ok, change(changeset, opts, context)}

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.after_action(changeset, fn _changeset, key ->
      case key.service_account_id do
        nil ->
          {:ok, key}

        service_account_id ->
          opts = Keyword.put(Ash.Context.to_opts(context), :tenant, key.organization_id)

          with {:ok, account} <- Core.get_service_account(service_account_id, opts),
               :ok <- Core.destroy_service_account(account, opts),
               do: {:ok, key}
      end
    end)
  end
end
