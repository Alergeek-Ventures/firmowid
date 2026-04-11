defmodule FirmowidWeb.Feedback.Components.Form do
  @moduledoc """
  LiveComponent rendering a feedback modal.

  Captures user feedback and stores local UI state. Analytics submission
  is handled by frontend telemetry hooks.
  """
  use FirmowidWeb, :live_component

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign(:content, "")
      |> assign(:submitted, false)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <.modal id="feedback-modal" on_cancel={JS.push("reset", target: "##{@id}")}>
        <div :if={!@submitted}>
          <h2 class="mb-2 text-xl font-semibold">Podziel się swoim feedbackiem</h2>
          <p class="text-darkGrey mb-6 text-sm">
            Twoja opinia pomaga nam rozwijać Firmowida. Napisz co możemy poprawić,
            co działa dobrze, albo czego Ci brakuje.
          </p>
          <form phx-submit="save" phx-target={"##{@id}"} class="space-y-6">
            <div>
              <label for="feedback-content" class="mb-2 block text-sm font-medium">
                Co możemy poprawić?
              </label>
              <textarea
                id="feedback-content"
                name="content"
                rows="5"
                required
                placeholder="Opisz swój pomysł, sugestię lub zgłoś problem"
                class="border-grey/30 focus:border-orangeText focus:ring-orangeText min-h-[120px] w-full resize-y rounded-md border px-3 py-2 text-sm"
              ><%= @content %></textarea>
            </div>
            <div class="flex justify-end gap-3">
              <.button
                type="button"
                color="grey"
                variant="outline"
                phx-click={hide_modal("feedback-modal")}
              >
                Zamknij
              </.button>
              <.button type="submit" color="black">
                Wyślij
              </.button>
            </div>
          </form>
        </div>
        <div :if={@submitted} class="p-4 text-center">
          <div class="mb-4 text-4xl">&#127881;</div>
          <h2 class="mb-2 text-xl font-semibold">Dziękujemy za feedback!</h2>
          <p class="text-darkGrey mb-6 text-sm">
            Twoja opinia jest dla nas bardzo ważna i pomoże nam ulepszyć
            aplikację.
          </p>
          <.button
            type="button"
            color="black"
            phx-click={
              JS.push("reset", target: "##{@id}")
              |> hide_modal("feedback-modal")
            }
          >
            Zamknij
          </.button>
        </div>
      </.modal>
    </div>
    """
  end

  @impl true
  def handle_event("save", %{"content" => content}, socket) when content != "" do
    {:noreply, assign(socket, :submitted, true)}
  end

  def handle_event("save", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("reset", _params, socket) do
    {:noreply, assign(socket, content: "", submitted: false)}
  end
end
