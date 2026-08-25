defmodule FirmowidWeb.Timetracker.Components.DelegationsList do
  @moduledoc "Shared delegation list for employee profiles and management tabs."

  use FirmowidWeb, :html

  import FirmowidWeb.DesignSystem.Components.Button
  import FirmowidWeb.DesignSystem.Components.Link
  import Phoenix.Component, except: [link: 1]

  alias FirmowidWeb.Timetracker.Utilities.DelegationPresentation

  attr :delegations, :list, required: true
  attr :management?, :boolean, default: false

  @spec delegations_list(map()) :: Phoenix.LiveView.Rendered.t()
  def delegations_list(assigns) do
    ~H"""
    <ul :if={@delegations != []} class="divide-grey-100 divide-y">
      <li :for={delegation <- @delegations} class="flex items-center gap-3 py-3 first:pt-0 last:pb-0">
        <.link
          :if={delegation.status == :in_progress && !@management?}
          kind="unstyled"
          navigate={~p"/delegacje/#{delegation.id}"}
          class="min-w-0 flex-1 hover:underline"
        >
          {delegation.title}
          <span class="text-grey-500 ml-2 text-xs uppercase">WERSJA ROBOCZA</span>
        </.link>
        <span :if={delegation.status != :in_progress || @management?} class="min-w-0 flex-1 truncate">
          {delegation.title}
          <span :if={delegation.status == :in_progress} class="text-grey-500 ml-2 text-xs uppercase">WERSJA ROBOCZA</span>
        </span>
        <span class="shrink-0 text-sm tabular-nums">
          {DelegationPresentation.format_range(delegation.start_date, delegation.end_date)}
        </span>
        <span class={badge_styles(delegation.status)}>
          {DelegationPresentation.status_label(delegation.status)}
        </span>
        <.button
          :if={@management? && delegation.status == :pending}
          type="button"
          variant="primary"
          accent="turquoise"
          size="small"
          phx-click="approve_delegation"
          phx-value-id={delegation.id}
        >
          Zatwierdź
        </.button>
      </li>
    </ul>
    <p :if={@delegations == []} class="text-grey-500 text-sm">Brak delegacji.</p>
    """
  end

  defp badge_styles(status) do
    [
      "shrink-0 rounded-full px-3 py-1 text-center text-sm"
      | DelegationPresentation.status_badge_styles(status)
    ]
  end
end
