defmodule Firmowid.Ash.Invoicing.Changes.LinkCorrectedKsefInvoice do
  @moduledoc """
  Links an imported correction to the invoice it corrects, found by that invoice's KSeF number.

  A correction is shown and recalculated against its original, so it cannot be recorded
  while the original is missing from the organization's invoices.
  """
  use Ash.Resource.Change

  alias Firmowid.Ash.Invoicing.SalesInvoice

  require Ash.Query

  @doc "Sets `corrected_invoice_id` from the `corrected_invoice_ksef_number` argument."
  @spec change(Ash.Changeset.t(), keyword(), Ash.Resource.Change.Context.t()) :: Ash.Changeset.t()
  @impl true
  def change(changeset, _opts, context) do
    case Ash.Changeset.get_argument(changeset, :corrected_invoice_ksef_number) do
      nil -> changeset
      ksef_number -> link(changeset, ksef_number, Ash.Context.to_opts(context))
    end
  end

  defp link(changeset, ksef_number, opts) do
    query =
      SalesInvoice
      |> Ash.Query.filter(ksef_number == ^ksef_number)
      |> Ash.Query.select([:id])

    case SalesInvoice.list(Keyword.put(opts, :query, query)) do
      {:ok, [original]} ->
        Ash.Changeset.force_change_attribute(changeset, :corrected_invoice_id, original.id)

      {:ok, []} ->
        Ash.Changeset.add_error(changeset,
          field: :corrected_invoice_ksef_number,
          message: "faktura korygowana nie jest zapisana w Firmowidzie"
        )

      {:error, error} ->
        Ash.Changeset.add_error(changeset, error)
    end
  end
end
