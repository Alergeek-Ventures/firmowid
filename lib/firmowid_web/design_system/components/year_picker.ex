defmodule FirmowidWeb.DesignSystem.Components.YearPicker do
  @moduledoc "Year-only picker built on AirDatepicker."
  use FirmowidWeb, :html

  attr :selected_year, :integer, required: true
  attr :disabled, :boolean, default: false
  attr :class, :any, default: nil
  attr :size, :string, values: ~w(big small), default: "small"
  attr :variant, :string, values: ~w(secondary outline), default: "outline"
  attr :rest, :global
  attr :active_years, :list, default: nil

  def year_picker(assigns) do
    ~H"""
    <FirmowidWeb.DesignSystem.Components.Button.button
      as="label"
      variant={@variant}
      size={@size}
      class={["group", @class]}
    >
      <Lucideicons.calendar_1 />
      <input
        type="button"
        class="flex-1 cursor-pointer bg-transparent text-left outline-none"
        phx-hook="AirDatepicker"
        value={@selected_year}
        data-mode="years"
        data-initial-date={"#{@selected_year}-01-01"}
        disabled={@disabled}
        data-enabled-years={@active_years && @active_years |> Enum.join(",")}
        {@rest}
      />
    </FirmowidWeb.DesignSystem.Components.Button.button>
    """
  end
end
