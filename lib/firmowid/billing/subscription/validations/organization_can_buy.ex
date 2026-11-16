defmodule Firmowid.Billing.Subscription.Validations.OrganizationCanBuy do
  @moduledoc """
  Refuses a plan purchase the organization cannot make: the organization that sells Firmowid
  (`:billing` `:seller_organization_id`) would invoice itself, a plan granted by hand
  (`plan_granted?`) needs no purchase, and the advance invoice needs the company address.
  """

  use Ash.Resource.Validation
  use Gettext, backend: Firmowid.Gettext

  alias Ash.Error.Changes.InvalidChanges
  alias Firmowid.Core

  @doc "Fails for the seller organization, a granted plan or a missing company address."
  @spec validate(Ash.Changeset.t(), keyword(), Ash.Resource.Validation.Context.t()) ::
          :ok | {:error, term()}
  @impl true
  def validate(changeset, _opts, context) do
    seller_id =
      :firmowid |> Application.fetch_env!(:billing) |> Keyword.fetch!(:seller_organization_id)

    case Core.get_organization(
           changeset.tenant,
           Ash.Context.to_opts(context, load: [:plan_granted?])
         ) do
      {:ok, %{id: ^seller_id}} ->
        refuse(gettext_noop("The company that sells Firmowid cannot buy a plan."))

      {:ok, %{plan_granted?: true}} ->
        refuse(gettext_noop("This company's plan was granted, so there is nothing to buy."))

      {:ok, %{address: address}} when address in [nil, ""] ->
        refuse(gettext_noop("Fill in the company address to buy a plan."))

      {:ok, _organization} ->
        :ok

      {:error, error} ->
        {:error, error}
    end
  end

  defp refuse(message), do: {:error, InvalidChanges.exception(message: message)}
end
