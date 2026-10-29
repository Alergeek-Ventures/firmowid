defmodule FirmowidWeb.Delegations.Components.DelegationsList do
  @moduledoc "Shared delegation list for employee profiles and management tabs."

  use FirmowidWeb, :html

  import FirmowidUI.Components.Button
  import FirmowidUI.Components.Link
  import FirmowidWeb.Delegations.Components.Delegation
  import Phoenix.Component, except: [link: 1]

  attr :delegations, :list, required: true
  attr :management?, :boolean, default: false

  @spec delegations_list(map()) :: Phoenix.LiveView.Rendered.t()
  def delegations_list(assigns) do
    ~H"""
    <ul :if={@delegations != []} class="divide-y divide-grey-100">
      <li :for={delegation <- @delegations} class="flex items-center gap-3 py-3 first:pt-0 last:pb-0">
        <.delegation_title
          delegation={delegation}
          is_link={
            delegation.status == :complete || (delegation.status == :in_progress && !@management?)
          }
        />
        <p class="shrink-0 text-sm tabular-nums">
          <.date_range start_date={delegation.start_date} end_date={delegation.end_date} />
        </p>
        <.status_badge status={delegation.status} />
        <.button
          :if={@management? && delegation.status == :pending}
          type="button"
          variant="primary"
          accent="teal"
          size="small"
          phx-click="approve_delegation"
          phx-value-id={delegation.id}
        >
          Zatwierdź
        </.button>
      </li>
    </ul>
    <p :if={@delegations == []} class="text-sm text-grey-500">Brak delegacji.</p>
    """
  end

  attr :delegation, :map, required: true
  attr :is_link, :boolean, required: true

  defp delegation_title(assigns) do
    ~H"""
    <div class="flex min-w-0 flex-1 items-center gap-2">
      <.link
        :if={@is_link}
        kind="unstyled"
        navigate={FirmowidWeb.Delegations.Utilities.Navigation.show_path(@delegation.reference)}
        class="truncate hover:underline"
      >
        <span class="truncate">{@delegation.title}</span>
      </.link>
      <p :if={!@is_link} class="truncate">
        <span class="truncate">{@delegation.title}</span>
      </p>
      <span :if={@delegation.status == :in_progress} class="ml-2 text-xs text-grey-500 uppercase">
        Wersja robocza
      </span>
    </div>
    """
  end
end
