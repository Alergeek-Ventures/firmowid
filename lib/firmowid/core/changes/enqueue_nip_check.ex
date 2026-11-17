defmodule Firmowid.Core.Changes.EnqueueNipCheck do
  @moduledoc """
  Queues a check of the organization's NIP in the public registers as soon as it
  is saved.

  The job is inserted in the action's transaction, so it exists only when the
  organization does. `VatIdCheckWorker` re-checks the NIP weekly after that.
  """
  use Ash.Resource.Change

  alias Firmowid.Invoicing.Workers.VatIdCheckWorker

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, organization ->
      %{organization_id: organization.id}
      |> VatIdCheckWorker.new()
      |> Firmowid.Oban.insert!(organization_id: organization.id)

      {:ok, organization}
    end)
  end
end
