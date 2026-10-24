defmodule FirmowidWeb.Invoicing.Components.StatusButton do
  @moduledoc """
  Compact action button used in invoicing status rows and related status panels.
  """

  use FirmowidWeb, :html

  @doc """
  Renders a compact status action button.
  """
  attr :label, :string, default: nil
  attr :icon, :string, default: nil
  attr :type, :string, default: "button"
  attr :class, :any, default: nil
  attr :rest, :global

  def status_button(assigns) do
    ~H"""
    <FirmowidUI.Components.Button.button
      type={@type}
      variant="unstyled"
      class={[
        "inline-flex h-6 w-20 cursor-pointer items-center justify-center rounded-md bg-grey-200 px-2 text-xs text-grey-700 uppercase transition-all duration-500 phx-click-loading:cursor-default phx-click-loading:opacity-75 phx-submit-loading:opacity-75",
        not is_nil(@label) && "gap-1",
        @class
      ]}
      {@rest}
    >
      <.icon :if={@icon} name={@icon} class="size-4" />
      <span :if={@label}>{@label}</span>
    </FirmowidUI.Components.Button.button>
    """
  end
end
