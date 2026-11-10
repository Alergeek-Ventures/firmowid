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

  @doc "Says how Analysis reads the finances of the industry, from its income channels and key costs."
  @spec description(IndustryTemplate.industry()) :: String.t()
  def description(:services), do: gettext("Analysis watches the cost of people, subcontractors and software.")

  def description(:gastronomy),
    do: gettext("Analysis splits income into the venue, delivery and catering, and watches the cost of food.")

  def description(:retail),
    do: gettext("Analysis splits income into the store and online sales, and watches the cost of goods.")
end
