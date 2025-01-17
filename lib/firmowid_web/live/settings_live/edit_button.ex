defmodule FirmowidWeb.SettingsLive.EditButton do
  use FirmowidWeb, :html

  attr :class, :string, default: nil

  attr :rest, :global,
    include: ~w(autocomplete name rel action enctype method novalidate target multipart type),
    doc: "the arbitrary HTML attributes to apply to the form tag"

  def edit_button(assigns) do
    ~H"""
    <.button
      phx-disable-with=""
      class={
        classes([
          "bg-lightGreyBg flex justify-center p-0 size-8 items-center rounded border-none hover:border-darkGrey disabled:bg-lightGreyBg disabled:cursor-default",
          @class
        ])
      }
      {@rest}
    >
      <.edit_icon class="h-4 w-4 text-darkGrey" />
    </.button>
    """
  end
end
