defmodule FirmowidWeb.Support.Components.Form do
  @moduledoc """
  Support form that creates tickets through the PostHog Support JavaScript API.
  """
  use FirmowidWeb, :live_component

  import FirmowidUI.Components.Button
  import FirmowidUI.Components.Inputs
  import FirmowidWeb.DesignSystem.Components.Alert, only: [alert: 1]
  import FirmowidWeb.DesignSystem.Components.CoreComponents
  import Phoenix.Component, except: [link: 1]

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:form, &empty_form/0)
     |> assign_new(:loading, fn -> false end)
     |> assign_new(:status, fn -> nil end)}
  end

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <.modal id="support-modal" on_cancel={hide_modal("support-modal")}>
        <:header>
          <h2 class="mb-2 text-xl font-semibold">{gettext("Send us a message")}</h2>
          <p class="text-sm text-grey-700">
            {gettext("Found a bug or have an idea? Share it with us — we read every message.")}
          </p>
        </:header>
        <.alert :if={@status == :sent} tone="success" class="mbe-6">
          {gettext("Support request sent")}
        </.alert>
        <.alert :if={@status == :error} tone="danger" class="mbe-6">
          {gettext("Could not send your request. Please try again.")}
        </.alert>
        <.form
          for={@form}
          id={"#{@id}-form"}
          phx-change="support_validate"
          phx-submit="support_submit"
          phx-hook="SupportForm"
          phx-target={@myself}
          class="space-y-6"
        >
          <.input
            type="textarea"
            field={@form[:message]}
            label={gettext("Your message")}
            placeholder={gettext("What happened, or what would make Firmowid more useful for you?")}
            rows={5}
            readonly={@loading}
            required
          />
          <div class="flex justify-end gap-3">
            <.button type="button" variant="outline" phx-click={hide_modal("support-modal")}>
              {gettext("Cancel")}
            </.button>
            <.button type="submit" variant="special" disabled={@loading || !@form.source.valid?}>
              {gettext("Send")}
            </.button>
          </div>
        </.form>
      </.modal>
    </div>
    """
  end

  @impl Phoenix.LiveComponent
  def handle_event("support_validate", %{"support" => params}, socket) do
    {:noreply, assign(socket, form: build_form(params), status: nil)}
  end

  def handle_event("support_submit", %{"support" => %{"message" => message}}, socket) do
    {:noreply,
     socket
     |> assign(form: build_form(%{"message" => message}), loading: true, status: nil)
     |> push_event("support:submit", %{message: message, email: socket.assigns.current_user.email})}
  end

  def handle_event("support_ticket_sent", _params, socket) do
    {:noreply, assign(socket, form: empty_form(), loading: false, status: :sent)}
  end

  def handle_event("support_ticket_failed", %{"reason" => reason}, socket) do
    require Logger

    Logger.warning("PostHog Support ticket creation failed: #{reason}")

    {:noreply, assign(socket, loading: false, status: :error)}
  end

  defp empty_form do
    build_form()
  end

  defp build_form(params \\ %{}) do
    {%{}, %{message: :string}}
    |> Ecto.Changeset.cast(params, [:message])
    |> Ecto.Changeset.validate_required(:message)
    |> Phoenix.Component.to_form(as: :support)
  end
end
