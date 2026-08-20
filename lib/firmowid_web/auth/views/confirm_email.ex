defmodule FirmowidWeb.Auth.Views.ConfirmEmail do
  @moduledoc false
  use FirmowidWeb, :live_view

  import FirmowidWeb.DesignSystem.Components.Button
  import FirmowidWeb.DesignSystem.Components.CoreComponents, except: [button: 1]
  import FirmowidWeb.DesignSystem.Components.Link
  import Phoenix.Component, except: [link: 1]

  alias AshAuthentication.AddOn.Confirmation.Actions
  alias FirmowidWeb.Infrastructure.UserAuth

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-sm">
      <.header class="text-center">Potwierdź adres email</.header>

      <p class="text-grey-600 mt-2 text-center text-sm">
        {confirmation_instruction(@email_change?)}
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
            {confirmation_button_label(@email_change?)}
          </.button>
        </:actions>
      </.simple_form>

      <p :if={!@email_change?} class="mt-4 text-center text-sm">
        <.link kind="unstyled" redirect={~p"/zaloguj"}>Zaloguj się</.link>
      </p>
    </div>
    """
  end

  def mount(%{"token" => token}, _session, socket) do
    socket = load_current_user(socket)

    case confirmation_details(token) do
      {:ok, %{email_change?: email_change?}} ->
        form = to_form(%{"confirm" => token}, as: "user")
        {:ok, assign(socket, form: form, token: token, email_change?: email_change?)}

      :error ->
        {:ok,
         socket
         |> put_flash(:error, "Link potwierdzający jest nieprawidłowy lub wygasł.")
         |> redirect(to: ~p"/")}
    end
  end

  defp confirmation_details(token) do
    # Verify JWT signature and that it carries a confirm action claim,
    # then read (without consuming) the change saved under its jti.
    with {:ok, %{"act" => "confirm", "jti" => jti, "sub" => subject}, resource} <-
           AshAuthentication.Jwt.verify(token, :firmowid),
         {:ok, user} <- AshAuthentication.subject_to_user(subject, resource),
         strategy = AshAuthentication.Info.strategy!(resource, :confirm),
         {:ok, changes} <- Actions.get_changes(strategy, jti) do
      {:ok, %{email_change?: Map.get(changes, "email") != to_string(user.email)}}
    else
      _ -> :error
    end
  end

  defp confirmation_instruction(true), do: "Aby zmienić adres email, kliknij poniższy przycisk."

  defp confirmation_instruction(false), do: "Aby potwierdzić założenie konta, kliknij poniższy przycisk."

  defp confirmation_button_label(true), do: "Potwierdź zmianę adresu email"
  defp confirmation_button_label(false), do: "Potwierdź założenie konta"

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
