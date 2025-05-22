defmodule FirmowidWeb.Components.Timetracker.SubnavigationButtons do
  use FirmowidWeb, :html
  import FirmowidWeb.Components.ButtonGroup

  # should this attribute be passed from parent like now? i dont know what is more phoenix-like
  # in react i would to it like here below, but
  # since subnavigation_buttons are always passed the same prop as show_read_projects we can handle it inside here instead of inside parent
  attr :show_read_projects, :boolean, required: true

  # as of now, the above prop is always Bodyguard.permit?(Firmowid.Timetracker, :read_projects, @current_user)

  def subnavigation_buttons(assigns) do
    ~H"""
    <.button_group buttons={[
      %{
        text: "Ewidencja",
        action: %{type: :link, on_click: ~p"/czasosledz/ewidencja"},
        class: classes(["hover:underline", button_styles(%{color: "grey", variant: "outline"})])
      },
      %{
        text: "Zarządzaj projektami",
        action: %{type: :link, on_click: ~p"/czasosledz/projekty"},
        class: button_styles(%{color: "light_grey"}),
        guard: @show_read_projects
      },
      %{
        text: "Dodaj projekt",
        action: %{type: :link, on_click: ~p"/czasosledz/projekty/dodaj"},
        class:
          classes([
            "hover:underline",
            "flex",
            button_styles(%{color: "black"})
          ]),
        icon: "hero-plus"
      }
    ]} />
    """
  end
end
