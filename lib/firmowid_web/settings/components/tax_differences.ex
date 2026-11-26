defmodule FirmowidWeb.Settings.Components.TaxDifferences do
  @moduledoc """
  The settings that the transfers indicate differently than the year has saved,
  every one as `Setting: saved → indicated`, for the taxes card and the inbox.
  """

  use FirmowidWeb, :html

  alias FirmowidWeb.Settings.Utilities.TaxSettings

  @doc """
  The differences (`TaxSettings.differences/2`) as inline text, joined with
  semicolons. The arrow is decoration; a screen reader hears "change to".
  `highlight` sets the indicated values apart, `lead` opens the sentence and
  `end_with` closes it.
  """
  attr :differences, :list, required: true
  attr :lead, :string, default: nil
  attr :highlight, :boolean, default: false
  attr :end_with, :string, default: ""

  def list(assigns) do
    last = length(assigns.differences)

    assigns =
      assigns
      |> assign(:items, Enum.with_index(assigns.differences, 1))
      |> assign(:last, last)

    ~H"""
    <span :if={@lead}>{@lead}{" "}</span>
    <.item
      :for={{difference, index} <- @items}
      difference={difference}
      highlight={@highlight}
      closing={if index == @last, do: @end_with, else: "; "}
    />
    """
  end

  attr :difference, :map, required: true
  attr :highlight, :boolean, required: true
  attr :closing, :string, required: true

  defp item(assigns) do
    %{setting: setting, saved: saved, indicated: indicated} = assigns.difference

    assigns =
      assigns
      |> assign(:setting, TaxSettings.setting_label(setting))
      |> assign(:saved, TaxSettings.value_label(setting, saved))
      |> assign(:indicated, TaxSettings.value_label(setting, indicated))
      |> assign(:change_to, pgettext("saved value to indicated value", "change to"))

    ~H"""
    <span>{@setting}: {@saved}
    <span aria-hidden="true">→</span><span class="sr-only">{@change_to}</span> <span class={[
      @highlight && "font-medium text-moss-700"
    ]}>{@indicated}</span>{@closing}</span>
    """
  end
end
