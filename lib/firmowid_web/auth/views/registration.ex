defmodule FirmowidWeb.Auth.Views.Registration do
  @moduledoc false
  use FirmowidWeb, :live_view

  import FirmowidWeb.DesignSystem.Components.Button
  import FirmowidWeb.DesignSystem.Components.CoreComponents, except: [button: 1]
  import FirmowidWeb.DesignSystem.Components.Link
  import Phoenix.Component, except: [link: 1]

  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Core.User

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-sm">
      <.header class="text-center">
        Zarejestruj się
        <:subtitle>
          Masz już konto?
          <.link
            kind="unstyled"
            navigate={~p"/zaloguj"}
            class="text-brand font-semibold hover:underline"
          >
            Zaloguj się
          </.link>
        </:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="registration_form"
        phx-submit="save"
        phx-change="validate"
        phx-trigger-action={@trigger_submit}
        action={~p"/auth/user/password/register"}
        method="post"
      >
        <.error :if={@check_errors and not @form.source.valid?}>
          Coś poszło nie tak...
        </.error>

        <.input field={@form[:email]} type="email" label="Email" required />
        <.input field={@form[:password]} type="password" label="Hasło" required />

        <:actions>
          <.button variant="special" phx-disable-with="Tworzenie konta..." class="w-full">
            Stwórz konto
          </.button>
        </:actions>
      </.simple_form>

      <div class="relative my-6">
        <div class="absolute inset-0 flex items-center">
          <div class="w-full border-t border-gray-300"></div>
        </div>
        <div class="relative flex justify-center text-sm">
          <span class="bg-white px-2 text-gray-500">lub</span>
        </div>
      </div>

      <%!-- TODO: Extract Google SVG icon into a shared auth component (duplicated in login.ex) --%>
      <.link
        redirect={~p"/auth/user/google"}
        kind="button"
        variant="outline"
        class="w-full gap-3 border-gray-300 bg-white text-sm font-medium text-gray-700 shadow-sm hover:bg-gray-50"
      >
        <svg class="size-5" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
          <path
            d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"
            fill="#4285F4"
          />
          <path
            d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"
            fill="#34A853"
          />
          <path
            d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"
            fill="#FBBC05"
          />
          <path
            d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"
            fill="#EA4335"
          />
        </svg>
        Zarejestruj się przez Google
      </.link>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    form =
      User
      |> AshPhoenix.Form.for_create(:register_with_password,
        domain: Core,
        as: "user"
      )
      |> to_form()

    socket =
      socket
      |> assign(trigger_submit: false)
      |> assign(:check_errors, false)
      |> assign(:form, form)

    {:ok, socket}
  end

  def handle_event("save", %{"user" => user_params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.form, user_params)

    {:noreply,
     socket
     |> assign(:form, form)
     |> assign(:check_errors, not form.source.valid?)
     |> assign(:trigger_submit, form.source.valid?)}
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.form, user_params)

    socket =
      socket
      |> assign(:form, form)
      |> assign(:check_errors, false)
      |> assign(:trigger_submit, false)

    {:noreply, socket}
  end
end
