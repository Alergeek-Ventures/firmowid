defmodule FirmowidWeb.Timetracker.Views.Delegation do
  @moduledoc "Overview of an employee's delegation draft."

  use FirmowidWeb, :live_view

  import FirmowidWeb.Timetracker.Components.Delegation

  alias Firmowid.Ash.Timetracker

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Timetracker.get_delegation(id, scope: socket.assigns.ash_scope, not_found_error?: false) do
      {:ok, nil} ->
        {:ok, push_navigate(socket, to: ~p"/ustawienia/profil")}

      {:ok, delegation} ->
        {:ok, assign(socket, delegation: delegation, page_title: delegation.title)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main class="mx-auto max-w-3xl space-y-10 px-6 py-10">
      <.back_link navigate={~p"/ustawienia/profil"} />
      <article class="rounded-lg bg-white p-6 shadow">
        <header class="flex flex-wrap items-start justify-between gap-4">
          <div class="space-y-2">
            <h1 class="text-2xl/tight font-normal">{@delegation.title}</h1>
            <p class="text-grey-700">{@delegation.purpose}</p>
          </div>
          <.status_badge status={@delegation.status} />
        </header>
        <dl class="border-grey-100 mt-8 border-t pt-6">
          <div class="grid gap-1 sm:grid-cols-2 sm:gap-4">
            <.detail_row label="Termin wyjazdu">
              <span class="tabular-nums">
                <.date_range start_date={@delegation.start_date} end_date={@delegation.end_date} />
              </span>
            </.detail_row>
          </div>
        </dl>
      </article>
    </main>
    """
  end
end
