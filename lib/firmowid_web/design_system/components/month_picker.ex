defmodule FirmowidWeb.DesignSystem.Components.MonthPicker do
  @moduledoc """
  App-owned month picker control built on top of the design-system button.
  """

  use FirmowidWeb, :html

  @sizes ~w(big small)
  @variants ~w(secondary outline)

  @doc """
  Renders a month picker trigger styled like a secondary button.
  """
  @spec month_picker(map()) :: Phoenix.LiveView.Rendered.t()
  attr :active_months, :list, default: nil
  attr :selected_date, :string, required: true
  attr :disabled, :boolean, default: false
  attr :rest, :global
  attr :class, :any, default: nil
  attr :value, :string, default: nil
  attr :size, :string, values: @sizes, default: "big"
  attr :variant, :string, values: @variants, default: "secondary"

  def month_picker(assigns) do
    ~H"""
    <FirmowidWeb.DesignSystem.Components.Button.button
      as="label"
      variant={@variant}
      size={@size}
      class={
        [
          "group has-disabled:bg-grey-100 has-disabled:text-grey-600 min-w-42 pr-4 max-md:hidden",
          # icon has "spacing" in it, we have to compensate
          @class
        ]
      }
    >
      <Lucideicons.calendar_1 />
      <input
        type="button"
        class="flex-1 cursor-pointer bg-transparent text-left outline-none"
        phx-hook="AirDatepicker"
        value={@value}
        data-enabled-months={
          @active_months && @active_months |> Enum.map(&Date.to_iso8601/1) |> Enum.join(",")
        }
        data-initial-date={@selected_date}
        disabled={@disabled}
        {@rest}
      />
    </FirmowidWeb.DesignSystem.Components.Button.button>
    """
  end
end
