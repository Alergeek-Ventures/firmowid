defmodule Firmowid.Ash.Core.Changes.GenerateNickname do
  @moduledoc """
  Generates a unique `inbound_email_nickname` using `HumanIDs.generate/0`.

  Checks for existing nicknames via query before insert, retrying up to 10 times
  on collisions. Used by both the `:create` and `:regenerate_nickname` actions
  on Organization.
  """
  use Ash.Resource.Change

  alias Firmowid.Ash.Core.Organization

  require Ash.Query

  @max_attempts 10

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      case generate_unique_nickname(@max_attempts, context) do
        {:ok, nickname} ->
          Ash.Changeset.force_change_attribute(changeset, :inbound_email_nickname, nickname)

        :error ->
          Ash.Changeset.add_error(changeset,
            field: :inbound_email_nickname,
            message: "failed to generate unique nickname after #{@max_attempts} attempts"
          )
      end
    end)
  end

  defp generate_unique_nickname(0, _context), do: :error

  defp generate_unique_nickname(attempts_left, context) do
    nickname = HumanIDs.generate()

    if nickname_exists?(nickname, context) do
      generate_unique_nickname(attempts_left - 1, context)
    else
      {:ok, nickname}
    end
  end

  defp nickname_exists?(nickname, context) do
    ash_opts =
      Enum.reject([actor: context.actor, tenant: context.tenant], fn {_k, v} -> is_nil(v) end)

    Organization
    |> Ash.Query.filter(inbound_email_nickname == ^nickname)
    |> Ash.Query.select([:id])
    |> Ash.Query.limit(1)
    |> Ash.read_one!(ash_opts)
    |> is_struct()
  end
end
