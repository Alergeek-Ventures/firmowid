defmodule FirmowidWeb.Invoicing.SalesInvoices.Components.Pdf do
  @moduledoc false
  use FirmowidWeb, :html

  alias FirmowidWeb.Invoicing.SalesInvoices.Components.Template

  attr :sales_invoice, :map, required: true
  attr :currency_rate, :map, required: false, default: nil
  attr :class, :any, default: nil
  attr :show_vat, :boolean, default: true
  attr :logo_data_uri, :string, default: nil
  attr :logo_url, :string, default: nil
  attr :footer_logo_data_uri, :string, default: nil
  attr :reference_invoice, :map, default: nil
  attr :include_internal_note_page, :boolean, default: false
  attr :body_chrome, :boolean, default: true

  def sales_invoice(assigns) do
    Template.sales_invoice(assigns)
  end

  attr :sales_invoice, :map, required: true
  attr :show_vat, :boolean, default: true
  attr :logo_data_uri, :string, default: nil
  attr :logo_url, :string, default: nil

  def sales_invoice_print_header(assigns) do
    Template.sales_invoice_print_header(assigns)
  end

  attr :sales_invoice, :map, required: true
  attr :footer_logo_data_uri, :string, default: nil

  def sales_invoice_print_footer(assigns) do
    Template.sales_invoice_print_footer(assigns)
  end
end
