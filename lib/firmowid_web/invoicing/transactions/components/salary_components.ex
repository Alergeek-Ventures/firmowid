defmodule FirmowidWeb.Invoicing.Transactions.Components.SalaryComponents do
  @moduledoc "Salary proposals and compact salary confirmation for bank transactions."

  use FirmowidWeb, :html

  import FirmowidWeb.DesignSystem.Components.Button
  import FirmowidWeb.DesignSystem.Components.Link
  import FirmowidWeb.Invoicing.Components.StatusButton
  import Phoenix.Component, except: [link: 1]

  alias Firmowid.Ash.Finances.Transaction
  alias FirmowidWeb.Invoicing.Components.MatchingComponents
  alias FirmowidWeb.Management.Utilities.Navigation
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
            gettext("Difference from transfer: %{amount}", amount: to_string(suggestion.difference))
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
  attr :summary, :map, default: nil
  attr :admin?, :boolean, required: true

  @doc "Renders payroll details only for administrators, otherwise a generic confirmation."
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
      <%= if @admin? do %>
        <MatchingComponents.confirmed_card
          amount={Money.abs(@transaction.signed_amount)}
          amount_label={gettext("Transferred amount")}
        >
          <:detail label={gettext("Employee")}>
            {if @summary, do: @summary.name, else: @transaction.salary_user.name}
          </:detail>
          <:detail label={gettext("Salary month")}>{month_label(@transaction.salary_month)}</:detail>
          <:detail label={gettext("Expected salary")}>
            {if @summary, do: @summary.expected_amount, else: gettext("Unavailable")}
          </:detail>
        </MatchingComponents.confirmed_card>
        <.link
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
      <% else %>
        <p>{gettext("Connected to salary")}</p>
      <% end %>
    </section>
    """
  end

  defp month_label(month) do
    Firmowid.Cldr.Date.to_string!(month,
      format: "LLLL y",
      locale: Gettext.get_locale(FirmowidWeb.Core.Gettext)
    )
  end
end
