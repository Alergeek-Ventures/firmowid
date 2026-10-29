defmodule Firmowid.Invoicing.Changes.PrepareCorrection do
  @moduledoc """
  Ash change that prepares a correction invoice (KOR) from a VAT invoice.

  Reads the original invoice from the `original_invoice_id` argument,
  finds the latest snapshot in the correction chain, and copies seller/buyer/payment
  fields to the changeset. Sets `ksef_invoice_kind: :kor` and `corrected_invoice_id`.

  Loads `:effective_snapshot`, then reloads needed fields on that struct — a bare
  `:struct` calc result leaves attributes as `%Ash.NotLoaded{}`.

  Omitted fields and Ash defaults inherit the latest snapshot, including sale
  and due dates. Explicit values (also nil and false) are preserved, except for
  buyer tax identity fields, which always come from the snapshot.

  Stores the loaded original as `context.corrected_invoice` and the effective
  snapshot as `context.invoice_reference` for read-only preview assembly.
  Lookup, loading, and eligibility failures are added to the changeset.
  """
  use Ash.Resource.Change
  use Gettext, backend: Firmowid.Gettext

  alias Firmowid.Invoicing.SalesInvoice

  @copied_fields [
    :seller_nip,
    :seller_display_name,
    :seller_address,
    :seller_name,
    :seller_surname,
    :seller_account_number,
    :vat_exemption_type,
    :vat_exemption_basis,
    :counterparty_id,
    :buyer_type,
    :buyer_id,
    :buyer_full_name,
    :buyer_given_name,
    :buyer_surname,
    :buyer_display_name,
    :buyer_address,
    :buyer_country,
    :buyer_is_different_mail_address,
    :buyer_mail_address,
    :buyer_mail_country,
    :buyer_email,
    :buyer_phone,
    :buyer_description,
    :should_send_emails,
    # Do not copy invoice/internal notes into corrections; corrections start fresh
    :buyer_pesel,
    :invoice_type,
    :payment_method,
    :currency,
    :is_reverse_charge,
    :is_cash_account,
    :related_parties,
    :receipt_invoice,
    :sale_date,
    :due_date
  ]

  @forced_snapshot_fields [
    :invoice_type,
    :buyer_type,
    :buyer_id,
    :buyer_pesel,
    :buyer_country
  ]

  @latest_snapshot_load [
    :sales_invoice_items,
    :sale_date,
    :due_date,
    :invoice_type | @copied_fields
  ]

  @impl true
  def change(changeset, _opts, context) do
    original_invoice_id = Ash.Changeset.get_argument(changeset, :original_invoice_id)

    # During AshPhoenix.Form validation, the argument may not be set yet.
    # Skip preparation and let the required argument validation handle it.
    if is_nil(original_invoice_id) do
      changeset
    else
      do_prepare(changeset, original_invoice_id, context)
    end
  end

  defp do_prepare(changeset, original_invoice_id, context) do
    opts = Ash.Context.to_opts(context)

    with {:ok, original_invoice} <-
           SalesInvoice.by_id(
             original_invoice_id,
             Keyword.put(opts, :load, [:effective_snapshot])
           ),
         :ok <- validate_original(original_invoice),
         {:ok, latest_snapshot} <-
           Ash.load(original_invoice.effective_snapshot, @latest_snapshot_load, opts) do
      prepare_from_snapshot(changeset, original_invoice, latest_snapshot)
    else
      {:error, error} -> Ash.Changeset.add_error(changeset, error)
    end
  end

  defp validate_original(%SalesInvoice{ksef_invoice_kind: :vat, invoice_number: number}) when not is_nil(number), do: :ok

  defp validate_original(_original_invoice) do
    {:error, field: :original_invoice_id, message: gettext("Choose an issued VAT invoice to correct.")}
  end

  defp prepare_from_snapshot(changeset, original_invoice, latest_snapshot) do
    # Defaults are changes too, but they are not caller intent. Preserve explicit
    # values (including nil/false) and replace omitted/defaulted fields with the snapshot.
    changeset =
      Enum.reduce(@copied_fields, changeset, fn field, cs ->
        if field in cs.defaults or not Ash.Changeset.changing_attribute?(cs, field) do
          value = Map.get(latest_snapshot, field)
          Ash.Changeset.force_change_attribute(cs, field, value)
        else
          cs
        end
      end)

    # Buyer tax identity must stay stable across corrections.
    # We force the identity-driving fields from the latest effective snapshot
    # so accidental blank/hidden form params cannot change the derived KSeF buyer ID type.
    changeset =
      Enum.reduce(@forced_snapshot_fields, changeset, fn field, cs ->
        Ash.Changeset.force_change_attribute(cs, field, Map.get(latest_snapshot, field))
      end)

    changeset
    |> Ash.Changeset.force_change_attribute(:ksef_invoice_kind, :kor)
    |> Ash.Changeset.force_change_attribute(:corrected_invoice_id, original_invoice.id)
    |> Ash.Changeset.force_change_attribute(:organization_id, original_invoice.organization_id)
    |> Ash.Changeset.set_context(%{
      corrected_invoice: original_invoice,
      invoice_reference: latest_snapshot
    })
  end
end
