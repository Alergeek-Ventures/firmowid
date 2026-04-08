defmodule FirmowidWeb.Auth.Views.ResetPassword do
  @moduledoc false
  use FirmowidWeb, :live_view

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-sm">
      <.header class="text-center">Resetuj hasło</.header>

      <%!-- Form posts to ash_authentication password reset endpoint --%>
      <.simple_form
        for={@form}
        id="reset_password_form"
        action={~p"/auth/user/password/reset"}
        method="post"
        phx-update="ignore"
      >
        <.error :if={@form.errors != []}>
          Ups, coś poszło nie tak! Sprawdź błędy poniżej.
        </.error>

        <input type="hidden" name={@form[:reset_token].name} value={@reset_token} />
        <.input field={@form[:password]} type="password" label="Nowe hasło" required />
        <.input
          field={@form[:password_confirmation]}
          type="password"
          label="Potwierdź nowe hasło"
          required
        />
        <:actions>
          <.button phx-disable-with="Resetowanie..." class="w-full">Resetuj hasło</.button>
        </:actions>
      </.simple_form>

      <p class="mt-4 text-center text-sm">
        <.link href={~p"/zarejestruj"}>Zarejestruj się</.link>
        | <.link href={~p"/zaloguj"}>Zaloguj się</.link>
      </p>
    </div>
    """
  end

  def mount(%{"token" => token}, _session, socket) do
    # Verify token is valid by attempting to get user from it
    case verify_reset_token(token) do
      {:ok, _token} ->
        form = to_form(%{"reset_token" => token}, as: "user")
        {:ok, assign(socket, form: form, reset_token: token)}

      :error ->
        {:ok,
         socket
         |> put_flash(:error, "Link do resetowania hasła jest nieprawidłowy lub wygasł.")
         |> redirect(to: ~p"/")}
    end
  end

  defp verify_reset_token(token) do
    # Verify the JWT signature and claims without triggering the actual reset action.
    # The previous implementation called Strategy.action(:reset, ...) which could
    # consume the token before the user submits the form.
    case AshAuthentication.Jwt.verify(token, :firmowid) do
      {:ok, %{"act" => "password_reset_with_password"}, _resource} -> {:ok, token}
      _ -> :error
    end
  end
end
