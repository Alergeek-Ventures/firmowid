defmodule FirmowidWeb.Management.Components.Tab do
  @moduledoc false
  use FirmowidWeb, :html

  import FirmowidUI.Components.Link
  import Phoenix.Component, except: [link: 1]

  attr :patch, :string, required: true
  attr :active, :boolean, default: false
  attr :class, :any, default: ""
  slot :inner_block

  def tab(assigns) do
    ~H"""
    <.link
      kind="unstyled"
      patch={@patch}
      class="z-0 h-auto rounded-lg border-transparent bg-transparent px-3 pt-3 pb-5 text-grey-700 hover:text-turquoise-600 disabled:text-grey-500 data-active:bg-grey-50 data-active:text-turquoise-600 data-active:shadow"
      data-active={@active}
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end
end
