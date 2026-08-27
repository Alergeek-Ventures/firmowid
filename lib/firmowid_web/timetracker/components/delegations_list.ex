defmodule FirmowidWeb.Timetracker.Components.DelegationsList do
  @moduledoc "Shared delegation list for employee profiles and management tabs."

  use FirmowidWeb, :html

  import FirmowidWeb.DesignSystem.Components.Button
  import FirmowidWeb.DesignSystem.Components.Link
  import FirmowidWeb.Timetracker.Components.Delegation
  import Phoenix.Component, except: [link: 1]

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
          <.delegation_title delegation={delegation} />
        </.link>
        <p :if={delegation.status != :in_progress || @management?} class="min-w-0 flex-1 truncate">
          <.delegation_title delegation={delegation} />
        </p>
        <p class="shrink-0 text-sm tabular-nums">
          <.date_range start_date={delegation.start_date} end_date={delegation.end_date} />
        </p>
        <.status_badge status={delegation.status} />
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

  attr :delegation, :map, required: true

  defp delegation_title(assigns) do
    ~H"""
    <span class="truncate">{@delegation.title}</span>
    <span :if={@delegation.status == :in_progress} class="text-grey-500 ml-2 text-xs uppercase">
      Wersja robocza
    </span>
    """
  end
end
