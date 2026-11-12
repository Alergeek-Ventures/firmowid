defmodule Firmowid.Finances.Actions.CreateRequisition do
  @moduledoc """
  Generic action implementation for creating a GoCardless requisition.

  Calls the GoCardless API to create an end-user agreement and requisition,
  persists the requisition record locally with `status: :pending`, and returns
  the GoCardless redirect link URL.

  The GoCardless-assigned UUID is used as the record's primary key.
  """
  use Ash.Resource.Actions.Implementation

  alias Firmowid.Finances.GoCardless.ApiClient
  alias Firmowid.Finances.Requisition

  @impl true
  def run(input, _opts, context) do
    %{institution_id: institution_id, max_transaction_days: max_days, redirect_url: redirect_url} =
      input.arguments

    # This action is authorized for the organization admin; the internal
    # `:persist` action is forbidden to every actor, so it runs unauthorized
    # here and only an id that GoCardless returned can become a requisition.
    with {:ok, gc_requisition} <-
           ApiClient.create_requisition(institution_id, max_days, redirect_url),
         {:ok, _record} <-
           Requisition.persist(
             %{id: gc_requisition["id"]},
             context |> Ash.Context.to_opts() |> Keyword.put(:authorize?, false)
           ) do
      {:ok, gc_requisition["link"]}
    end
  end
end
