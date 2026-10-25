defmodule FirmowidWeb.Management.Components.Card do
  @moduledoc "Management-specific card content: inline edit actions."
  use FirmowidWeb, :html

  import FirmowidUI.Components.Button

  attr :editing, :boolean, required: true
  attr :form, :string, default: nil
  attr :toggle_event, :string, required: true
  attr :target, :any, default: nil

  def card_edit_actions(assigns) do
    ~H"""
    <%= if @editing do %>
      <.button
        form={@form}
        type="submit"
        variant="secondary"
        size="small"
        accent="rust"
        class="ml-2"
      >
        Zapisz
      </.button>
      <.button
        type="button"
        variant="ghost"
        size="small"
        phx-click={@toggle_event}
        phx-target={@target}
      >
        <.icon name="hero-arrow-uturn-left-micro" class="size-4" />
      </.button>
    <% else %>
      <.button
        type="button"
        variant="ghost"
        size="small"
        phx-click={@toggle_event}
        phx-target={@target}
      >
        <.icon name="hero-pencil-square" class="size-5" />
      </.button>
    <% end %>
    """
  end
end
