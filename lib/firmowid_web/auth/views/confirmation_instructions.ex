defmodule FirmowidWeb.Auth.Views.ConfirmationInstructions do
  @moduledoc false
  use FirmowidWeb, :live_view

  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Core.Senders.ConfirmationSender

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
    # Try to find user and resend confirmation if not yet confirmed
    # Always show the same message for security (don't reveal if email exists)
    with {:ok, user} <- fetch_user_by_email(email),
         true <- is_nil(user.confirmed_at) do
      send_confirmation_email(user)
    end

    info =
      "Jeśli Twój email jest w naszym systemie i nie został jeszcze potwierdzony, wkrótce otrzymasz wiadomość z instrukcjami."

    {:noreply,
     socket
     |> put_flash(:info, info)
     |> redirect(to: ~p"/")}
  end

  defp fetch_user_by_email(email) do
    case Core.get_user_by_email(email, authorize?: false, actor: %{}) do
      {:ok, user} -> {:ok, user}
      _ -> :error
    end
  end

  defp send_confirmation_email(user) do
    # Generate a confirmation token and send it
    # This mimics what the confirmation add-on does on user creation
    # Generate a JWT token with confirmation purpose
    {:ok, token, _claims} =
      AshAuthentication.Jwt.token_for_user(user, %{
        "act" => "confirm_new_user",
        "confirm" => true
      })

    ConfirmationSender.send(user, token, [])
  end
end
