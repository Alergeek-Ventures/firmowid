defmodule Firmowid.Ash.Core.Changes.GenerateNickname do
  @moduledoc """
  Generates a unique `inbound_email_nickname` using `HumanIDs.generate/0`.

  Retries up to 10 times on unique constraint violations (identity collisions).
  Used by both the `:create` and `:regenerate_nickname` actions on Organization.
  """
  use Ash.Resource.Change

  @max_attempts 10

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      generate_with_retry(changeset, @max_attempts)
    end)
  end

  defp generate_with_retry(_changeset, 0) do
    raise "Failed to generate unique inbound email nickname after #{@max_attempts} attempts"
  end

  defp generate_with_retry(changeset, attempts_left) do
    nickname = HumanIDs.generate()

    changeset
    |> Ash.Changeset.force_change_attribute(:inbound_email_nickname, nickname)
    |> Ash.Changeset.after_action(fn _changeset, result ->
      {:ok, result}
    end)
  rescue
    # Identity violation on :unique_nickname — retry with new nickname
    e in Ash.Error.Invalid ->
      if identity_conflict?(e) do
        generate_with_retry(changeset, attempts_left - 1)
      else
        reraise e, __STACKTRACE__
      end
  end

  defp identity_conflict?(%{errors: errors}) do
    Enum.any?(errors, fn
      %Ash.Error.Changes.InvalidChanges{fields: fields} ->
        :inbound_email_nickname in fields

      _ ->
        false
    end)
  end
end
