defmodule Firmowid.Ash.Invoicing.Changes.LinkCorrectedKsefInvoice do
  @moduledoc """
  Links an imported correction to the VAT invoice it corrects, found by the KSeF number
  of the corrected document.

  Corrections in Firmowid all point at the original VAT invoice and keep its complete
  state after the correction, so an imported correction is rejected when its original
  is missing from the organization's invoices, or when it lists only some of the lines
  of the state it corrects.
  """
  use Ash.Resource.Change

  alias Firmowid.Ash.Invoicing.SalesInvoice

  require Ash.Query

  @doc "Sets `corrected_invoice_id` of a KOR from its `corrected_invoice_ksef_number` argument."
  @spec change(Ash.Changeset.t(), keyword(), Ash.Resource.Change.Context.t()) :: Ash.Changeset.t()
  @impl true
  def change(changeset, _opts, context) do
    case Ash.Changeset.get_attribute(changeset, :ksef_invoice_kind) do
      :kor -> link(changeset, Ash.Context.to_opts(context))
      :vat -> changeset
    end
  end

  defp link(changeset, opts) do
    with {:ok, original} <- find_original(changeset, opts),
         :ok <- check_complete(changeset, original, opts) do
      Ash.Changeset.force_change_attribute(changeset, :corrected_invoice_id, original.id)
    else
      {:error, error} -> Ash.Changeset.add_error(changeset, error)
    end
  end

  # A correction of a correction names the earlier correction; the chain hangs off the VAT invoice.
  defp find_original(changeset, opts) do
    ksef_number = Ash.Changeset.get_argument(changeset, :corrected_invoice_ksef_number)

    query =
      SalesInvoice
      |> Ash.Query.filter(not is_nil(^ksef_number) and ksef_number == ^ksef_number)
      |> Ash.Query.load(:corrected_invoice)

    case SalesInvoice.list(Keyword.put(opts, :query, query)) do
      {:ok, [%SalesInvoice{ksef_invoice_kind: :kor, corrected_invoice: original}]} ->
        {:ok, original}

      {:ok, [%SalesInvoice{} = original]} ->
        {:ok, original}

      {:ok, []} ->
        {:error, error("faktura korygowana nie jest zapisana w Firmowidzie")}

      {:error, error} ->
        {:error, error}
    end
  end

  defp check_complete(changeset, original, opts) do
    with {:ok, original} <- Ash.load(original, [:effective_snapshot], opts),
         {:ok, snapshot} <- Ash.load(original.effective_snapshot, [:sales_invoice_items], opts) do
      if Ash.Changeset.get_argument(changeset, :corrected_line_count) ==
           length(snapshot.sales_invoice_items),
         do: :ok,
         else: {:error, error("korekta wykazuje tylko część pozycji faktury korygowanej")}
    end
  end

  defp error(message), do: [field: :corrected_invoice_ksef_number, message: message]
end
