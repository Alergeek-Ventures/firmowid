defmodule FirmowidWeb.Invoicing.CostInvoices.Components.Pdf do
  @moduledoc false
  use FirmowidWeb, :html

  alias FirmowidWeb.Invoicing.Components.Print

  attr :internal_note, :string, required: true
  attr :footer_logo_data_uri, :string, default: nil

  def internal_note_page(assigns) do
    ~H"""
    <Print.internal_note_page
      internal_note={@internal_note}
      footer_logo_data_uri={@footer_logo_data_uri}
    />
    """
  end
end
