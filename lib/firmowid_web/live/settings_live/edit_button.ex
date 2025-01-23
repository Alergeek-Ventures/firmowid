defmodule FirmowidWeb.SettingsLive.EditButton do
  use FirmowidWeb, :html

  attr :class, :string, default: nil

  attr :tag_name, :string,
    default: "button",
    doc: "the tag to render the button as"

  attr :rest, :global,
    include:
      ~w(autocomplete name rel action enctype method novalidate target multipart type for form),
    doc: "the arbitrary HTML attributes to apply to the form tag"

  def edit_button(assigns) do
    ~H"""
    <.dynamic_tag
      tag_name={@tag_name}
      class={
        classes([
          button_styles(),
          "bg-white flex justify-center p-0 size-8 items-center rounded border-none hover:border-darkGrey phx-click-loading:bg-lightGreyBg phx-click-loading:cursor-default phx-click-loading:opacity-60 text-darkGrey active:text-darkGrey/60 active:bg-lightGreyBg cursor-pointer",
          @class
        ])
      }
      {@rest}
    >
      <.edit_icon class="h-4 w-4" />
    </.dynamic_tag>
    """
  end
end
