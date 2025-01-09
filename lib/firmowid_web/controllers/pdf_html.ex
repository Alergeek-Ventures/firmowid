defmodule FirmowidWeb.PdfHTML do
  use FirmowidWeb, :html

  attr :invoice, :map, required: true
  attr :currency_rate, :map, required: false, default: nil
  attr :class, :string, default: nil

  def invoice(assigns) do
    FirmowidWeb.Invoice.Template.invoice(assigns)
  end
end
