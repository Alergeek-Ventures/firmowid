defmodule Firmowid.Core.Validations.NoActiveSubscription do
  @moduledoc """
  Refuses a trial for an organization that already pays for its plan with an active
  subscription.
  """

  use Ash.Resource.Validation
  use Gettext, backend: Firmowid.Gettext

  alias Ash.Error.Changes.InvalidChanges

  @doc "Fails while the organization has an active subscription."
  @spec validate(Ash.Changeset.t(), keyword(), Ash.Resource.Validation.Context.t()) ::
          :ok | {:error, term()}
  @impl true
  def validate(changeset, _opts, context) do
    organization = changeset.data

    # Subscriptions belong to the organization's tenant.
    case Ash.load(
           organization,
           :has_active_subscription?,
           Ash.Context.to_opts(context, tenant: organization.id)
         ) do
      {:ok, %{has_active_subscription?: false}} ->
        :ok

      {:ok, _organization} ->
        {:error,
         InvalidChanges.exception(message: gettext_noop("This company pays for its plan, so it cannot get a trial."))}

      {:error, error} ->
        {:error, error}
    end
  end
end
