defmodule FirmowidWeb.Analysis.Components.ProjectSwitcher do
  @moduledoc """
  Switches the trends between the whole company and one project: a menu of links to the same
  period with the project's filter, the selected one checked.
  """
  use FirmowidWeb, :html

  import FirmowidWeb.DesignSystem.Components.FigmaIcon, only: [figma_icon: 1]
  import FirmowidWeb.DesignSystem.Components.Menu, only: [dropdown_panel_styles: 0]

  attr :id, :string, required: true
  attr :label, :string, required: true, doc: "the shown slice's name"

  attr :options, :list,
    required: true,
    doc: "`%{name, patch, selected?}` for the whole company and each project"

  @doc "Renders the project switcher."
  @spec switcher(map()) :: Phoenix.LiveView.Rendered.t()
  def switcher(assigns) do
    ~H"""
    <div class="inline-flex">
      <FirmowidUI.Components.Button.button
        id={"#{@id}-trigger"}
        type="button"
        variant="tertiary"
        size="big"
        aria-haspopup="menu"
        aria-label={gettext("Show: %{slice}", slice: @label)}
        phx-click={show_popover("#{@id}-menu")}
      >
        <.figma_icon name="projekty" />
        <span class="max-w-48 truncate">{@label}</span>
        <.figma_icon name="chevron_down" />
      </FirmowidUI.Components.Button.button>
      <.popover id={"#{@id}-menu"} reference_id={"#{@id}-trigger"} placement="bottom-end">
        <div
          role="menu"
          aria-label={gettext("Show")}
          class={[
            "flex max-h-(--popover-available-height) w-60 flex-col overflow-y-auto overscroll-contain",
            dropdown_panel_styles()
          ]}
        >
          <FirmowidUI.Components.Link.link
            :for={option <- @options}
            kind="unstyled"
            role="menuitem"
            patch={option.patch}
            phx-click={hide_popover("#{@id}-menu")}
            aria-current={option.selected? && "true"}
            class="flex min-h-9 w-full cursor-pointer items-center justify-between gap-2 rounded-sm px-3 text-start text-sm/[1.35] text-black hover:bg-grey-200 active:bg-grey-300"
          >
            <span class="truncate">{option.name}</span>
            <.figma_icon :if={option.selected?} name="check" class="size-4" />
          </FirmowidUI.Components.Link.link>
        </div>
      </.popover>
    </div>
    """
  end
end
