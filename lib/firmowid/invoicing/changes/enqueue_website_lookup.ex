defmodule Firmowid.Invoicing.Changes.EnqueueWebsiteLookup do
  @moduledoc """
  Queues the lookup of a company counterparty's website as soon as it is created
  or the details the lookup searches by change, so the list shows its logo. A
  change clears the website found for the old details. People are never looked up.

  The job is inserted in the action's transaction, so it exists only when the
  counterparty does. `CounterpartyWebsiteWorker` picks up any lookup left undone.
  """
  use Ash.Resource.Change

  alias Firmowid.Invoicing.Workers.CounterpartyWebsiteWorker

  @lookup_fields [:type, :full_name, :display_name, :tax_id, :country, :email]

  @impl true
  def change(changeset, _opts, _context) do
    if changeset.action_type == :create or
         Enum.any?(@lookup_fields, &Ash.Changeset.changing_attribute?(changeset, &1)) do
      changeset
      |> Ash.Changeset.force_change_attributes(%{website_domain: nil, website_checked_at: nil})
      |> Ash.Changeset.after_action(&enqueue/2)
    else
      changeset
    end
  end

  defp enqueue(_changeset, counterparty) do
    if counterparty.type == :company do
      %{organization_id: counterparty.organization_id, counterparty_id: counterparty.id}
      |> CounterpartyWebsiteWorker.new()
      |> Firmowid.Oban.insert!(organization_id: counterparty.organization_id)
    end

    {:ok, counterparty}
  end
end
