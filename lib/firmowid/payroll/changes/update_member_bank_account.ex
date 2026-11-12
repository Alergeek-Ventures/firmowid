defmodule Firmowid.Payroll.Changes.UpdateMemberBankAccount do
  @moduledoc """
  Saves the `bank_account_number` argument, when given, on the salary's member after the
  salary, so a refused account number rolls the salary back. The returned salary carries
  the updated member; the member's errors carry the `:member` path.
  """
  use Ash.Resource.Change

  alias Firmowid.Core

  @impl true
  def change(changeset, _opts, context) do
    case Ash.Changeset.fetch_argument(changeset, :bank_account_number) do
      {:ok, bank_account_number} ->
        Ash.Changeset.after_action(changeset, fn _changeset, salary ->
          opts = Ash.Context.to_opts(context)

          with {:ok, %{member: member}} <- Ash.load(salary, :member, opts),
               {:ok, member} <-
                 Core.update_member_profile(
                   member,
                   %{bank_account_number: bank_account_number},
                   opts
                 ) do
            {:ok, %{salary | member: member}}
          else
            {:error, error} -> {:error, Ash.Error.set_path(error, [:member])}
          end
        end)

      :error ->
        changeset
    end
  end
end
