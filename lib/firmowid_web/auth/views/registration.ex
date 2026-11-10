defmodule FirmowidWeb.Auth.Views.Registration do
  @moduledoc false
  use FirmowidWeb, :live_view

  import FirmowidUI.Components.Button
  import FirmowidUI.Components.Link
  import FirmowidWeb.Auth.Components.AuthPage
  import FirmowidWeb.DesignSystem.Components.CoreComponents
  import Phoenix.Component, except: [link: 1]

  alias Firmowid.Core
  alias Firmowid.Core.User

  def render(assigns) do
    ~H"""
    <.auth_page title={gettext("Sign up")}>
      <.simple_form
        for={@form}
        id="registration_form"
        phx-submit="save"
        phx-change="validate"
        phx-trigger-action={@trigger_submit}
        action={~p"/auth/user/password/register"}
        method="post"
      >
        <.input
          id={@form[:email].id}
          name={@form[:email].name}
          value={@form[:email].value}
          errors={email_errors(@form[:email], @email_error)}
          type="email"
          label={gettext("Email")}
          required
        />
        <.input
          id={@form[:password].id}
          name={@form[:password].name}
          value={@form[:password].value}
          errors={password_errors(@form[:password])}
          type="password"
          label={gettext("Password")}
          required
        />

        <:actions>
          <.button variant="special" phx-disable-with={gettext("Creating account...")} class="w-full">
            {gettext("Create account")}
          </.button>
        </:actions>
      </.simple_form>

      <p class="mt-4 text-center">
        {gettext("Already have an account?")}
        <.link
          kind="unstyled"
          navigate={~p"/zaloguj"}
          class="font-semibold text-rust-700 hover:underline"
        >
          {gettext("Log in")}
        </.link>
      </p>

      <.google_button label={gettext("Sign up with Google")} />
    </.auth_page>
    """
  end

  def mount(_params, _session, socket) do
    # After a failed sign-up the controller sends back the email and, when it is taken, why.
    email = Phoenix.Flash.get(socket.assigns.flash, :email)

    form =
      User
      |> AshPhoenix.Form.for_create(:register_with_password,
        domain: Core,
        as: "user",
        params: %{"email" => email}
      )
      |> to_form()

    socket =
      socket
      |> assign(trigger_submit: false)
      |> assign(:form, form)
      |> assign(:email_error, Phoenix.Flash.get(socket.assigns.flash, :email_error))
      |> assign(no_padding: true)
      |> assign(:page_title, gettext("Sign up"))

    {:ok, socket}
  end

  def handle_event("save", %{"user" => user_params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.form, user_params)

    {:noreply,
     socket
     |> assign(:form, form)
     |> assign(:trigger_submit, form.source.valid?)}
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.form, user_params)

    socket =
      socket
      |> assign(:form, form)
      |> assign(:email_error, nil)
      |> assign(:trigger_submit, false)

    {:noreply, socket}
  end

  # A taken email comes back from the controller; the rest from the form.
  defp email_errors(_field, email_error) when is_binary(email_error), do: [email_error]

  defp email_errors(field, nil) do
    if Phoenix.Component.used_input?(field),
      do: Enum.map(field.errors, &translate_error/1),
      else: []
  end

  # The password strategy only requires a length, so one plain sentence says what to fix.
  defp password_errors(field) do
    if Phoenix.Component.used_input?(field) and field.errors != [],
      do: [gettext("The password needs at least 8 characters.")],
      else: []
  end
end
