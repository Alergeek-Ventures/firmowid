defmodule FirmowidWeb.Invoicing.Components.Print do
  @moduledoc false
  use FirmowidWeb, :html

  attr :class, :string, default: nil
  slot :inner_block, required: true

  def a4_page(assigns) do
    ~H"""
    <div class={[
      "relative mx-auto box-content flex min-h-[calc(842px-2*32px)] w-[calc(595px-2*32px)] flex-col bg-white p-8 print:h-auto print:min-h-[calc(842px-2*32px)]",
      @class
    ]}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :internal_note, :string, required: true
  attr :footer_logo_data_uri, :string, default: nil

  def internal_note_page(assigns) do
    ~H"""
    <.a4_page class="mt-4">
      <div class="flex h-full flex-col">
        <div class="mt-6 flex-1 text-sm/6 whitespace-pre-wrap text-neutral-900">
          {@internal_note}
        </div>

        <div class="flex w-full flex-col items-center justify-center">
          <%= if @footer_logo_data_uri do %>
            <img src={@footer_logo_data_uri} class="mb-2 size-8 object-contain" />
          <% end %>

          <p class="text-sm text-neutral-700">firmowid.pl</p>
        </div>
      </div>
    </.a4_page>
    """
  end
end
