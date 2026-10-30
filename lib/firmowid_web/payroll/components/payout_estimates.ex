defmodule FirmowidWeb.Payroll.Components.PayoutEstimates do
  @moduledoc "Shared payout labels used in payroll and bank matching."
  use FirmowidWeb, :html

  @doc "Describes a saved or hypothetical variant, never an inferred insurance or tax status."
  @spec variant_label(atom()) :: String.t()
  def variant_label(:uop), do: gettext("Employment contract")
  def variant_label(:uz_social), do: gettext("Mandate — social and health insurance")

  def variant_label(:uz_social_with_sickness), do: gettext("Mandate — social, sickness and health insurance")

  def variant_label(:uz_health), do: gettext("Mandate — health insurance only")
  def variant_label(:uz_student), do: gettext("Mandate — student under 26")
  def variant_label(:uod_20), do: gettext("Contract for specific work — 20% costs")
  def variant_label(:uod_50), do: gettext("Contract for specific work — 50% costs")
  def variant_label(:b2b), do: gettext("B2B — gross amount")

  @doc "Returns a compact contract label for payroll lists."
  @spec contract_label(atom()) :: String.t()
  def contract_label(:uop), do: gettext("Employment")

  def contract_label(type) when type in [:uz_social, :uz_social_with_sickness, :uz_health, :uz_student],
    do: gettext("Mandate")

  def contract_label(type) when type in [:uod_20, :uod_50], do: gettext("Specific work")
  def contract_label(:b2b), do: "B2B"
end
