defmodule FirmowidUI.Invoicing.Components.Print do
  @moduledoc """
  Shared A4 document layout and internal-note page for invoice previews and PDFs.

  These function components render document content without browser navigation
  or PDF generation infrastructure.
  """
  use FirmowidUI, :html

  alias Phoenix.LiveView.Rendered

  attr :class, :string, default: nil
  slot :inner_block, required: true

  @doc "Renders slotted document content in the invoice's printable A4 page layout."
  @spec a4_page(map()) :: Rendered.t()
  def a4_page(assigns) do
    ~H"""
    <div class={[
      "relative mx-auto box-content flex min-h-[calc(842px-2*32px)] w-[calc(595px-2*32px)] flex-col bg-white p-8 print:h-auto print:min-h-0 print:w-full print:p-0",
      @class
    ]}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :internal_note, :string, required: true
  attr :footer_logo_data_uri, :string, default: nil

  @doc "Renders an internal note on a separate A4 page with an optional embedded footer logo."
  @spec internal_note_page(map()) :: Rendered.t()
  def internal_note_page(assigns) do
    ~H"""
    <.a4_page class="mt-4 print:static">
      <div class="flex h-full flex-col">
        <div class="text-neutral-900 mt-6 flex-1 text-sm/6 whitespace-pre-wrap">{@internal_note}</div>

        <div class="flex w-full flex-col items-center justify-center print:absolute print:inset-x-0 print:bottom-0">
          <%= if @footer_logo_data_uri do %>
            <img src={@footer_logo_data_uri} class="mb-2 size-8 object-contain" />
          <% end %>

          <p class="text-neutral-700 text-sm">firmowid.pl</p>
        </div>
      </div>
    </.a4_page>
    """
  end
end
