defmodule FirmowidWeb.Invoicing.Transactions.Components.DelegationComponents do
  @moduledoc "Business trip proposals and the confirmed business trip of a bank transaction."

  use FirmowidWeb, :html

  import FirmowidUI.Components.Button
  import FirmowidUI.Components.Link
  import FirmowidWeb.Invoicing.Components.StatusButton
  import Phoenix.Component, except: [link: 1]

  alias Firmowid.Delegations.Delegation
  alias Firmowid.Finances.Transaction
  alias Firmowid.TimeFormatter
  alias FirmowidWeb.Invoicing.Components.MatchingComponents
  alias FirmowidWeb.Management.Utilities.Navigation
  alias Phoenix.LiveView.Rendered

  attr :suggestions, :list, required: true

  @doc "Renders business trip candidates with an explicit manual confirmation action."
  @spec suggestions(map()) :: Rendered.t()
  def suggestions(assigns) do
    ~H"""
    <section :if={@suggestions != []} id="delegation-suggestions">
      <MatchingComponents.candidates
        title={gettext("Potential business trips for this transaction")}
        date_label={pgettext("business trips table", "Dates")}
        amount_label={gettext("Amount")}
      >
        <:candidate
          :for={{suggestion, index} <- Enum.with_index(@suggestions)}
          id={"delegation-suggestion-#{suggestion.delegation_id}"}
          name={suggestion.name}
          navigate={Navigation.employee_delegation_path(suggestion.user_id, suggestion.reference)}
          description={description(suggestion)}
          date={TimeFormatter.format_date_range(suggestion.start_date, suggestion.end_date)}
          amount={suggestion.expected_amount || "—"}
        >
          <MatchingComponents.score_indicator
            id={"delegation-match-#{suggestion.delegation_id}"}
            level={suggestion.confidence}
            tooltip={match_tooltip(suggestion)}
          />
          <.button
            type="button"
            phx-click="connect_delegation"
            phx-value-delegation_id={suggestion.delegation_id}
            variant={
              if index == 0 and suggestion.confidence == :high, do: "secondary", else: "tertiary"
            }
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
  attr :admin?, :boolean, required: true

  @doc "Renders the business trip a transaction belongs to, with the unlink action for administrators."
  @spec confirmation(map()) :: Rendered.t()
  def confirmation(assigns) do
    ~H"""
    <section id="delegation-confirmation" class="flex flex-col gap-8">
      <MatchingComponents.confirmed_header>
        <:action :if={@admin?}>
          <.status_button
            id="disconnect-delegation"
            phx-click="disconnect_delegation"
            icon="hero-arrow-uturn-left-micro"
            title={gettext("Unlink business trip")}
            aria-label={gettext("Unlink business trip")}
          />
        </:action>
      </MatchingComponents.confirmed_header>
      <MatchingComponents.confirmed_card
        amount={Money.abs(@transaction.signed_amount)}
        amount_label={gettext("Transferred amount")}
      >
        <:detail label={pgettext("business trips table", "Business trip")}>
          <%!-- Only administrators and the traveling employee may read the trip itself. --%>
          <span :if={is_nil(@transaction.delegation)}>—</span>
          <.link
            :if={@transaction.delegation && @admin?}
            kind="unstyled"
            class="leading-snug hover:underline"
            navigate={
              Navigation.employee_delegation_path(
                @transaction.delegation.member.user_id,
                @transaction.delegation.reference
              )
            }
          >
            {@transaction.delegation.reference}
          </.link>
          <span :if={@transaction.delegation && !@admin?}>{@transaction.delegation.reference}</span>
        </:detail>
        <:detail :if={@transaction.delegation} label={gettext("Employee")}>
          {employee_name(@transaction.delegation)}
        </:detail>
        <:detail :if={@transaction.delegation} label={gettext("Title")}>
          {@transaction.delegation.title}
        </:detail>
        <:detail :if={@transaction.delegation} label={pgettext("business trips table", "Dates")}>
          {TimeFormatter.format_date_range(
            @transaction.delegation.start_date,
            @transaction.delegation.end_date
          )}
        </:detail>
      </MatchingComponents.confirmed_card>
    </section>
    """
  end

  defp description(suggestion) do
    [kind_label(suggestion.kind), suggestion.title, suggestion.reference]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp kind_label(:advance), do: gettext("Advance")
  defp kind_label(:settlement), do: gettext("Settlement payout")
  defp kind_label(:return), do: gettext("Returned advance")
  defp kind_label(nil), do: nil

  defp match_tooltip(suggestion) do
    [
      if(suggestion.reference_named?, do: gettext("The transfer title names this business trip")),
      if(suggestion.difference,
        do: gettext("Difference from transfer: %{amount}", amount: to_string(suggestion.difference))
      )
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp employee_name(%Delegation{member: member}), do: member.name || to_string(member.user.email)
end
