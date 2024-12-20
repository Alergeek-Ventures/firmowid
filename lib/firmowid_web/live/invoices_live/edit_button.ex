defmodule FirmowidWeb.InvoicesLive.EditButton do
  use FirmowidWeb, :html

  attr :rest, :global,
    include: ~w(autocomplete name rel action enctype method novalidate target multipart),
    doc: "the arbitrary HTML attributes to apply to the form tag"

  def edit_button(assigns) do
    ~H"""
    <.button
      type="button"
      phx-disable-with=""
      class="bg-lightGreyBg rounded border-none hover:border-darkGrey disabled:bg-lightGreyBg disabled:cursor-default"
      {@rest}
    >
      <.edit_icon class="w-6 h-6 text-darkGrey" />
    </.button>
    """
  end
end
