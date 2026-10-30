defmodule FirmowidWeb.DesignSystem.Components.MonthPicker do
  @moduledoc """
  App-owned month and month range picker controls built on top of the design-system button.
  """

  use FirmowidWeb, :html

  alias Phoenix.LiveView.Rendered

  @sizes ~w(big small)
  @variants ~w(secondary outline)

  @doc """
  Renders a month picker trigger styled like a secondary button.
  """
  @spec month_picker(map()) :: Rendered.t()
  attr :active_months, :list, default: nil
  attr :selected_date, :string, required: true
  attr :disabled, :boolean, default: false
  attr :show_on_mobile, :boolean, default: false
  attr :rest, :global
  attr :class, :any, default: nil
  attr :value, :string, default: nil
  attr :size, :string, values: @sizes, default: "big"
  attr :variant, :string, values: @variants, default: "secondary"

  def month_picker(assigns) do
    ~H"""
    <FirmowidUI.Components.Button.button
      as="label"
      variant={@variant}
      size={@size}
      class={
        [
          "group has-disabled:bg-grey-100 has-disabled:text-grey-600",
          !@show_on_mobile && "max-md:hidden",
          # icon has "spacing" in it, we have to compensate
          @size == "big" && "min-w-42 pr-4",
          @size == "small" && "min-w-38 pr-2",
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
    </FirmowidUI.Components.Button.button>
    """
  end

  @doc """
  Renders a picker of a range of months, styled like the month picker. The picker shows a selected range, otherwise
  `label`. Choosing the second month sends `select-period` with the ISO `from`
  and `to` months; the clear button sends it without them.
  """
  @spec month_range_picker(map()) :: Rendered.t()
  attr :id, :string, required: true
  attr :selected, :any, required: true, doc: "first and last month of the selected range, or nil"
  attr :label, :string, required: true, doc: "what the trigger shows without a selected range"
  attr :clear_label, :string, required: true, doc: "text of the button clearing the range"
  attr :size, :string, values: @sizes, default: "big"
  attr :variant, :string, values: @variants, default: "secondary"
  attr :rest, :global

  def month_range_picker(assigns) do
    ~H"""
    <FirmowidUI.Components.Button.button
      as="label"
      variant={@variant}
      size={@size}
      class="group pr-4 has-focus-visible:outline-2 has-focus-visible:outline-offset-2 has-focus-visible:outline-teal-700"
    >
      <Lucideicons.calendar_range />
      <input
        id={@id}
        type="text"
        readonly
        placeholder={@label}
        class="field-sizing-content flex-1 cursor-pointer border-0 bg-transparent p-0 text-left text-[length:inherit] shadow-none outline-none placeholder:text-current focus:ring-0"
        phx-hook="AirDatepicker"
        data-mode="months"
        data-range="true"
        data-initial-date={Date.to_iso8601((@selected && elem(@selected, 0)) || Date.utc_today())}
        data-selected-dates={
          @selected && @selected |> Tuple.to_list() |> Enum.map_join(",", &Date.to_iso8601/1)
        }
        data-clear-label={@clear_label}
        {@rest}
      />
    </FirmowidUI.Components.Button.button>
    """
  end
end
