defmodule FirmowidWeb.Management.Components.Card do
  @moduledoc "Shared card components for the management section."
  use FirmowidWeb, :html

  import FirmowidWeb.DesignSystem.Components.Button
  import FirmowidWeb.DesignSystem.Components.CoreComponents, except: [button: 1]

  attr :label, :string, required: true
  attr :for, :string, default: ""
  attr :class, :any, default: ""
  slot :inner_block

  def user_card_info(assigns) do
    ~H"""
    <div class={["space-y-1", @class]}>
      <label for={@for} class="text-grey-700 block text-sm/snug">{@label}</label>
      <div class="flex items-center gap-2 text-base/snug">{render_slot(@inner_block)}</div>
    </div>
    """
  end

  attr :class, :any, default: ""
  attr :gap_size, :string, default: "6"
  attr :dimmed, :boolean, default: false
  slot :inner_block, required: true

  def card(assigns) do
    ~H"""
    <section class={[
      "relative flex flex-col rounded-md bg-white p-6 text-black shadow",
      @gap_size && "gap-y-#{@gap_size}",
      @class
    ]}>
      <div
        :if={@dimmed}
        class="absolute inset-0 z-10 rounded-md bg-white/60"
      >
      </div>
      {render_slot(@inner_block)}
    </section>
    """
  end

  slot :inner_block, required: true
  slot :actions

  def card_header(assigns) do
    ~H"""
    <div class="flex min-h-8.5 flex-row items-center gap-2">
      <h3 class="text-grey-900 text-base/tight font-medium">
        {render_slot(@inner_block)}
      </h3>
      <div :if={Enum.any?(@actions)} class="flex items-center gap-2">
        {render_slot(@actions)}
      </div>
    </div>
    """
  end

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
        accent="orange"
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
