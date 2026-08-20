defmodule FirmowidWeb.Settings.Components.AccountTab do
  @moduledoc """
  Function components for the account settings route.
  """

  use FirmowidWeb, :html

  import FirmowidWeb.DesignSystem.Components.Button
  import FirmowidWeb.DesignSystem.Components.CoreComponents, except: [button: 1]
  import FirmowidWeb.Settings.Components.EditButton

  alias FirmowidWeb.Settings.Components.Helpers
  alias Phoenix.LiveView.Rendered

  @doc """
  Renders the main account overview route.
  """
  @spec account_tab(map()) :: Rendered.t()
  attr :current_user, :map, required: true
  attr :current_org, :map, required: true
  attr :delete_account_form, :map, required: true
  attr :editing_account_name, :boolean, required: true
  attr :editing_credentials, :boolean, required: true
  attr :email_form, :map, required: true
  attr :google_connected?, :boolean, required: true
  attr :password_form, :map, required: true
  attr :current_password, :string, default: nil

  def account_tab(assigns) do
    ~H"""
    <div class="grid w-full grid-cols-1 gap-8 lg:grid-cols-2 lg:gap-16">
      <.name_section
        current_user={@current_user}
        editing_account_name={@editing_account_name}
      />

      <.credentials_section
        current_user={@current_user}
        editing_credentials={@editing_credentials}
        email_form={@email_form}
        password_form={@password_form}
        current_password={@current_password}
      />

      <.google_login_section
        google_connected?={@google_connected?}
        current_user={@current_user}
      />

      <.account_closure_section
        current_user={@current_user}
        current_org={@current_org}
        delete_account_form={@delete_account_form}
      />
    </div>
    """
  end

  attr :title, :string, required: true
  attr :action, :any, default: nil
  attr :action_label, :string, default: nil
  attr :class, :any, default: nil
  slot :inner_block, required: true

  defp account_section(assigns) do
    ~H"""
    <section class={["space-y-3", @class]}>
      <div class="flex min-h-8 items-center gap-2.5">
        <h2 class="text-grey-900 text-base leading-none font-semibold">{@title}</h2>

        <span
          :if={@action}
          id={"settings-#{@action}-tooltip"}
          phx-hook="Tippy"
          data-tippy-content={@action_label || @title}
          data-tippy-delay="100"
        >
          <.edit_button
            type="button"
            phx-click={@action}
            aria-label={@action_label || @title}
          />
        </span>
      </div>

      {render_slot(@inner_block)}
    </section>
    """
  end

  attr :label, :string, required: true
  attr :value_class, :string, default: nil
  slot :inner_block, required: true

  defp detail_row(assigns) do
    ~H"""
    <Helpers.settings_display_field
      label={@label}
      class="w-full"
      value_class={["break-words", @value_class]}
    >
      {render_slot(@inner_block)}
    </Helpers.settings_display_field>
    """
  end

  attr :current_user, :map, required: true
  attr :editing_account_name, :boolean, required: true

  defp name_section(assigns) do
    ~H"""
    <.account_section
      title="Imię i nazwisko"
      action={if(!@editing_account_name, do: "toggle_editing_account_name")}
      action_label="Edytuj imię i nazwisko"
    >
      <%= if @editing_account_name do %>
        <form phx-submit="save" class="space-y-4">
          <input type="hidden" name="user[name]" value={@current_user.name || ""} />

          <div class="space-y-2">
            <Helpers.settings_field label="Imię" class="w-full">
              <.input
                type="text"
                name="user[first_name]"
                value={first_name(@current_user.name)}
              />
            </Helpers.settings_field>

            <Helpers.settings_field label="Nazwisko" class="w-full">
              <.input
                type="text"
                name="user[last_name]"
                value={last_name(@current_user.name)}
              />
            </Helpers.settings_field>
          </div>

          <div class="flex w-full justify-start gap-5 lg:justify-end">
            <.button
              type="button"
              variant="secondary"
              phx-click="toggle_editing_account_name"
              size="small"
            >
              Anuluj
            </.button>

            <.button type="submit" variant="primary" size="small">
              Zapisz
            </.button>
          </div>
        </form>
      <% else %>
        <div class="space-y-2">
          <.detail_row label="Imię">{first_name(@current_user.name)}</.detail_row>
          <.detail_row label="Nazwisko">{last_name(@current_user.name)}</.detail_row>
        </div>
      <% end %>
    </.account_section>
    """
  end

  attr :current_user, :map, required: true
  attr :email_form, :map, required: true
  attr :password_form, :map, required: true
  attr :current_password, :string, default: nil
  attr :editing_credentials, :boolean, required: true

  defp credentials_section(assigns) do
    ~H"""
    <.account_section
      title="Dane dostępowe"
      action={if(!@editing_credentials, do: "toggle_editing_credentials")}
      action_label="Edytuj dane dostępowe"
    >
      <.form
        :if={@editing_credentials}
        for={@email_form}
        id="email_form"
        phx-submit="change_email"
        class="space-y-4"
      >
        <Helpers.settings_field label="Nowy adres email" class="w-full">
          <.input field={@email_form[:email]} type="email" required />
        </Helpers.settings_field>

        <p class="text-grey-600 text-sm">
          Wyślemy link potwierdzający na nowy adres. Zmiana nastąpi po jego otwarciu.
        </p>

        <div class="flex w-full justify-start gap-5 sm:justify-end">
          <.button type="submit" variant="primary" size="small">
            Zapisz adres email
          </.button>
        </div>
      </.form>

      <.form
        :if={@editing_credentials}
        for={@password_form}
        id="password_form"
        action={~p"/zaloguj?_action=password_updated"}
        method="post"
        phx-change="validate_password"
        phx-submit="update_password"
        class="space-y-4"
      >
        <div class="space-y-2">
          <Helpers.settings_field label="Twoje hasło" class="w-full">
            <.input
              type="password"
              name="current_password"
              id="current_password_for_password"
              value={@current_password}
              required
            />
          </Helpers.settings_field>

          <Helpers.settings_field label="Nowe hasło" class="w-full">
            <.input
              type="password"
              name={@password_form[:password].name}
              value={@password_form[:password].value}
              required
            />
          </Helpers.settings_field>

          <Helpers.settings_field label="Powtórz hasło" class="w-full">
            <.input
              type="password"
              name={@password_form[:password_confirmation].name}
              value={@password_form[:password_confirmation].value}
              required
            />
          </Helpers.settings_field>
        </div>

        <div class="flex w-full justify-start gap-5 sm:justify-end">
          <.button
            type="button"
            variant="secondary"
            size="small"
            phx-click="toggle_editing_credentials"
          >
            Anuluj
          </.button>

          <.button
            type="submit"
            variant="primary"
            size="small"
            phx-disable-with="Zapisywanie..."
          >
            Zapisz
          </.button>
        </div>
      </.form>

      <div :if={!@editing_credentials} class="space-y-2">
        <.detail_row label="E-mail">{@current_user.email}</.detail_row>
        <.detail_row label="Hasło">****************</.detail_row>
      </div>
    </.account_section>
    """
  end

  attr :google_connected?, :boolean, required: true
  attr :current_user, :map, required: true

  defp google_login_section(assigns) do
    ~H"""
    <.account_section title="Logowanie przez Google">
      <div class="flex flex-col gap-4">
        <Helpers.settings_display_field label="Powiązane konto" class="w-full">
          <%= if @google_connected? do %>
            <div class="flex items-center gap-2">
              <span>{@current_user.email}</span>
              <span class="text-green-700">
                <.icon name="hero-check-circle-solid" class="size-5" />
              </span>
            </div>
          <% else %>
            Brak
          <% end %>
        </Helpers.settings_display_field>

        <p :if={@google_connected?} class="text-grey-600 text-sm">
          Aby zmienić konto Google, najpierw zmień i potwierdź powyższy adres email.
        </p>

        <.button
          type="button"
          variant="outline"
          size="small"
          phx-click={
            if(@google_connected?, do: "replace_google_account", else: "link_google_account")
          }
          class="gap-2 self-start"
        >
          <svg class="size-5" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
            <path
              d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"
              fill="#4285F4"
            />
            <path
              d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"
              fill="#34A853"
            />
            <path
              d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"
              fill="#FBBC05"
            />
            <path
              d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"
              fill="#EA4335"
            />
          </svg>
          {if @google_connected?, do: "Zmień konto Google", else: "Połącz z Google"}
        </.button>

        <.button
          :if={@google_connected?}
          type="button"
          variant="destructive"
          size="small"
          phx-click="unlink_google_account"
        >
          Rozłącz
        </.button>
      </div>
    </.account_section>
    """
  end

  attr :current_user, :map, required: true
  attr :current_org, :map, required: true
  attr :delete_account_form, :map, required: true

  defp account_closure_section(assigns) do
    ~H"""
    <.account_section title="Zamykanie konta">
      <div class="flex flex-col gap-4">
        <.detail_row label="Nazwa konta">{@current_user.email}</.detail_row>

        <.button
          class="max-w-[200px]"
          type="button"
          variant="destructive"
          size="small"
          phx-click={show_modal("confirm_modal")}
        >
          Zamknij konto
        </.button>
      </div>

      <.modal id="confirm_modal">
        <h3 class="text-grey-900 text-lg font-semibold">
          Czy na pewno chcesz zamknąć konto? <b>Nie da się tego cofnąć.</b>
        </h3>

        <p class="text-grey-700 mt-3 text-sm">
          Usuniemy Twoje konto i wszystkie przypisane do niego dane.
          <%= if @current_org.owner_id == @current_user.id do %>
            Usuniemy też całą organizację i wszystkie jej dane.
          <% end %>
        </p>

        <.simple_form for={@delete_account_form} phx-submit="delete_account" id="delete_account_form">
          <.input
            field={@delete_account_form[:current_password]}
            type="password"
            label="Twoje hasło"
            required
          />

          <:actions>
            <div class="flex flex-col-reverse gap-3 sm:flex-row sm:justify-end">
              <.button
                type="button"
                variant="secondary"
                phx-click={hide_modal("confirm_modal")}
              >
                Anuluj
              </.button>

              <.button
                type="submit"
                variant="destructive"
                phx-disable-with="Usuwam..."
              >
                Zamknij konto
              </.button>
            </div>
          </:actions>
        </.simple_form>
      </.modal>
    </.account_section>
    """
  end

  defp first_name(nil), do: "—"

  defp first_name(name) do
    name
    |> to_string()
    |> String.split(~r/\s+/, trim: true)
    |> List.first()
    |> default_dash()
  end

  defp last_name(nil), do: "—"

  defp last_name(name) do
    parts = String.split(to_string(name), ~r/\s+/, trim: true)

    case parts do
      [_single] -> "—"
      [_first | rest] -> Enum.join(rest, " ")
      _ -> "—"
    end
  end

  defp default_dash(nil), do: "—"
  defp default_dash(""), do: "—"
  defp default_dash(value), do: value
end
