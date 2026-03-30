defmodule FirmowidWeb.Auth.Views.Login do
  @moduledoc false
  use FirmowidWeb, :live_view

  def render(assigns) do
    ~H"""
    <div class="relative flex h-screen w-screen items-center justify-center overflow-clip">
      <img src="/images/figurine.png" class="absolute -top-20 left-1/2 h-[135vh] opacity-10" />
      <div class="z-10 max-w-sm">
        <h1 class="text-center text-2xl font-bold">
          Wejdź do Firmowida
        </h1>

        <.simple_form for={@form} id="login_form" action={~p"/zaloguj"} phx-update="ignore">
          <.input field={@form[:email]} type="email" label="Email" required />
          <.input field={@form[:password]} type="password" label="Hasło" required />

          <:actions>
            <.input field={@form[:remember_me]} type="checkbox" label="Zapamiętaj mnie" />
            <.link href={~p"/resetuj-haslo"} class="text-sm font-semibold">
              Zapomniałeś hasła?
            </.link>
          </:actions>
          <:actions>
            <.button phx-disable-with="Logowanie..." class="w-full px-4 py-2">
              Zaloguj się
            </.button>
          </:actions>
        </.simple_form>

        <p class="mt-4 text-center">
          Nie masz konta?
          <.link navigate={~p"/zarejestruj"} class="text-brand font-semibold hover:underline">
            Zarejestruj się
          </.link>
        </p>

        <.link
          href={~p"/auth/google"}
          class="mt-8 flex w-full items-center justify-center gap-3 rounded-md border bg-white px-4 py-2 text-sm font-medium text-gray-700 transition-colors duration-200 hover:bg-black hover:text-white"
        >
          <svg class="size-4" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
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
          Zaloguj się przez Google
        </.link>
      </div>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    email = Phoenix.Flash.get(socket.assigns.flash, :email)
    form = to_form(%{"email" => email}, as: "user")

    socket =
      socket
      |> assign(form: form)
      |> assign(no_padding: true)

    {:ok, socket, temporary_assigns: [form: form]}
  end
end
