defmodule Firmowid.Core.Changes.SetTrialEnd do
  @moduledoc """
  Sets the last day of a trial of `months` months (an argument) that starts in the current
  Warsaw month: one month ends this month, three end with the month two after it.
  """

  use Ash.Resource.Change

  alias Firmowid.Billing.Month

  @doc "Sets `trial_ends_on` from the `:months` argument."
  @spec change(Ash.Changeset.t(), keyword(), Ash.Resource.Change.Context.t()) :: Ash.Changeset.t()
  @impl true
  def change(changeset, _opts, _context) do
    months = Ash.Changeset.get_argument(changeset, :months)

    ends_on =
      Month.current()
      |> Date.shift(month: months - 1)
      |> Date.end_of_month()

    Ash.Changeset.force_change_attribute(changeset, :trial_ends_on, ends_on)
  end
end
