defmodule FirmowidWeb.DesignSystem.Components.Tabs do
  @moduledoc """
  Navigation between sibling views of one page, and the pill toggle for switching a list's scope.
  """

  use FirmowidUI, :html

  alias Phoenix.LiveView.Rendered

  @doc """
  Renders underline tabs. Each tab is a link (`patch` or `navigate`) so the selected
  view lives in the URL. Tabs are neutral: they never take a ledger colour.
  """
  @spec tabs(map()) :: Rendered.t()
  attr :label, :string, required: true, doc: "Accessible name of the tab navigation."
  attr :class, :any, default: nil

  slot :tab, required: true do
    attr :patch, :string
    attr :navigate, :string
    attr :active, :boolean
  end

  def tabs(assigns) do
    ~H"""
    <nav aria-label={@label} class={["flex gap-6 border-b border-grey-200", @class]}>
      <.link
        :for={tab <- @tab}
        patch={tab[:patch]}
        navigate={tab[:navigate]}
        aria-current={tab[:active] && "page"}
        class={[
          "-mb-px flex items-center gap-2 border-b-2 pb-2.5 text-sm font-medium whitespace-nowrap transition-colors [&>svg]:size-4",
          tab_state_styles(tab[:active])
        ]}
      >
        {render_slot(tab)}
      </.link>
    </nav>
    """
  end

  @doc """
  Renders a segmented control: a group of pills where exactly one is active, for
  switching the scope of a list (for example active and archived records).
  Options are links (`patch` or `navigate`) or buttons with `phx-click`.
  """
  @spec segmented_control(map()) :: Rendered.t()
  attr :label, :string, required: true, doc: "Accessible name of the group."
  attr :class, :any, default: nil

  slot :option, required: true do
    attr :patch, :string
    attr :navigate, :string
    attr :active, :boolean
    attr :"phx-click", :any
    attr :"phx-value-value", :any
  end

  def segmented_control(assigns) do
    ~H"""
    <div role="group" aria-label={@label} class={["flex flex-wrap gap-2", @class]}>
      <%= for option <- @option do %>
        <.link
          :if={option[:patch] || option[:navigate]}
          patch={option[:patch]}
          navigate={option[:navigate]}
          aria-current={option[:active] && "page"}
          class={[segment_base_styles(), segment_state_styles(option[:active])]}
        >
          {render_slot(option)}
        </.link>
        <button
          :if={!(option[:patch] || option[:navigate])}
          type="button"
          aria-pressed={to_string(option[:active] == true)}
          phx-click={option[:"phx-click"]}
          phx-value-value={option[:"phx-value-value"]}
          class={[segment_base_styles(), segment_state_styles(option[:active])]}
        >
          {render_slot(option)}
        </button>
      <% end %>
    </div>
    """
  end

  defp tab_state_styles(true), do: "border-grey-900 text-grey-900"

  defp tab_state_styles(_inactive), do: "border-transparent text-grey-600 hover:border-grey-300 hover:text-grey-900"

  defp segment_base_styles,
    do:
      "inline-flex h-8 cursor-pointer items-center gap-1.5 rounded-full px-3 text-sm font-medium whitespace-nowrap transition-colors [&>svg]:size-4"

  defp segment_state_styles(true), do: "bg-grey-700 text-white"
  defp segment_state_styles(_inactive), do: "text-grey-700 hover:bg-grey-200"
end
