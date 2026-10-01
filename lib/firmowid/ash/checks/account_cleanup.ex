defmodule Firmowid.Ash.Checks.AccountCleanup do
  @moduledoc "Restricts account cleanup to records owned by the cleanup system actor's user."
  use Ash.Policy.FilterCheck

  alias Firmowid.Ash.SystemActor

  @impl true
  def describe(_opts), do: "record belongs to the account cleanup system actor's user"

  @impl true
  def filter(%SystemActor{role: :account_cleanup, user_id: user_id}, _context, _opts) when not is_nil(user_id) do
    expr(user_id == ^user_id)
  end

  def filter(_actor, _context, _opts), do: false
end
