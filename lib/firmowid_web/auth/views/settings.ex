defmodule FirmowidWeb.Auth.Views.Settings do
  @moduledoc false
  use FirmowidWeb, :live_view

  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Core.User

  def render(assigns) do
    ~H"""
    <.header class="text-center">
      Ustawienia Konta
      <:subtitle>Zarządzaj adresem email i ustawieniami hasła</:subtitle>
    </.header>

    <div class="space-y-12 divide-y">
      <div>
        <.simple_form
          for={@email_form}
          id="email_form"
          phx-submit="update_email"
          phx-change="validate_email"
        >
          <.input field={@email_form[:email]} type="email" label="Email" required />
          <.input
            field={@email_form[:current_password]}
            name="current_password"
            id="current_password_for_email"
            type="password"
            label="Aktualne hasło"
            value={@email_form_current_password}
            required
          />
          <:actions>
            <.button phx-disable-with="Zmieniam...">Zmień Email</.button>
          </:actions>
        </.simple_form>
      </div>
      <div>
        <.simple_form
          for={@password_form}
          id="password_form"
          phx-change="validate_password"
          phx-submit="update_password"
        >
          <.input field={@password_form[:password]} type="password" label="Nowe hasło" required />
          <.input
            field={@password_form[:password_confirmation]}
            type="password"
            label="Potwierdź nowe hasło"
          />
          <.input
            field={@password_form[:current_password]}
            name="current_password"
            type="password"
            label="Aktualne hasło"
            id="current_password_for_password"
            value={@current_password}
            required
          />
          <:actions>
            <.button phx-disable-with="Zmieniam...">Zmień Hasło</.button>
          </:actions>
        </.simple_form>
      </div>
    </div>
    """
  end

  def mount(%{"token" => token}, _session, socket) do
    # Handle email change confirmation token
    strategy = AshAuthentication.Info.strategy!(User, :confirm_email_update)

    socket =
      case AshAuthentication.Strategy.action(strategy, :confirm, %{"confirm" => token}) do
        {:ok, _user} ->
          put_flash(socket, :info, "Email został zmieniony pomyślnie.")

        {:error, _error} ->
          put_flash(socket, :error, "Link do zmiany emaila jest nieprawidłowy lub wygasł.")
      end

    {:ok, push_navigate(socket, to: ~p"/ustawienia/bezpieczenstwo")}
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    # Create forms for email and password changes
    # Note: ash_authentication generates :change_password action for password changes
    # Email changes use the confirm_email_update confirmation add-on
    email_form =
      user
      |> AshPhoenix.Form.for_update(:update_profile,
        domain: Core,
        as: "user",
        actor: user,
        authorize?: true
      )
      |> to_form()

    password_form =
      user
      |> AshPhoenix.Form.for_update(:change_password,
        domain: Core,
        as: "user",
        actor: user,
        authorize?: true
      )
      |> to_form()

    socket =
      socket
      |> assign(:current_password, nil)
      |> assign(:email_form_current_password, nil)
      |> assign(:current_email, user.email)
      |> assign(:email_form, email_form)
      |> assign(:password_form, password_form)

    {:ok, socket}
  end

  def handle_event("validate_email", params, socket) do
    %{"current_password" => password, "user" => user_params} = params

    email_form =
      AshPhoenix.Form.validate(socket.assigns.email_form, user_params)

    {:noreply, assign(socket, email_form: email_form, email_form_current_password: password)}
  end

  def handle_event("update_email", params, socket) do
    %{"current_password" => _password, "user" => user_params} = params
    _user = socket.assigns.current_user

    # Email change uses the confirm_email_update confirmation add-on
    # which inhibits the update and sends a confirmation email
    strategy = AshAuthentication.Info.strategy!(User, :confirm_email_update)

    case AshAuthentication.Strategy.action(strategy, :request, %{
           "email" => user_params["email"]
         }) do
      {:ok, _user} ->
        info = "Link potwierdzający zmianę adresu email został wysłany na nowy adres."
        {:noreply, socket |> put_flash(:info, info) |> assign(email_form_current_password: nil)}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Nie udało się zainicjować zmiany emaila: #{inspect(error)}")}
    end
  end

  def handle_event("validate_password", params, socket) do
    %{"current_password" => password, "user" => user_params} = params

    password_form =
      AshPhoenix.Form.validate(socket.assigns.password_form, user_params)

    {:noreply, assign(socket, password_form: password_form, current_password: password)}
  end

  def handle_event("update_password", params, socket) do
    %{"current_password" => _password, "user" => user_params} = params

    case AshPhoenix.Form.submit(socket.assigns.password_form, params: user_params) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> put_flash(:info, "Hasło zostało zmienione pomyślnie.")
         |> push_navigate(to: ~p"/ustawienia/bezpieczenstwo")}

      {:error, form} ->
        {:noreply, assign(socket, password_form: form)}
    end
  end
end
