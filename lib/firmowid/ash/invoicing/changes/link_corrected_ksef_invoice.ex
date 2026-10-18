defmodule Firmowid.Ash.Invoicing.Changes.LinkCorrectedKsefInvoice do
  @moduledoc """
  Links an imported correction to the VAT invoice it corrects, found by the KSeF number
  of the corrected document.

  Corrections in Firmowid all point at the original VAT invoice, so a correction of a
  correction links to that correction's original. A correction is rejected when its
  original is missing from the organization's invoices.
  """
  use Ash.Resource.Change

  alias Firmowid.Ash.Invoicing.SalesInvoice

  require Ash.Query

  @missing "faktura korygowana nie jest zapisana w Firmowidzie"

  @doc "Sets `corrected_invoice_id` of a KOR from its `corrected_invoice_ksef_number` argument."
  @spec change(Ash.Changeset.t(), keyword(), Ash.Resource.Change.Context.t()) :: Ash.Changeset.t()
  @impl true
  def change(changeset, _opts, context) do
    ksef_number = Ash.Changeset.get_argument(changeset, :corrected_invoice_ksef_number)

    case {Ash.Changeset.get_attribute(changeset, :ksef_invoice_kind), ksef_number} do
      {:vat, _ksef_number} -> changeset
      {:kor, nil} -> add_missing(changeset)
      {:kor, ksef_number} -> link(changeset, ksef_number, Ash.Context.to_opts(context))
    end
  end

  defp link(changeset, ksef_number, opts) do
    query =
      SalesInvoice
      |> Ash.Query.filter(ksef_number == ^ksef_number)
      |> Ash.Query.select([:id, :ksef_invoice_kind, :corrected_invoice_id])

    case SalesInvoice.list(Keyword.put(opts, :query, query)) do
      {:ok, [%SalesInvoice{ksef_invoice_kind: :kor, corrected_invoice_id: id}]} ->
        Ash.Changeset.force_change_attribute(changeset, :corrected_invoice_id, id)

      {:ok, [%SalesInvoice{id: id}]} ->
        Ash.Changeset.force_change_attribute(changeset, :corrected_invoice_id, id)

      {:ok, []} ->
        add_missing(changeset)

      {:error, error} ->
        Ash.Changeset.add_error(changeset, error)
    end
  end

  defp add_missing(changeset) do
    Ash.Changeset.add_error(changeset, field: :corrected_invoice_ksef_number, message: @missing)
  end
end
