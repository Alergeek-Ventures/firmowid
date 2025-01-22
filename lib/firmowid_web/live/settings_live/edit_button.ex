defmodule FirmowidWeb.SettingsLive.EditButton do
  use FirmowidWeb, :html

  attr :class, :string, default: nil

  attr :rest, :global,
    include: ~w(autocomplete name rel action enctype method novalidate target multipart type),
    doc: "the arbitrary HTML attributes to apply to the form tag"

  def edit_button(assigns) do
    ~H"""
    <.button
      class={
        classes([
          "bg-white flex justify-center p-0 size-8 items-center rounded border-none hover:border-darkGrey phx-click-loading:bg-lightGreyBg phx-click-loading:cursor-default phx-click-loading:opacity-60 text-darkGrey active:text-darkGrey/60 active:bg-lightGreyBg",
          @class
        ])
      }
      {@rest}
    >
      <.edit_icon class="h-4 w-4" />
    </.button>
    """
  end
end
