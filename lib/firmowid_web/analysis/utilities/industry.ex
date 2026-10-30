defmodule FirmowidWeb.Analysis.Utilities.Industry do
  @moduledoc """
  Labels of the industries an organization chooses its analysis template from.
  """

  use Gettext, backend: Firmowid.Gettext

  alias Firmowid.Analysis.IndustryTemplate

  @doc "Select options of the supported industries."
  @spec options() :: [{String.t(), IndustryTemplate.industry()}]
  def options, do: Enum.map(IndustryTemplate.industries(), &{label(&1), &1})

  @doc "Names the industry."
  @spec label(IndustryTemplate.industry()) :: String.t()
  def label(:services), do: gettext("Services")
  def label(:gastronomy), do: gettext("Food service")
  def label(:retail), do: gettext("Retail")
end
