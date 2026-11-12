defmodule Firmowid.Invoicing.SalesInvoice.EffectiveFields do
  @moduledoc """
  Generates `effective_<field>` expression calculations for correction-aware field access.

  Each calculation resolves to:

      if is_nil(latest_correction), do: <field>, else: latest_correction.<field>

  These are expression calculations — pushed to the DB, filterable, sortable.
  The `sales_invoice_items` relationship is excluded (not a scalar field).
  """

  @effective_fields [
    sale_date: :date,
    due_date: :date,
    payment_method: :atom,
    seller_nip: :string,
    seller_display_name: :string,
    seller_address: :string,
    buyer_pesel: :string
  ]

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
