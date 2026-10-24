defmodule FirmowidUI.Utilities.ButtonStyles do
  @moduledoc false

  @doc "Returns the shared design-system size classes for button-like controls."
  @spec size_classes(String.t()) :: String.t()
  def size_classes("big") do
    "h-11 gap-2.5 rounded-lg px-2.75 py-2 text-base/tight font-normal [&>svg]:size-5"
  end

  def size_classes("small") do
    "h-8 rounded-md px-2 py-1.5 text-sm/tight font-normal gap-1.5 [&>svg]:size-4"
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
      "bg-transparent text-grey-700",
      "inline-flex items-center justify-center rounded-[3px] transition-colors",
      "hover:border-grey-700 active:text-grey-100 active:bg-grey-700"
    ]
  end

  def variant_classes("primary", "rust") do
    [
      "border-transparent",
      "bg-rust-700 text-white",
      "hover:bg-rust-800 active:bg-rust-900",
      "disabled:bg-rust-400"
    ]
  end

  def variant_classes("primary", "teal") do
    [
      "border-transparent",
      "bg-teal-700 text-white",
      "hover:bg-teal-800 active:bg-teal-900",
      "disabled:bg-teal-400"
    ]
  end

  def variant_classes("secondary", "teal") do
    [
      "border-transparent",
      "bg-teal-200 text-teal-900",
      "hover:bg-teal-300 active:bg-teal-400",
      "disabled:bg-teal-100 disabled:text-teal-600"
    ]
  end

  def variant_classes("secondary", "rust") do
    [
      "border-transparent",
      "bg-rust-200 text-rust-900",
      "hover:bg-rust-300 active:bg-rust-400",
      "disabled:bg-rust-100 disabled:text-rust-600"
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
      "bg-grey-100 border-grey-200 text-grey-700 inline-flex
      items-center justify-center gap-2 rounded-full border px-2 py-1 text-sm/tight font-medium transition-colors",
      "data-active:bg-grey-700 data-active:border-grey-700 data-active:text-white",
      "data-active:hover:bg-grey-700 hover:bg-grey-200"
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
      "bg-brick-200 text-brick-800",
      "hover:bg-brick-300 active:bg-brick-400",
      "disabled:text-brick-500"
    ]
  end

  def variant_classes("success", _accent) do
    [
      "border-transparent",
      "bg-moss-200 text-moss-800",
      "hover:bg-moss-300 active:bg-moss-400",
      "disabled:text-moss-500"
    ]
  end
end
