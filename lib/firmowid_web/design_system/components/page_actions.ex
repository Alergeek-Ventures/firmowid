defmodule FirmowidWeb.DesignSystem.Components.PageActions do
  @moduledoc """
  Primary actions of a page: an inline toolbar on wide screens and a floating action
  button (FAB) in the bottom corner on phones.
  """

  use FirmowidUI, :html

  import FirmowidUI.Components.Button

  alias Phoenix.LiveView.JS
  alias Phoenix.LiveView.Rendered

  @doc """
  Renders page actions. On phones a single action floats as a round icon-only FAB;
  wrap its label in `<span class="max-md:sr-only">` so it stays the accessible name.
  Several actions collapse into one round "+" FAB (`label` is its accessible name)
  that expands into the actions stacked above it over a dimmed page (Material speed
  dial); the last (rightmost on wide screens) action sits closest to the main button.
  The app layout reserves space below the content for the FAB (`data-page-actions`),
  so the last list row can always be scrolled above it.

  Mark the clickable element of each action with `data-fab`; it gets the round FAB
  shape on phones while keeping its own colours.
  """
  @spec page_actions(map()) :: Rendered.t()
  attr :id, :string, default: "page-actions"

  attr :label, :string,
    default: nil,
    doc: "Accessible name of the main FAB when there are several actions."

  attr :class, :any, default: nil
  attr :rest, :global
  slot :action, required: true

  def page_actions(assigns) do
    ~H"""
    <div
      id={@id}
      data-page-actions
      phx-click-away={length(@action) > 1 && close(@id)}
      class={[
        "group flex items-center gap-4 max-md:fixed max-md:right-4 max-md:bottom-[calc(1rem+env(safe-area-inset-bottom))] max-md:z-50 max-md:flex-col max-md:items-end max-md:gap-3 max-md:**:data-fab:h-14 max-md:**:data-fab:rounded-full max-md:**:data-fab:shadow-lg",
        if(length(@action) > 1,
          do: "max-md:**:data-fab:px-5",
          else: "max-md:**:data-fab:w-14 max-md:**:data-fab:px-0 max-md:[&_[data-fab]_svg]:size-6"
        ),
        @class
      ]}
      {@rest}
    >
      <div
        :if={length(@action) > 1}
        aria-hidden="true"
        phx-click={close(@id)}
        class="invisible fixed inset-0 -z-10 bg-black/40 opacity-0 transition-[opacity,visibility] duration-150 group-data-open:visible group-data-open:opacity-100 md:hidden"
      />
      <div
        id={"#{@id}-menu"}
        class={[
          "flex items-center gap-4",
          if(length(@action) > 1,
            do:
              "max-md:invisible max-md:translate-y-2 max-md:flex-col max-md:items-end max-md:gap-3 max-md:opacity-0 max-md:transition-[opacity,translate,visibility] max-md:duration-150 max-md:group-data-open:visible max-md:group-data-open:translate-y-0 max-md:group-data-open:opacity-100",
            else: "max-md:contents"
          )
        ]}
      >
        {render_slot(@action)}
      </div>
      <.button
        :if={length(@action) > 1}
        type="button"
        variant="special"
        class="size-14 px-0! md:hidden"
        aria-label={@label}
        aria-expanded="false"
        aria-controls={"#{@id}-menu"}
        phx-click={toggle(@id)}
        data-fab
      >
        <Lucideicons.plus class="size-6! transition-transform duration-150 group-data-open:rotate-45" />
      </.button>
    </div>
    """
  end

  defp toggle(id) do
    {"data-open", "true"}
    |> JS.toggle_attribute(to: "##{id}")
    |> JS.toggle_attribute({"aria-expanded", "true", "false"}, to: "##{id} > button")
  end

  defp close(id) do
    "data-open"
    |> JS.remove_attribute(to: "##{id}")
    |> JS.set_attribute({"aria-expanded", "false"}, to: "##{id} > button")
  end
end
