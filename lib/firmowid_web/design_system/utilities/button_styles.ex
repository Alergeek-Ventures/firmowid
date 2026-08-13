defmodule FirmowidWeb.DesignSystem.Utilities.ButtonStyles do
  @moduledoc false

  @doc "Returns the shared design-system size classes for button-like controls."
  @spec size_classes(String.t()) :: String.t()
  def size_classes("big") do
    "h-11 gap-2.5 rounded-lg px-2.75 py-2 text-base/tight font-normal [&>svg]:size-5"
  end

  def size_classes("small") do
    "rounded-md px-2 py-1.5 text-sm/tight font-normal gap-1.5 [&>svg]:size-4"
  end

  @doc "Returns the shared design-system variant classes for button-like controls."
  @spec variant_classes(String.t(), String.t() | nil) :: [String.t()]
  def variant_classes("special", _accent) do
    [
      "border-transparent",
      "bg-black text-white",
      "hover:bg-grey-700 active:bg-grey-800",
      "disabled:bg-grey-400 disabled:text-grey-400"
    ]
  end

  def variant_classes("plain", _accent) do
    [
      "border-transparent",
      "bg-transparent"
    ]
  end

  def variant_classes("icon", _accent) do
    [
      "border border-transparent",
      "bg-transparent text-darkGrey",
      "inline-flex items-center justify-center rounded-[3px] transitions-colors",
      "hover:border-darkGrey active:text-lightGreyBg active:bg-darkGrey"
    ]
  end

  def variant_classes("primary", "orange") do
    [
      "border-transparent",
      "bg-orange-700 text-white",
      "hover:bg-orange-800 active:bg-orange-900",
      "disabled:bg-orange-400"
    ]
  end

  def variant_classes("primary", "turquoise") do
    [
      "border-transparent",
      "bg-turquoise-700 text-white",
      "hover:bg-turquoise-800 active:bg-turquoise-900",
      "disabled:bg-turquoise-400"
    ]
  end

  def variant_classes("secondary", "turquoise") do
    [
      "border-transparent",
      "bg-turquoise-200 text-turquoise-900",
      "hover:bg-turquoise-300 active:bg-turquoise-400",
      "disabled:bg-turquoise-100 disabled:text-turquoise-600"
    ]
  end

  def variant_classes("secondary", "orange") do
    [
      "border-transparent",
      "bg-orange-200 text-orange-900",
      "hover:bg-orange-300 active:bg-orange-400",
      "disabled:bg-orange-100 disabled:text-orange-600"
    ]
  end

  def variant_classes("secondary", _accent) do
    [
      "border-transparent",
      "bg-grey-200 text-grey-900",
      "hover:bg-grey-300 active:bg-grey-400",
      "disabled:bg-grey-100 disabled:text-grey-600"
    ]
  end

  def variant_classes("filter", _accent) do
    [
      "h-fit",
      "bg-lightGreyBg border-greyButtonBg text-darkGrey inline-flex
      items-center justify-center gap-2 rounded-full border px-2 py-1 text-sm/tight font-medium transition-colors",
      "data-active:bg-darkGrey data-active:border-darkGrey data-active:text-white",
      "data-active:hover:bg-darkGrey hover:bg-greyButtonBg"
    ]
  end

  def variant_classes("tertiary", _accent) do
    [
      "border-transparent",
      "bg-grey-700 text-white",
      "hover:bg-grey-800 active:bg-grey-900",
      "disabled:bg-grey-600 disabled:text-grey-300"
    ]
  end

  def variant_classes("outline", _accent) do
    [
      "border-grey-200 text-grey-900",
      "hover:bg-grey-200 active:bg-grey-300",
      "disabled:text-grey-600"
    ]
  end

  def variant_classes("ghost", _accent) do
    [
      "border-transparent text-grey-900",
      "hover:bg-grey-200 active:bg-grey-700 active:text-white",
      "disabled:text-grey-600"
    ]
  end

  def variant_classes("destructive", _accent) do
    [
      "border-transparent",
      "bg-red-200 text-red-800",
      "hover:bg-red-300 active:bg-red-400",
      "disabled:text-red-500"
    ]
  end

  def variant_classes("success", _accent) do
    [
      "border-transparent",
      "bg-green-200 text-green-800",
      "hover:bg-green-300 active:bg-green-400",
      "disabled:text-green-500"
    ]
  end
end
