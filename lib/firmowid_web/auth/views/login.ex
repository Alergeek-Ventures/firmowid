defmodule FirmowidWeb.Auth.Views.Login do
  @moduledoc false
  use FirmowidWeb, :live_view

  import FirmowidUI.Components.Button
  import FirmowidUI.Components.Link
  import FirmowidWeb.Auth.Components.AuthPage
  import FirmowidWeb.DesignSystem.Components.CoreComponents
  import Phoenix.Component, except: [link: 1]

  def render(assigns) do
    ~H"""
    <.auth_page title={gettext("Go to Firmowid")}>
      <.simple_form
        for={@form}
        id="login_form"
        action={~p"/auth/user/password/sign_in"}
        phx-update="ignore"
        method="post"
      >
        <.input field={@form[:email]} type="email" label={gettext("Email")} required />
        <.input
          field={@form[:password]}
          type="password"
          label={gettext("Password")}
          required
        />

        <:actions>
          <.input
            id="remember-me"
            name="user[remember_me]"
            checked={false}
            type="checkbox"
            label={gettext("Remember me")}
          />
          <.link kind="unstyled" redirect={~p"/resetuj-haslo"} class="text-sm font-semibold">
            {gettext("Forgot your password?")}
          </.link>
        </:actions>
        <:actions>
          <.button variant="special" phx-disable-with={gettext("Signing in...")} class="w-full">
            {gettext("Log in")}
          </.button>
        </:actions>
      </.simple_form>

      <p class="mt-4 text-center">
        {gettext("Don't have an account?")}
        <.link
          kind="unstyled"
          navigate={~p"/zarejestruj"}
          class="font-semibold text-rust-700 hover:underline"
        >
          {gettext("Sign up")}
        </.link>
      </p>

      <%!-- The box belongs to the password form, so the browser shows the Google
      button that carries it while it is ticked. --%>
      <div class="[body:has(#remember-me:checked)_&]:hidden">
        <.google_button label={gettext("Log in with Google")} />
      </div>
      <div class="hidden [body:has(#remember-me:checked)_&]:block">
        <.google_button label={gettext("Log in with Google")} remember_me />
      </div>
    </.auth_page>
    """
  end

  def mount(_params, _session, socket) do
    email = Phoenix.Flash.get(socket.assigns.flash, :email)
    form = to_form(%{"email" => email}, as: "user")

    socket =
      socket
      |> assign(form: form)
      |> assign(no_padding: true)
      |> assign(:page_title, gettext("Log in"))

    {:ok, socket, temporary_assigns: [form: form]}
  end
end
