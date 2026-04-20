defmodule FirmowidWeb.Auth.Views.ForgotPassword do
  @moduledoc false
  use FirmowidWeb, :live_view

  import FirmowidWeb.DesignSystem.Components.Button
  import FirmowidWeb.DesignSystem.Components.CoreComponents, except: [button: 1]
  import FirmowidWeb.DesignSystem.Components.Link
  import Phoenix.Component, except: [link: 1]

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-sm">
      <.header class="text-center">
        Nie pamiętasz hasła?
        <:subtitle>Wyślemy Ci link do resetowania hasła na Twoją skrzynkę</:subtitle>
      </.header>

      <%!-- Form posts to ash_authentication password reset request endpoint --%>
      <.simple_form
        for={@form}
        id="reset_password_form"
        action={~p"/auth/user/password/reset_request"}
        method="post"
        phx-update="ignore"
      >
        <.input field={@form[:email]} type="email" placeholder="Email" required />
        <:actions>
          <.button variant="special" phx-disable-with="Wysyłanie..." class="w-full">
            Wyślij instrukcje resetowania hasła
          </.button>
        </:actions>
      </.simple_form>
      <p class="mt-4 text-center text-sm">
        <.link kind="unstyled" redirect={~p"/zarejestruj"}>Zarejestruj się</.link>
        | <.link kind="unstyled" redirect={~p"/zaloguj"}>Zaloguj się</.link>
      </p>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    {:ok, assign(socket, form: to_form(%{}, as: "user"))}
  end
end
