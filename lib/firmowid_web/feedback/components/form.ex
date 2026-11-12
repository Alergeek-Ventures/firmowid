defmodule FirmowidWeb.Feedback.Components.Form do
  @moduledoc """
  LiveComponent rendering the feedback modal. Sending captures the typed text as a
  PostHog survey response (see `Firmowid.Analytics.capture_feedback/4`) and shows
  the thank-you note; the text is not stored in the application.
  """
  use FirmowidWeb, :live_component

  import FirmowidUI.Components.Button
  import FirmowidWeb.DesignSystem.Components.CoreComponents
  import Phoenix.Component, except: [link: 1]

  alias Firmowid.Analytics

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign(:submitted, false)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <.modal id="feedback-modal" on_cancel={JS.push("reset", target: "##{@id}")}>
        <div :if={!@submitted}>
          <h2 class="mb-2 text-xl font-semibold">{gettext("Share your feedback")}</h2>
          <p class="mb-6 text-sm text-grey-700">
            {gettext(
              "Your opinion helps us develop Firmowid. Tell us what we can improve, what works well, or what you are missing."
            )}
          </p>
          <form id={"#{@id}-form"} phx-submit="save" phx-target={"##{@id}"} class="space-y-6">
            <div>
              <label for="feedback-content" class="mb-2 block text-sm font-medium">
                {gettext("What can we improve?")}
              </label>
              <textarea
                id="feedback-content"
                name="content"
                rows="5"
                required
                maxlength="5000"
                placeholder={gettext("Describe your idea or suggestion, or report a problem")}
                class="min-h-[120px] w-full resize-y rounded-md border border-grey-200 px-3 py-2 text-sm focus:border-rust-700 focus:ring-rust-700"
              ></textarea>
            </div>
            <div class="flex justify-end gap-3">
              <.button type="button" variant="outline" phx-click={hide_modal("feedback-modal")}>
                {gettext("Close")}
              </.button>
              <.button type="submit" variant="special">
                {gettext("Send")}
              </.button>
            </div>
          </form>
        </div>
        <div :if={@submitted} class="p-4 text-center">
          <div class="mb-4 text-3xl">&#127881;</div>
          <h2 class="mb-2 text-xl font-semibold">{gettext("Thank you for your feedback!")}</h2>
          <p class="mb-6 text-sm text-grey-700">
            {gettext("Your opinion is very important to us and will help us improve the application.")}
          </p>
          <.button
            type="button"
            variant="special"
            phx-click={
              JS.push("reset", target: "##{@id}")
              |> hide_modal("feedback-modal")
            }
          >
            {gettext("Close")}
          </.button>
        </div>
      </.modal>
    </div>
    """
  end

  @impl true
  def handle_event("save", %{"content" => content}, socket) do
    case String.trim(content) do
      "" ->
        {:noreply, socket}

      text ->
        %{current_user: user, current_uri: uri} = socket.assigns
        Analytics.capture_feedback(user, user.member.organization_id, uri.path, text)

        {:noreply, assign(socket, :submitted, true)}
    end
  end

  def handle_event("reset", _params, socket) do
    {:noreply, assign(socket, :submitted, false)}
  end
end
