defmodule Firmowid.Invoicing.Validations.CorrectedRatesNormalized do
  @moduledoc """
  Passes when a correction should normalize its VAT rates for reverse charge.

  Invoices issued in Firmowid always carry normalized rates (all `oo` under reverse
  charge, none otherwise), so their corrections keep normalizing. An invoice imported
  from KSeF keeps its document's rates, e.g. `np II` under reverse charge; its
  correction normalizes them only when it changes the reverse charge itself.
  `PrepareCorrection` stores the corrected state as `invoice_reference`; without it the
  condition passes.
  """
  use Ash.Resource.Validation

  @doc "Checks the corrected state's rates and whether the reverse charge changes."
  @spec validate(Ash.Changeset.t(), keyword(), Ash.Resource.Validation.Context.t()) ::
          :ok | {:error, keyword()}
  @impl true
  def validate(changeset, _opts, _context) do
    case changeset.context[:invoice_reference] do
      %{is_reverse_charge: reverse_charge?, sales_invoice_items: items} ->
        normalized? = Enum.all?(items, &(&1.vat_rate == "oo" == reverse_charge?))
        changed? = Ash.Changeset.get_attribute(changeset, :is_reverse_charge) != reverse_charge?

        if normalized? or changed?,
          do: :ok,
          else: {:error, field: :sales_invoice_items, message: "keeps the corrected invoice's rates"}

      _no_reference ->
        :ok
    end
  end
end
