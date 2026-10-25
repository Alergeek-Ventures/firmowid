defmodule FirmowidWeb.Payroll.Components.PayoutEstimates do
  @moduledoc "Shared labels and disclosure of indicative payouts in payroll and bank matching."
  use FirmowidWeb, :html

  alias Phoenix.LiveView.Rendered

  attr :estimates, :list, required: true
  attr :gross_amount, Money, required: true
  attr :subtitle, :string, default: nil

  @doc "Shows only the expected payout and its basis, with the calculation and assumptions in a modal."
  @spec summary(map()) :: Rendered.t()
  def summary(assigns) do
    primary = List.first(assigns.estimates)

    assigns =
      assigns
      |> assign(:primary, primary)
      |> assign(:basis_label, basis_label(primary))

    ~H"""
    <section id="payout-estimates" class="flex flex-col gap-2">
      <div class="flex items-center justify-between gap-2">
        <h3 class="text-sm/snug font-normal text-nowrap text-grey-700">{gettext("Net forecast")}</h3>
        <.icon_button
          :if={@primary}
          label={gettext("How is this calculated?")}
          phx-click={show_modal("payout-estimates-modal")}
        >
          <Lucideicons.info aria-hidden="true" />
        </.icon_button>
      </div>
      <p class="text-start text-xl/snug font-semibold text-teal-700 tabular-nums">
        {if @primary, do: @primary.amount, else: "—"}
      </p>
      <p :if={@basis_label} class="text-xs/snug text-grey-600">{@basis_label}</p>
      <%= if @primary do %>
        <.modal id="payout-estimates-modal" class="max-w-xl!">
          <div class="flex flex-col gap-6">
            <header class="flex flex-col gap-2">
              <h2 id="payout-estimates-modal-title" class="text-lg/snug font-medium">
                {gettext("How is this calculated?")}
              </h2>
              <p :if={@subtitle} class="text-sm/snug text-grey-700">{@subtitle}</p>
            </header>
            <dl class="grid grid-cols-[minmax(0,1fr)_auto] gap-x-4 gap-y-3 text-sm/snug tabular-nums">
              <dt class="text-grey-700">{gettext("Gross")}</dt>
              <dd class="text-end">{@gross_amount}</dd>
              <%= if @primary.variant != :b2b do %>
                <dt class="text-grey-700">{gettext("Social insurance")}</dt>
                <dd class="text-end">{deduction(@primary.social)}</dd>
                <dt class="text-grey-700">{gettext("Health insurance")}</dt>
                <dd class="text-end">{deduction(@primary.health)}</dd>
                <dt class="text-grey-700">{gettext("Income tax advance")}</dt>
                <dd class="text-end">{deduction(@primary.tax)}</dd>
              <% end %>
            </dl>
            <div class="flex items-center justify-between gap-4 border-bs border-grey-200 pbs-4">
              <span class="text-sm/snug">{gettext("Net forecast")}</span>
              <strong class="text-xl/snug font-medium text-teal-700 tabular-nums">
                {@primary.amount}
              </strong>
            </div>
            <p :if={@primary.basis == :profile} class="text-sm/snug text-grey-700">
              {variant_label(@primary.variant)}
            </p>
            <p :for={alternative <- Enum.drop(@estimates, 1)} class="text-sm/snug text-grey-700">
              {alternative_label(alternative)}
            </p>
            <p
              :if={@primary.basis == :hypothetical and @primary.variant != :b2b}
              class="text-sm/snug text-grey-700"
            >
              {gettext(
                "Confirm the net forecast assumptions in the employee profile to show one variant."
              )}
            </p>
            <p
              :if={@primary.youth_relief? and @primary.variant != :uz_student}
              class="text-xs/snug text-grey-600"
            >
              {gettext("Youth tax relief")}
            </p>
            <p id="payout-estimates-modal-description" class="text-xs/snug text-grey-600">
              {assumptions(@primary)}
              {if @primary.variant == :uop,
                do:
                  gettext(
                    "Health insurance is capped under the 2021 rules, approximated from the current PIT-2 reduction, which may affect small salaries."
                  )}
              {gettext(
                "Forecast based on available data and assumptions. It does not replace payroll calculation and is not financial or tax advice."
              )}
            </p>
          </div>
        </.modal>
      <% end %>
    </section>
    """
  end

  @doc "Describes a saved or hypothetical variant, never an inferred insurance or tax status."
  @spec variant_label(atom()) :: String.t()
  def variant_label(:uop), do: gettext("Employment contract")
  def variant_label(:uz_social), do: gettext("Mandate — social and health insurance")

  def variant_label(:uz_social_with_sickness), do: gettext("Mandate — social, sickness and health insurance")

  def variant_label(:uz_health), do: gettext("Mandate — health insurance only")
  def variant_label(:uz_student), do: gettext("Mandate — student under 26")
  def variant_label(:uod_20), do: gettext("Specific-task contract — 20% costs")
  def variant_label(:uod_50), do: gettext("Specific-task contract — 50% costs")
  def variant_label(:b2b), do: gettext("B2B — gross amount")

  @doc "Returns a compact contract label for payroll lists."
  @spec contract_label(atom()) :: String.t()
  def contract_label(:uop), do: gettext("Employment")

  def contract_label(type) when type in [:uz_social, :uz_social_with_sickness, :uz_health, :uz_student],
    do: gettext("Mandate")

  def contract_label(type) when type in [:uod_20, :uod_50], do: gettext("Specific-task")
  def contract_label(:b2b), do: "B2B"

  defp deduction(amount), do: if(Money.zero?(amount), do: amount, else: Money.negate!(amount))

  defp alternative_label(%{variant: :uz_social, amount: amount}),
    do: gettext("With social insurance contributions: %{amount}.", amount: to_string(amount))

  defp alternative_label(%{variant: :uz_health, amount: amount}),
    do: gettext("With health insurance only: %{amount}.", amount: to_string(amount))

  defp alternative_label(%{variant: :uod_50, amount: amount}),
    do: gettext("If 50% tax-deductible costs apply: %{amount}.", amount: to_string(amount))

  defp basis_label(%{basis: :profile}), do: gettext("Based on saved assumptions")
  defp basis_label(%{variant: :b2b}), do: nil
  defp basis_label(%{basis: :hypothetical}), do: gettext("Hypothetical variant")
  defp basis_label(nil), do: nil

  defp assumptions(%{basis: :profile}),
    do:
      gettext(
        "Based on the saved assumptions, which are not verified: first income tax bracket, no PPK and unused annual limits."
      )

  # Hypothetical estimates always lead with one of these variants.
  defp assumptions(%{variant: :uz_student}), do: gettext("Student status is assumed from age, with unused youth relief.")

  defp assumptions(%{variant: :uz_health}),
    do: gettext("Health insurance only, first income tax bracket, no PIT-2 reduction.")

  defp assumptions(%{variant: :uop}),
    do: gettext("First income tax bracket, standard costs, PLN 300 PIT-2 reduction, no PPK.")

  defp assumptions(%{variant: :uod_20}),
    do: gettext("First income tax bracket, 20% tax-deductible costs, no PIT-2 reduction.")

  defp assumptions(%{variant: :b2b}), do: gettext("Gross amount under the contract.")
end
