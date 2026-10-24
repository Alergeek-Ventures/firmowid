defmodule FirmowidUI.Invoicing.Components.InvoiceNotes do
  @moduledoc "Invoice note and internal comment fields shared by browser and MCP reviews."
  use FirmowidUI, :html

  attr :invoice_note, :string, default: nil
  attr :internal_note, :string, default: nil

  attr :class, :any,
    default: nil,
    doc: "Layout and text size of the fields, such as a compact two-column grid."

  @doc "Renders both fields in one form that sends `update_notes` on change."
  @spec invoice_notes(map()) :: Phoenix.LiveView.Rendered.t()
  def invoice_notes(assigns) do
    ~H"""
    <form id="invoice-notes-form" phx-change="update_notes" class={["grid gap-3", @class]}>
      <label class="grid gap-2 text-sm text-grey-500">
        {gettext("Note on the invoice")}
        <textarea
          id="invoice-note"
          name="invoice_note"
          rows="3"
          placeholder={gettext("Visible on the invoice and in KSeF (invoice footer)")}
          class="resize-none rounded-lg border border-grey-200 px-3 py-2 text-sm text-grey-700 inline-full placeholder:text-grey-400 focus:border-transparent focus:ring-2 focus:ring-teal-500"
        >{@invoice_note || ""}</textarea>
      </label>
      <label class="grid gap-2 text-sm text-grey-500">
        {gettext("Comment")}
        <textarea
          id="internal-note"
          name="internal_note"
          rows="3"
          placeholder={gettext("Internal note, not shown on the invoice (only in Firmowid)")}
          class="resize-none rounded-lg border border-grey-200 px-3 py-2 text-sm text-grey-700 inline-full placeholder:text-grey-400 focus:border-transparent focus:ring-2 focus:ring-teal-500"
        >{@internal_note || ""}</textarea>
      </label>
    </form>
    """
  end
end
