defmodule FirmowidWeb.Components.Timetracker.AddCoworkerModal do
  @moduledoc false
  use FirmowidWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.modal id="add_coworker_modal" on_cancel={hide_modal("add_coworker_modal")}>
        <div class="flex flex-col gap-4">
          <h3 class="text-lg font-semibold">
            Dodaj współpracownika do projektu {@selected_project.name}
          </h3>
          <form :if={@selected_project} class="relative w-[100%] animate-appear" phx-submit="add_user">
            <.input
              type="select"
              name="user_id"
              id="user"
              prompt="Dodaj współpracownika"
              value={nil}
              options={Enum.map(@users, &{&1.name || &1.email, &1.id})}
            />
            <div class="flex flex-row gap-12 justify-center mt-4">
              <.button
                color="light_grey"
                size="small"
                type="button"
                phx-click={hide_modal("add_coworker_modal")}
              >
                Anuluj
              </.button>
              <.button
                color="light_orange"
                size="small"
                type="submit"
                phx-click={hide_modal("add_coworker_modal")}
              >
                Dodaj
              </.button>
            </div>
          </form>
        </div>
      </.modal>
    </div>
    """
  end
end
