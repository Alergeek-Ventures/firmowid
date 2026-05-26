defmodule Firmowid.Ash.Invoicing.SalesInvoice.EffectiveFields do
  @moduledoc """
  Generates `effective_<field>` expression calculations for correction-aware field access.

  Each calculation resolves to:

      if is_nil(latest_correction), do: <field>, else: latest_correction.<field>

  These are expression calculations — pushed to the DB, filterable, sortable.
  The `sales_invoice_items` relationship is excluded (not a scalar field).
  """

  @effective_fields [
    invoice_type: :atom,
    sale_date: :date,
    due_date: :date,
    payment_method: :atom,
    currency: :string,
    seller_nip: :string,
    seller_display_name: :string,
    seller_address: :string,
    seller_name: :string,
    seller_surname: :string,
    seller_account_number: :string,
    buyer_type: :atom,
    buyer_id: :string,
    buyer_full_name: :string,
    buyer_given_name: :string,
    buyer_surname: :string,
    buyer_pesel: :string,
    buyer_display_name: :string,
    buyer_address: :string,
    buyer_country: :string,
    buyer_is_different_mail_address: :boolean,
    buyer_mail_address: :string,
    buyer_mail_country: :string,
    buyer_email: :string,
    buyer_phone: :string,
    buyer_description: :string,
    should_send_emails: :boolean,
    is_cash_account: :boolean,
    is_reverse_charge: :boolean
  ]

  @doc """
  Returns the list of `{field, type}` pairs used by the macro.

  Useful for runtime iteration (e.g., copying effective values back to plain field names).
  """
  def fields, do: @effective_fields

  @doc false
  defmacro effective_correction_calculations do
    for {field, type} <- @effective_fields do
      calc_name = :"effective_#{field}"

      quote do
        calculate unquote(calc_name),
                  unquote(type),
                  expr(
                    if exists(latest_correction, true) do
                      ^ref([:latest_correction], unquote(field))
                    else
                      ^ref(unquote(field))
                    end
                  )
      end
    end
  end
end
