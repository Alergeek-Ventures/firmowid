defmodule Firmowid.Billing.Subscription.Validations.PeriodSettled do
  @moduledoc """
  Refuses a change while the current period's payment of the subscription is not paid.

  A paid change followed by the subscription ending on that unpaid payment would leave a refund
  behind, so it waits for the `:current_period_settled?` calculation: the free month counts as
  settled.
  """

  use Ash.Resource.Validation
  use Gettext, backend: Firmowid.Gettext

  alias Ash.Error.Changes.InvalidChanges

  @doc "Fails unless the subscription's current period is free or paid."
  @spec validate(Ash.Changeset.t(), keyword(), Ash.Resource.Validation.Context.t()) ::
          :ok | {:error, term()}
  @impl true
  def validate(changeset, _opts, context) do
    subscription =
      Ash.load!(changeset.data, :current_period_settled?, Ash.Context.to_opts(context))

    if subscription.current_period_settled? do
      :ok
    else
      {:error,
       InvalidChanges.exception(message: gettext_noop("You can switch plans once this month's payment goes through."))}
    end
  end
end
