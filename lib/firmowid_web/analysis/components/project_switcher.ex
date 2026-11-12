defmodule FirmowidWeb.Analysis.Components.ProjectSwitcher do
  @moduledoc """
  Switches the trends between the whole company and one project: a menu of links to the same
  period with the project's filter, the selected one checked.
  """
  use FirmowidWeb, :html

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
        variant="secondary"
        size="big"
        aria-haspopup="menu"
        aria-label={gettext("Show: %{slice}", slice: @label)}
        phx-click={show_popover("#{@id}-menu")}
      >
        <Lucideicons.folder_kanban aria-hidden="true" />
        <span class="max-w-48 truncate">{@label}</span>
        <Lucideicons.chevron_down class="size-4 text-grey-700" aria-hidden="true" />
      </FirmowidUI.Components.Button.button>
      <.popover id={"#{@id}-menu"} reference_id={"#{@id}-trigger"} placement="bottom-start">
        <div
          role="menu"
          aria-label={gettext("Show")}
          class="flex max-h-(--popover-available-height) min-w-56 flex-col overflow-y-auto overscroll-contain rounded-lg bg-white p-1 shadow-lg ring-1 ring-grey-700/10"
        >
          <FirmowidUI.Components.Link.link
            :for={option <- @options}
            kind="unstyled"
            role="menuitem"
            patch={option.patch}
            phx-click={hide_popover("#{@id}-menu")}
            aria-current={option.selected? && "true"}
            class="flex min-h-9 w-full cursor-pointer items-center justify-between gap-2 rounded-md px-2.5 text-start text-sm text-grey-900 hover:bg-grey-100 active:bg-grey-200"
          >
            <span class="truncate">{option.name}</span>
            <Lucideicons.check :if={option.selected?} class="size-4 shrink-0" aria-hidden="true" />
          </FirmowidUI.Components.Link.link>
        </div>
      </.popover>
    </div>
    """
  end
end
