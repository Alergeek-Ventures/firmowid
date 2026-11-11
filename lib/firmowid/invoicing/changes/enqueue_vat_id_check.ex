defmodule Firmowid.Invoicing.Changes.EnqueueVatIdCheck do
  @moduledoc """
  Queues a VIES check of a counterparty's EU VAT number as soon as it is saved.

  The job is inserted in the action's transaction, so it exists only when the
  counterparty does. `VatIdCheckWorker` re-checks the number periodically after that.
  """
  use Ash.Resource.Change

  alias Firmowid.Invoicing.CountryCodes
  alias Firmowid.Invoicing.Workers.VatIdCheckWorker

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, counterparty ->
      if eu_vat?(counterparty) do
        %{organization_id: counterparty.organization_id, counterparty_id: counterparty.id}
        |> VatIdCheckWorker.new()
        |> Firmowid.Oban.insert!(organization_id: counterparty.organization_id)
      end

      {:ok, counterparty}
    end)
  end

  defp eu_vat?(counterparty) do
    counterparty.tax_id not in [nil, ""] and
      CountryCodes.tax_id_type(counterparty.country, counterparty.pesel, counterparty.type) ==
        :eu_vat
  end
end
