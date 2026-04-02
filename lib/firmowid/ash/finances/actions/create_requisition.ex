defmodule Firmowid.Ash.Finances.Actions.CreateRequisition do
  @moduledoc """
  Generic action implementation for creating a GoCardless requisition.

  Calls the GoCardless API to create an end-user agreement and requisition,
  persists the requisition record locally with `status: :pending`, and returns
  the GoCardless redirect link URL.

  The GoCardless-assigned UUID is used as the record's primary key.
  """
  use Ash.Resource.Actions.Implementation

  alias Firmowid.Ash.Finances.GoCardless.ApiClient

  @impl true
  def run(input, _opts, context) do
    institution_id = input.arguments.institution_id
    max_days = input.arguments.max_transaction_days
    redirect_url = input.arguments.redirect_url
    tenant = context.tenant

    with {:ok, gc_requisition} <-
           ApiClient.create_requisition(institution_id, max_days, redirect_url),
         {:ok, _record} <-
           input.resource
           |> Ash.Changeset.for_create(:persist, %{id: gc_requisition["id"]},
             tenant: tenant,
             authorize?: false,
             actor: %{}
           )
           |> Ash.create(tenant: tenant, authorize?: false, actor: %{}) do
      {:ok, gc_requisition["link"]}
    end
  end
end
