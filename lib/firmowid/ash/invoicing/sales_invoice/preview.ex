defmodule Firmowid.Ash.Invoicing.SalesInvoice.Preview do
  @moduledoc "Assembles an unsaved document from its validated invoice changeset using resource calculations."

  alias Firmowid.Ash.Invoicing.SalesInvoiceItem

  @totals [:net_value, :vat_value, :gross_value]
  @invoice_calculations [
    :amount,
    :buyer_id_type,
    :buyer_display_name_label,
    :is_draft,
    :is_confirmed
  ]
  @review_fields [
    :invoice_type,
    :invoice_number,
    :issue_date,
    :sale_date,
    :due_date,
    :currency,
    :payment_method,
    :should_send_emails,
    :counterparty_id,
    :seller_nip,
    :seller_display_name,
    :seller_address,
    :seller_account_number,
    :buyer_type,
    :buyer_id,
    :buyer_full_name,
    :buyer_given_name,
    :buyer_surname,
    :buyer_pesel,
    :buyer_display_name,
    :buyer_address,
    :buyer_country,
    :is_reverse_charge,
    :vat_exemption_type,
    :vat_exemption_basis,
    :invoice_note,
    :internal_note,
    :correction_reason,
    :correction_type
  ]

  @doc "Projects the reviewed document and delivery choice for confirmation and finalization."
  @spec review_snapshot(struct()) :: map()
  def review_snapshot(invoice) do
    items =
      Enum.map(
        invoice.sales_invoice_items,
        &Map.take(&1, [:index, :name, :quantity, :unit, :unit_price, :vat_rate, :gtu])
      )

    invoice
    |> Map.take(@review_fields)
    |> Map.put(:items, items)
    |> Map.put(:reference_invoice, reference_snapshot(invoice.reference_invoice))
  end

  @doc "Materializes prepared attributes and items without executing persistence or submission hooks."
  @spec from_changeset(Ash.Changeset.t(), keyword()) :: {:ok, struct()} | {:error, term()}
  def from_changeset(changeset, opts) do
    with {:ok, invoice} <- apply_attributes(changeset),
         {:ok, items} <- items(changeset, invoice, opts),
         {:ok, reference} <- reference(changeset, invoice, opts) do
      totals =
        Map.new(@totals, fn field ->
          {field, Enum.reduce(items, Decimal.new(0), &Decimal.add(Map.fetch!(&1, field), &2))}
        end)

      invoice =
        invoice
        |> Map.merge(totals)
        |> Map.put(:organization_id, opts[:tenant])
        |> Map.put(:sales_invoice_items, items)
        |> Map.put(:reference_invoice, reference)
        |> Map.put(:corrected_invoice, corrected_invoice(changeset, invoice))

      # Edited records can carry stale calculations. Keep the assembled relation
      # totals, but let Ash recalculate document fields from the prepared values.
      @invoice_calculations
      |> Enum.reduce(invoice, &Ash.Resource.unload(&2, &1))
      |> Ash.load(@invoice_calculations, Keyword.put(opts, :reuse_values?, true))
    end
  end

  defp reference_snapshot(nil), do: nil
  defp reference_snapshot(%Ash.NotLoaded{}), do: nil

  defp reference_snapshot(invoice) when is_map(invoice) do
    invoice
    |> Map.take([:id, :invoice_number, :ksef_number, :amount])
    |> Map.put(
      :sales_invoice_items,
      Enum.map(
        invoice.sales_invoice_items,
        &Map.take(&1, [:index, :name, :quantity, :unit, :unit_price, :vat_rate, :gtu])
      )
    )
  end

  defp items(changeset, invoice, opts) do
    items =
      Ash.Changeset.get_argument(changeset, :sales_invoice_items) || invoice.sales_invoice_items

    items
    |> Enum.reduce_while({:ok, []}, fn attrs, {:ok, items} ->
      attrs = Map.take(attrs, [:index, :name, :quantity, :unit, :unit_price, :vat_rate, :gtu])

      changeset =
        attrs
        |> SalesInvoiceItem.changeset_to_create(opts)
        |> Ash.Changeset.force_change_attribute(:organization_id, opts[:tenant])
        |> Ash.Changeset.force_change_attribute(:sales_invoice_id, invoice.id)

      with {:ok, item} <- apply_attributes(changeset),
           {:ok, item} <- item_totals(item, opts) do
        {:cont, {:ok, [item | items]}}
      else
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, items} -> {:ok, Enum.reverse(items)}
      {:error, error} -> {:error, error}
    end
  end

  defp item_totals(item, opts) do
    refs = Map.take(item, [:quantity, :unit_price, :vat_rate])

    Enum.reduce_while(@totals, {:ok, item}, fn field, {:ok, item} ->
      case Ash.calculate(SalesInvoiceItem, field, Keyword.put(opts, :refs, refs)) do
        {:ok, value} -> {:cont, {:ok, Map.put(item, field, value)}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp reference(_changeset, %{ksef_invoice_kind: :vat}, _opts), do: {:ok, nil}

  defp reference(changeset, invoice, opts) do
    reference = Map.get(changeset.context, :invoice_reference, invoice.reference_invoice)
    Ash.load(reference, [:amount | @totals] ++ [sales_invoice_items: @totals], opts)
  end

  defp corrected_invoice(_changeset, %{ksef_invoice_kind: :vat}), do: nil

  defp corrected_invoice(changeset, invoice),
    do: Map.get(changeset.context, :corrected_invoice, invoice.corrected_invoice)

  defp apply_attributes(changeset) do
    case Ash.Changeset.apply_attributes(changeset) do
      {:ok, record} -> {:ok, record}
      {:error, changeset} -> {:error, Ash.Error.to_error_class(changeset.errors)}
    end
  end
end
