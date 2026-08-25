defmodule FirmowidWeb.Timetracker.Views.Delegation do
  @moduledoc "Overview of an employee's delegation draft."

  use FirmowidWeb, :live_view

  import FirmowidWeb.DesignSystem.Components.Link
  import Phoenix.Component, except: [link: 1]

  alias Firmowid.Ash.Timetracker
  alias FirmowidWeb.Timetracker.Utilities.DelegationPresentation

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Timetracker.get_delegation(id, scope: socket.assigns.ash_scope, not_found_error?: false) do
      {:ok, nil} ->
        {:ok, push_navigate(socket, to: ~p"/ustawienia/konto")}

      {:ok, delegation} ->
        {:ok, assign(socket, delegation: delegation, page_title: delegation.title)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main class="mx-auto max-w-3xl space-y-6 px-6 py-10">
      <.link kind="unstyled" navigate={~p"/ustawienia/konto"}>Wróć</.link>
      <h1 class="text-2xl font-medium">{@delegation.title}</h1>
      <p>{@delegation.purpose}</p>
      <p>{DelegationPresentation.format_range(@delegation.start_date, @delegation.end_date)}</p>
      <span class="rounded-full px-3 py-1 text-sm">{DelegationPresentation.status_label(
        @delegation.status
      )}</span>
    </main>
    """
  end
end
