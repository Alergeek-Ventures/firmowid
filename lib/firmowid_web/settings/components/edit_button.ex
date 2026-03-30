defmodule FirmowidWeb.Settings.Components.EditButton do
  @moduledoc false
  use FirmowidWeb, :html

  attr :class, :any, default: nil

  attr :tag_name, :string,
    default: "button",
    doc: "the tag to render the button as"

  attr :rest, :global,
    include: ~w(autocomplete name rel action enctype method novalidate target multipart type for form),
    doc: "the arbitrary HTML attributes to apply to the form tag"

  def edit_button(assigns) do
    ~H"""
    <.dynamic_tag
      tag_name={@tag_name}
      class={[
        "active:bg-lightGreyBg active:text-darkGrey/60 hover:border-darkGrey phx-click-loading:bg-lightGreyBg phx-click-loading:cursor-default phx-click-loading:opacity-75 phx-submit-loading:opacity-75 text-darkGrey flex size-8 cursor-pointer items-center justify-center rounded border border-none bg-white p-0 leading-6 transition-all duration-200 disabled:pointer-events-none disabled:opacity-40",
        @class
      ]}
      {@rest}
    >
      <Lucideicons.square_pen class="size-4" />
    </.dynamic_tag>
    """
  end
end
