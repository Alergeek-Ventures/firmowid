defmodule FirmowidWeb.Auth.Views.ConfirmationInstructions do
  @moduledoc false
  use FirmowidWeb, :live_view

  alias Firmowid.Accounts

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-sm">
      <.header class="text-center">
        Nie otrzymałeś instrukcji potwierdzenia?
        <:subtitle>Wyślemy nowy link potwierdzający na Twoją skrzynkę</:subtitle>
      </.header>

      <.simple_form for={@form} id="resend_confirmation_form" phx-submit="send_instructions">
        <.input field={@form[:email]} type="email" placeholder="Email" required />
        <:actions>
          <.button phx-disable-with="Wysyłanie..." class="w-full">
            Wyślij ponownie instrukcje potwierdzenia
          </.button>
        </:actions>
      </.simple_form>

      <p class="mt-4 text-center">
        <.link href={~p"/zarejestruj"}>Zarejestruj się</.link>
        | <.link href={~p"/zaloguj"}>Zaloguj się</.link>
      </p>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    {:ok, assign(socket, form: to_form(%{}, as: "user"))}
  end

  def handle_event("send_instructions", %{"user" => %{"email" => email}}, socket) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_user_confirmation_instructions(
        user,
        &url(~p"/potwierdz/#{&1}")
      )
    end

    info =
      "Jeśli Twój email jest w naszym systemie i nie został jeszcze potwierdzony, wkrótce otrzymasz wiadomość z instrukcjami."

    {:noreply,
     socket
     |> put_flash(:info, info)
     |> redirect(to: ~p"/")}
  end
end
