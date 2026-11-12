defmodule FirmowidWeb.Timetracker.Components.Leave do
  @moduledoc "Display components shared by the leave request lists of the team and the profile."
  use FirmowidWeb, :html

  @doc "Renders the icon of a leave reason's group: health, time off or other."
  attr :reason, :atom, required: true
  attr :class, :string, default: "size-4"

  def reason_icon(assigns) do
    ~H"""
    <%= cond do %>
      <% @reason in [:sick, :indisposition] -> %>
        <Lucideicons.cross class={@class} />
      <% @reason in [:rest, :vacation] -> %>
        <Lucideicons.sun class={@class} />
      <% @reason in [:unpaid, :other] -> %>
        <Lucideicons.slash class={@class} />
    <% end %>
    """
  end
end
