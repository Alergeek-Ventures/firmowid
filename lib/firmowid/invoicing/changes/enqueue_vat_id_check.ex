defmodule Firmowid.Invoicing.Changes.EnqueueVatIdCheck do
  @moduledoc """
  Queues a check of a counterparty's EU VAT number or NIP as soon as it is saved.

  The job is inserted in the action's transaction, so it exists only when the
  counterparty does. `VatIdCheckWorker` re-checks the number periodically after that.
  """
  use Ash.Resource.Change

  alias Firmowid.Invoicing.CountryCodes
  alias Firmowid.Invoicing.Workers.VatIdCheckWorker

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, counterparty ->
      if checked_id?(counterparty) do
        %{organization_id: counterparty.organization_id, counterparty_id: counterparty.id}
        |> VatIdCheckWorker.new()
        |> Firmowid.Oban.insert!(organization_id: counterparty.organization_id)
      end

      {:ok, counterparty}
    end)
  end

  defp checked_id?(counterparty) do
    counterparty.tax_id not in [nil, ""] and
      CountryCodes.tax_id_type(counterparty.country, counterparty.pesel, counterparty.type) in [
        :eu_vat,
        :nip
      ]
  end
end
