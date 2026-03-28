defmodule FirmowidWeb.FeedbackLive.FormComponent do
  @moduledoc """
  LiveComponent rendering a feedback modal.

  Captures user feedback and submits it as a PostHog survey response.
  Designed to be embedded in the app layout so it's available from every
  authenticated view.

  ## PostHog integration

  Feedback is submitted as a `"survey sent"` event to PostHog using the
  Capture API. The survey must be created in PostHog dashboard with "API"
  presentation mode. Update `@survey_id` and `@question_id` after creating
  the survey.
  """
  use FirmowidWeb, :live_component

  alias Firmowid.Analytics

  # PostHog survey configuration.
  # Create an API-type survey in PostHog dashboard and paste the IDs here.
  # See: https://posthog.com/docs/surveys/implementing-custom-surveys
  @survey_id "019d3547-2ac9-0000-3af2-d6fbe2319c0b"
  @question_id "bc5052e4-721e-4a98-8321-7bc2d04590bd"
  @survey_name "Feedback w aplikacji"
  @question_text "Jak możemy usprawnić Firmowida?"

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
          <h2 class="text-xl font-semibold mb-2">Podziel się swoim feedbackiem</h2>
          <p class="text-sm text-darkGrey mb-6">
            Twoja opinia pomaga nam rozwijać Firmowida. Napisz co możemy poprawić,
            co działa dobrze, albo czego Ci brakuje.
          </p>
          <form phx-submit="save" phx-target={"##{@id}"} class="space-y-6">
            <div>
              <label for="feedback-content" class="block text-sm font-medium mb-2">
                Co możemy poprawić?
              </label>
              <textarea
                id="feedback-content"
                name="content"
                rows="5"
                required
                placeholder="Opisz swój pomysł, sugestię lub zgłoś problem"
                class="w-full rounded-md border border-grey/30 px-3 py-2 text-sm
                  focus:border-orangeText focus:ring-orangeText resize-y min-h-[120px]"
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
        <div :if={@submitted} class="text-center p-4">
          <div class="text-4xl mb-4">&#127881;</div>
          <h2 class="text-xl font-semibold mb-2">Dziękujemy za feedback!</h2>
          <p class="text-sm text-darkGrey mb-6">
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
    user = socket.assigns.current_user
    page_path = socket.assigns.current_uri.path

    Analytics.track_event("survey sent", user, %{
      "$survey_id" => @survey_id,
      "$survey_name" => @survey_name,
      "$survey_response_#{@question_id}" => content,
      "$survey_questions" => [
        %{"id" => @question_id, "question" => @question_text}
      ],
      "page_path" => page_path
    })

    {:noreply, assign(socket, :submitted, true)}
  end

  def handle_event("save", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("reset", _params, socket) do
    {:noreply, assign(socket, content: "", submitted: false)}
  end
end
