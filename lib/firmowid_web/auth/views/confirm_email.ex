defmodule FirmowidWeb.Auth.Views.ConfirmEmail do
  @moduledoc false
  use FirmowidWeb, :live_view

  import FirmowidWeb.DesignSystem.Components.Button
  import FirmowidWeb.DesignSystem.Components.CoreComponents, except: [button: 1]
  import FirmowidWeb.DesignSystem.Components.Link
  import Phoenix.Component, except: [link: 1]

  alias FirmowidWeb.Infrastructure.UserAuth

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-sm">
      <.header class="text-center">Potwierdź adres email</.header>

      <p class="text-grey-600 mt-2 text-center text-sm">
        Aby potwierdzić adres email, kliknij poniższy przycisk.
      </p>

      <%!-- Form posts to ash_authentication confirmation endpoint (require_interaction? true
           means GET links are rejected — a button-click POST is required). --%>
      <.simple_form
        for={@form}
        id="confirm_email_form"
        action={~p"/auth/user/confirm"}
        method="post"
        phx-update="ignore"
      >
        <input type="hidden" name={@form[:confirm].name} value={@token} />
        <:actions>
          <.button variant="special" phx-disable-with="Potwierdzanie..." class="w-full">
            Potwierdź adres email
          </.button>
        </:actions>
      </.simple_form>

      <p class="mt-4 text-center text-sm">
        <.link kind="unstyled" redirect={~p"/zaloguj"}>Zaloguj się</.link>
      </p>
    </div>
    """
  end

  def mount(%{"token" => token}, _session, socket) do
    socket = load_current_user(socket)

    case verify_confirmation_token(token) do
      {:ok, _token} ->
        form = to_form(%{"confirm" => token}, as: "user")
        {:ok, assign(socket, form: form, token: token)}

      :error ->
        {:ok,
         socket
         |> put_flash(:error, "Link potwierdzający jest nieprawidłowy lub wygasł.")
         |> redirect(to: ~p"/")}
    end
  end

  defp verify_confirmation_token(token) do
    # Verify JWT signature and that it carries a confirm action claim,
    # without consuming the token before the user clicks the button.
    case AshAuthentication.Jwt.verify(token, :firmowid) do
      {:ok, %{"act" => "confirm"}, _resource} -> {:ok, token}
      _ -> :error
    end
  end

  defp load_current_user(socket) do
    case socket.assigns[:current_user] do
      nil ->
        socket

      user when is_nil(user.organization_id) ->
        assign(socket, :current_user, Ash.load!(user, [avatar_blob: [:url]], actor: user))

      user ->
        {loaded_user, _org, _scope} = UserAuth.load_scope_and_avatars(user)
        assign(socket, :current_user, loaded_user)
    end
  end
end
