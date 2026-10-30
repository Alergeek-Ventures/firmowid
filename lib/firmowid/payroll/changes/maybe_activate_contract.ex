defmodule Firmowid.Payroll.Changes.MaybeActivateContract do
  @moduledoc """
  After create/submit_signed, activates a signed contract when `starts_at` is today or in the past.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.after_action(changeset, fn _changeset, contract ->
      maybe_activate_contract(contract, context)
    end)
  end

  defp maybe_activate_contract(%{status: :signed, starts_at: starts_at} = contract, context) do
    if Date.after?(starts_at, Date.utc_today()) do
      {:ok, contract}
    else
      opts =
        context
        |> Ash.Context.to_opts()
        |> Keyword.take([:actor, :tenant, :authorize?, :tracer])
        |> Keyword.put(:tenant, contract.organization_id)

      contract
      |> Ash.Changeset.for_update(:activate, %{}, opts)
      |> Ash.update(opts)
    end
  end

  defp maybe_activate_contract(contract, _context), do: {:ok, contract}
end
