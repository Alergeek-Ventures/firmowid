defmodule FirmowidWeb.PdfHTML do
  use FirmowidWeb, :html

  attr :sales_invoice, :map, required: true
  attr :currency_rate, :map, required: false, default: nil
  attr :class, :string, default: nil
  attr :show_vat, :boolean, default: true
  attr :logo_data_uri, :string, default: nil
  attr :footer_logo_data_uri, :string, default: nil

  def sales_invoice(assigns) do
    FirmowidWeb.SalesInvoices.Template.sales_invoice(assigns)
  end
end
