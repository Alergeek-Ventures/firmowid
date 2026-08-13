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
        "hover:bg-grey-100 hover:text-grey-900 phx-click-loading:bg-grey-100 phx-click-loading:cursor-default phx-click-loading:opacity-75 phx-submit-loading:opacity-75 text-grey-700 flex size-8 cursor-pointer items-center justify-center rounded-lg border border-transparent bg-white p-0 leading-6 transition duration-200 focus:outline-none focus-visible:ring-2 focus-visible:ring-orange-700 disabled:pointer-events-none disabled:opacity-40",
        @class
      ]}
      {@rest}
    >
      <Lucideicons.square_pen class="size-4" />
    </.dynamic_tag>
    """
  end
end
