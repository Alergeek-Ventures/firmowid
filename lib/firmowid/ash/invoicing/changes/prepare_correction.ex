defmodule Firmowid.Ash.Invoicing.Changes.PrepareCorrection do
  @moduledoc """
  Ash change that prepares a correction invoice (KOR) from a VAT invoice.

  Reads the original invoice from the `original_invoice_id` argument,
  finds the latest snapshot in the correction chain, and copies seller/buyer/payment
  fields to the changeset. Sets `ksef_invoice_kind: :kor` and `corrected_invoice_id`.
  """
  use Ash.Resource.Change

  alias Firmowid.Ash.Invoicing.SalesInvoice

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
    :is_cash_account
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

    original_invoice =
      SalesInvoice.by_id!(
        original_invoice_id,
        Keyword.put(opts, :load, [
          :effective_snapshot,
          :sales_invoice_items,
          corrections: :sales_invoice_items,
          latest_correction: @latest_snapshot_load
        ])
      )

    latest_snapshot = original_invoice.effective_snapshot

    # Copy fields from the latest snapshot, but don't overwrite explicitly provided values
    changeset =
      Enum.reduce(@copied_fields, changeset, fn field, cs ->
        if is_nil(Ash.Changeset.get_attribute(cs, field)) do
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

    # Also copy sale_date and due_date if not explicitly set
    changeset =
      if is_nil(Ash.Changeset.get_attribute(changeset, :sale_date)) do
        Ash.Changeset.force_change_attribute(changeset, :sale_date, latest_snapshot.sale_date)
      else
        changeset
      end

    changeset =
      if is_nil(Ash.Changeset.get_attribute(changeset, :due_date)) do
        Ash.Changeset.force_change_attribute(changeset, :due_date, latest_snapshot.due_date)
      else
        changeset
      end

    changeset
    |> Ash.Changeset.force_change_attribute(:ksef_invoice_kind, :kor)
    |> Ash.Changeset.force_change_attribute(:corrected_invoice_id, original_invoice.id)
    |> Ash.Changeset.force_change_attribute(:organization_id, original_invoice.organization_id)
  end
end
