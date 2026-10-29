defmodule Firmowid.Invoicing.Validations.InvoiceDraft do
  @moduledoc "Restricts saved-draft operations to an unnumbered VAT invoice."
  use Ash.Resource.Validation
  use Gettext, backend: Firmowid.Gettext

  @doc "Checks the original record, before any requested number is applied."
  @spec validate(Ash.Changeset.t(), keyword(), Ash.Resource.Validation.Context.t()) ::
          :ok | {:error, keyword()}
  @impl true
  def validate(%{data: %{invoice_number: nil, ksef_invoice_kind: :vat}}, _opts, _context), do: :ok

  def validate(_changeset, _opts, _context) do
    {:error, field: :invoice_id, message: gettext("Only an unnumbered invoice draft can be issued.")}
  end
end
