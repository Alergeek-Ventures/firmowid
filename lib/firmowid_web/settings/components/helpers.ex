defmodule FirmowidWeb.Settings.Components.Helpers do
  @moduledoc """
  Shared presentational helpers for settings components.
  """

  use FirmowidWeb, :html

  alias Phoenix.LiveView.Rendered

  @doc """
  Builds a compact text label used in bank logo placeholders.
  """
  @spec bank_logo_label(map()) :: String.t()
  def bank_logo_label(%{institution_name: nil}), do: "BANK"
  def bank_logo_label(%{institution_name: ""}), do: "BANK"

  def bank_logo_label(%{institution_name: institution_name}) do
    institution_name
    |> String.split(~r/\s+/, trim: true)
    |> Enum.take(2)
    |> Enum.map_join(&String.first/1)
    |> String.upcase()
  end

  @doc """
  Renders a bank logo tile using GoCardless institution metadata when available.
  """
  @spec bank_logo(map()) :: Rendered.t()
  attr :account, :map, required: true
  attr :bank_institutions, :map, default: %{}
  attr :class, :string, default: nil

  def bank_logo(assigns) do
    institution = Map.get(assigns.bank_institutions, assigns.account.institution_id)

    assigns =
      assigns
      |> assign(:institution, institution)
      |> assign(:label, bank_logo_label(assigns.account))
      |> assign(:logo_url, bank_logo_url(institution))
      |> assign(:logo_alt, bank_logo_alt(assigns.account, institution))
      |> assign(:logo_style, bank_logo_style(institution))
      |> assign(:background_class, bank_logo_background_class(bank_logo_url(institution)))

    ~H"""
    <div
      class={[
        "flex h-[42px] w-[72px] items-center justify-center overflow-hidden rounded-sm border border-black/5",
        @background_class,
        @class
      ]}
      style={@logo_style}
    >
      <img
        :if={@logo_url}
        src={@logo_url}
        alt={@logo_alt}
        class="max-h-[70%] max-w-[78%] object-contain"
        loading="lazy"
      />
      <span :if={!@logo_url} class="text-caps-sm text-grey-700 font-semibold tracking-[0.02em]">
        {@label}
      </span>
    </div>
    """
  end

  @doc """
  Renders a settings form field with the label above its control.
  """
  @spec settings_field(map()) :: Rendered.t()
  attr :label, :string, required: true
  attr :class, :any, default: nil
  attr :label_class, :any, default: nil
  slot :inner_block, required: true

  def settings_field(assigns) do
    ~H"""
    <label class={["flex flex-col gap-1", @class]}>
      <span class={["text-grey-700 text-sm leading-[1.35]", @label_class]}>{@label}</span>
      {render_slot(@inner_block)}
    </label>
    """
  end

  @doc """
  Renders a read-only settings value with the label above the displayed content.
  """
  @spec settings_display_field(map()) :: Rendered.t()
  attr :label, :string, required: true
  attr :class, :any, default: nil
  attr :label_class, :any, default: nil
  attr :value_class, :any, default: nil
  slot :inner_block, required: true

  def settings_display_field(assigns) do
    ~H"""
    <div class={["flex flex-col gap-1", @class]}>
      <div class={["text-grey-700 text-sm leading-[1.35]", @label_class]}>{@label}</div>
      <div class={["text-grey-900 text-base leading-[1.35]", @value_class]}>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  defp bank_logo_url(%{logo: logo}) when is_binary(logo) and logo != "", do: logo
  defp bank_logo_url(_institution), do: nil

  defp bank_logo_alt(_account, %{name: name}) when is_binary(name) and name != "", do: "Logo #{name}"

  defp bank_logo_alt(%{institution_name: name}, _institution) when is_binary(name) and name != "", do: "Logo #{name}"

  defp bank_logo_alt(_account, _institution), do: "Logo banku"

  defp bank_logo_style(%{dominant_color_rgb: color_rgb}) when is_binary(color_rgb) do
    color_rgb = String.trim(color_rgb)

    if color_rgb == "" do
      nil
    else
      "background-color: rgb(#{color_rgb} / 0.18);"
    end
  end

  defp bank_logo_style(_institution), do: nil

  defp bank_logo_background_class(nil), do: "bg-grey-100"
  defp bank_logo_background_class(_logo_url), do: "bg-white"
end
