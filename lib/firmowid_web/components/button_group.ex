defmodule FirmowidWeb.Components.ButtonGroup do
  @moduledoc false
  use FirmowidWeb, :html

  @doc """
  Creates a list of buttons

  Takes one required parameter which is a List of Map with keys: text, action, button_class, icon, icon_class, guard
  text is mandatory
  action is an URL string for :link type
  button_class is optional, the default is :nil
  icon is optional, if nothing is provided, nothing is rendered
  icon_class is optional, icon is not styled if nothing is provided
  guard is optional, if it is absent, it is treated as :true
  """

  attr :buttons, :list, required: true

  def button_group(assigns) do
    ~H"""
    <%= for button <- @buttons do %>
      <% %{
        :text => text,
        :button_class => button_class,
        :action => action,
        :icon => icon,
        :icon_class => icon_class,
        :guard => guard
      } = Map.merge(button_defaults(), button) %>
      <.link :if={guard} navigate={action} class={button_class}>
        <%= if icon != :nil do %>
          <.icon name={icon} class={icon_class} />
        <% end %>
        {text}
      </.link>
    <% end %>
    """
  end

  defp button_defaults, do: %{button_class: nil, icon: nil, icon_class: nil, guard: true}
end
