defmodule FirmowidWeb.User.LoginLive do
  @moduledoc false
  use FirmowidWeb, :live_view

  def render(assigns) do
    ~H"""
    <div class="w-screen h-screen overflow-clip flex items-center justify-center relative">
      <img src="/images/figurine.png" class="h-[135vh] opacity-10 absolute -top-20 left-1/2" />
      <div class="max-w-sm z-10">
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
            <.button phx-disable-with="Logowanie..." class="w-full">
              Zaloguj się
            </.button>
          </:actions>
        </.simple_form>

        <p class="mt-4 text-center">
          Nie masz konta?
          <.link navigate={~p"/zarejestruj"} class="font-semibold text-brand hover:underline">
            Zarejestruj się
          </.link>
        </p>
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
