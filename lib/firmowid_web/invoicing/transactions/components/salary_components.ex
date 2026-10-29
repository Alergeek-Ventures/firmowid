defmodule FirmowidWeb.Invoicing.Transactions.Components.SalaryComponents do
  @moduledoc "Salary proposals and compact salary confirmation for bank transactions."

  use FirmowidWeb, :html

  import FirmowidUI.Components.Button
  import FirmowidUI.Components.Link
  import FirmowidWeb.Invoicing.Components.StatusButton
  import Phoenix.Component, except: [link: 1]

  alias Firmowid.Core.User
  alias Firmowid.Finances.Transaction
  alias FirmowidWeb.Invoicing.Components.MatchingComponents
  alias FirmowidWeb.Management.Utilities.Navigation
  alias FirmowidWeb.Payroll.Components.PayoutEstimates
  alias Phoenix.LiveView.Rendered

  attr :suggestions, :list, required: true

  @doc "Renders salary candidates with an explicit manual confirmation action."
  @spec suggestions(map()) :: Rendered.t()
  def suggestions(assigns) do
    ~H"""
    <section :if={@suggestions != []} id="salary-suggestions">
      <MatchingComponents.candidates
        title={gettext("Potential salaries for this transaction")}
        date_label={gettext("Month")}
        amount_label={gettext("Amount")}
      >
        <:candidate
          :for={{suggestion, index} <- Enum.with_index(@suggestions)}
          id={"salary-suggestion-#{suggestion.user_id}-#{suggestion.month}"}
          name={suggestion.name}
          description={
            Enum.join(
              [
                if(suggestion.payout_variant,
                  do:
                    gettext("Example: %{variant}",
                      variant: PayoutEstimates.variant_label(suggestion.payout_variant)
                    )
                ),
                gettext("Difference from transfer: %{amount}",
                  amount: to_string(suggestion.difference)
                )
              ]
              |> Enum.reject(&is_nil/1),
              " · "
            )
          }
          date={month_label(suggestion.month)}
          amount={suggestion.expected_amount}
        >
          <MatchingComponents.score_indicator
            id={"salary-amount-match-#{suggestion.user_id}-#{suggestion.month}"}
            level={if Money.zero?(suggestion.difference), do: :high, else: :mid}
            tooltip={
              gettext("Difference from transfer: %{amount}", amount: to_string(suggestion.difference))
            }
          />
          <.button
            type="button"
            phx-click="connect_salary"
            phx-value-user_id={suggestion.user_id}
            phx-value-month={Date.to_iso8601(suggestion.month)}
            variant={if index == 0, do: "tertiary", else: "secondary"}
            size="small"
          >
            {gettext("Confirm")}
          </.button>
        </:candidate>
      </MatchingComponents.candidates>
    </section>
    """
  end

  attr :transaction, Transaction, required: true
  attr :expected_amount, Money, default: nil
  attr :payout_variant, :atom, default: nil
  attr :admin?, :boolean, required: true

  @doc "Renders the salary assignment, with expected pay and payroll controls restricted to administrators."
  @spec confirmation(map()) :: Rendered.t()
  def confirmation(assigns) do
    ~H"""
    <section id="salary-confirmation" class="flex flex-col gap-8">
      <MatchingComponents.confirmed_header>
        <:action :if={@admin?}>
          <.status_button
            id="disconnect-salary"
            phx-click="disconnect_salary"
            icon="hero-arrow-uturn-left-micro"
            title={gettext("Disconnect salary")}
            aria-label={gettext("Disconnect salary")}
          />
        </:action>
      </MatchingComponents.confirmed_header>
      <MatchingComponents.confirmed_card
        amount={Money.abs(@transaction.signed_amount)}
        amount_label={gettext("Transferred amount")}
      >
        <:detail :if={is_struct(@transaction.salary_user, User)} label={gettext("Employee")}>
          {@transaction.salary_user.member.name || to_string(@transaction.salary_user.email)}
        </:detail>
        <:detail label={gettext("Salary month")}>{month_label(@transaction.salary_month)}</:detail>
        <:detail
          :if={@admin?}
          label={if @payout_variant, do: gettext("Estimated take-home pay"), else: gettext("Gross")}
        >
          <div class="flex flex-col gap-1">
            <span><span :if={@payout_variant && @payout_variant != :b2b} aria-hidden="true">≈ </span>{@expected_amount ||
              gettext("Unavailable")}</span>
            <span :if={@payout_variant} class="text-sm/snug text-grey-700">
              {PayoutEstimates.variant_label(@payout_variant)}
            </span>
            <span :if={@payout_variant && @payout_variant != :b2b} class="text-xs/snug text-grey-600">
              {gettext(
                "Estimate only — excludes employee declarations and earlier payments this year."
              )}
            </span>
          </div>
        </:detail>
      </MatchingComponents.confirmed_card>
      <.link
        :if={@admin?}
        kind="text"
        class="self-end"
        navigate={
          Navigation.employee_path(@transaction.salary_user_id, %{
            miesiac: @transaction.salary_month
          })
        }
      >
        {gettext("View timesheet")}
        <.icon name="hero-arrow-right-solid" class="size-4" />
      </.link>
    </section>
    """
  end

  defp month_label(month) do
    Firmowid.Cldr.Date.to_string!(month,
      format: "LLLL y",
      locale: "pl"
    )
  end
end
