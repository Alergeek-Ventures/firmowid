defmodule Firmowid.Invoicing.Validations.InvoiceNumberRequired do
  @moduledoc "Requires an invoice number when finalizing a VAT invoice."
  use Ash.Resource.Validation
  use Gettext, backend: Firmowid.Gettext

  @doc "Rejects finalization without a selected invoice number."
  @spec validate(Ash.Changeset.t(), keyword(), Ash.Resource.Validation.Context.t()) ::
          :ok | {:error, keyword()}
  @impl true
  def validate(changeset, _opts, _context) do
    if is_nil(Ash.Changeset.get_attribute(changeset, :invoice_number)) do
      {:error, field: :invoice_number, message: gettext("Choose an invoice number before issuing the invoice.")}
    else
      :ok
    end
  end
end
