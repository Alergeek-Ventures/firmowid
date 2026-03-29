defmodule FirmowidWeb.Auth.Views.ForgotPassword do
  @moduledoc false
  use FirmowidWeb, :live_view

  alias Firmowid.Accounts

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-sm">
      <.header class="text-center">
        Nie pamiętasz hasła?
        <:subtitle>Wyślemy Ci link do resetowania hasła na Twoją skrzynkę</:subtitle>
      </.header>

      <.simple_form for={@form} id="reset_password_form" phx-submit="send_email">
        <.input field={@form[:email]} type="email" placeholder="Email" required />
        <:actions>
          <.button phx-disable-with="Wysyłanie..." class="w-full">
            Wyślij instrukcje resetowania hasła
          </.button>
        </:actions>
      </.simple_form>
      <p class="text-center text-sm mt-4">
        <.link href={~p"/zarejestruj"}>Zarejestruj się</.link>
        | <.link href={~p"/zaloguj"}>Zaloguj się</.link>
      </p>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    {:ok, assign(socket, form: to_form(%{}, as: "user"))}
  end

  def handle_event("send_email", %{"user" => %{"email" => email}}, socket) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_user_reset_password_instructions(
        user,
        &url(~p"/resetuj-haslo/#{&1}")
      )
    end

    info =
      "Jeśli Twój email jest w naszym systemie, wkrótce otrzymasz instrukcje resetowania hasła."

    {:noreply,
     socket
     |> put_flash(:info, info)
     |> redirect(to: ~p"/")}
  end
end
