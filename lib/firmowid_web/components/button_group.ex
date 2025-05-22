defmodule FirmowidWeb.Components.ButtonGroup do
  use FirmowidWeb, :html

  @doc """
  Creates a list of buttons

  Takes one required parameter which is a List of Map with keys: text, icon, class, action, guard
  action is a Map with keys: type (:button / :link), on_click (provide function for :button type, or URL string for :link type)
  icon is optional, if nothing is provided, nothing is rendered
  class is optional, the default is :nil
  guard is optional, if it is absent, it is treated as :true

  example:
  [
    %{
      text: "Show modal",
      class: button_styles(%{color: "grey", variant: "outline"}),
      action: %{ type: :button, on_click: show_modal },
      guard: Bodyguard.permit?(Firmowid.Timetracker, :read_projects, @current_user)
    },
    %{
      text: "My profile",
      class: classes([
        "hover:underline",
        button_styles(%{color: "grey"})
      ]),
      action: %{ type: :link, on_click: ~p"/czasosledz" }
    }
  ]
  """

  attr :buttons, :list, required: true

  def button_group(assigns) do
    ~H"""
    <%= for button <- @buttons do %>
      <% %{ :text => text, :icon => icon, :class => class, :action => %{ :type => type, :on_click => on_click }, :guard => guard } = Map.merge(button_defaults(), button) %>
      <.link
        :if={guard && type == :link}
        navigate={on_click}
        class={class}
      >
        <%= if icon != :nil do %>
          <.icon name={icon} class="w-6 h-6 mr-2.5" />
        <% end %>
        {text}
      </.link>
    <% end %>
    """
  end

  defp button_defaults(), do: %{ icon: :nil, class: :nil, guard: :true }
end
