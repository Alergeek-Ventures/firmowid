defmodule FirmowidWeb.Settings.Components.AccountTab do
  @moduledoc """
  Function components for the account settings route.
  """

  use FirmowidWeb, :html

  import FirmowidUI.Components.Button
  import FirmowidWeb.DesignSystem.Components.CoreComponents, except: [button: 1]
  import FirmowidWeb.Settings.Components.EditButton

  alias Firmowid.TimeFormatter
  alias FirmowidUI.Components.Inputs
  alias FirmowidWeb.Settings.Components.Helpers
  alias Phoenix.LiveView.Rendered

  @doc """
  Renders the main account overview route.
  """
  @spec account_tab(map()) :: Rendered.t()
  attr :current_user, :map, required: true
  attr :owned_organizations, :list, required: true
  attr :delete_account_form, :map, required: true
  attr :editing_account_name, :boolean, required: true
  attr :member_form, :map, required: true
  attr :editing_credentials, :boolean, required: true
  attr :email_form, :map, required: true
  attr :google_connected?, :boolean, required: true
  attr :password_form, :map, required: true
  attr :current_password, :string, default: nil

  def account_tab(assigns) do
    ~H"""
    <div class="grid w-full grid-cols-1 lg:grid-cols-2">
      <div class="flex flex-col gap-14">
        <.name_section
          current_user={@current_user}
          editing_account_name={@editing_account_name}
          member_form={@member_form}
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

        <.language_section />

        <.account_closure_section
          current_user={@current_user}
          owned_organizations={@owned_organizations}
          delete_account_form={@delete_account_form}
        />
      </div>
      <div></div>
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
    <section class={["space-y-4", @class]}>
      <div class="flex min-h-8 items-center gap-1">
        <h2 class="text-base leading-none font-medium text-grey-900">{@title}</h2>

        <span
          :if={@action}
          id={"settings-#{@action}-tooltip"}
          phx-hook="Tippy"
          data-tippy-content={@action_label || @title}
          data-tippy-delay="100"
          data-tippy-theme="small"
        >
          <.edit_button
            type="button"
            class="size-8!"
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
      class="justfy-center"
      value_class={["break-words", @value_class]}
    >
      {render_slot(@inner_block)}
    </Helpers.settings_display_field>
    """
  end

  attr :current_user, :map, required: true
  attr :editing_account_name, :boolean, required: true
  attr :member_form, :map, required: true

  defp name_section(assigns) do
    ~H"""
    <.account_section
      title={gettext("Personal data")}
      action={if(!@editing_account_name, do: "toggle_editing_account_name")}
      action_label={gettext("Edit personal data")}
    >
      <%= if @editing_account_name do %>
        <form phx-submit="save" class="space-y-4">
          <input type="hidden" name="user[name]" value={@member_form[:name].value || ""} />

          <div class="space-y-2">
            <Helpers.settings_field label={gettext("First name")} layout={:row} for="user_first_name">
              <.input
                type="text"
                name="user[first_name]"
                id="user_first_name"
                value={name_input_value(first_name(@member_form[:name].value))}
                errors={Inputs.translate_errors(@member_form.errors, :name)}
                input_class="w-full"
              />
            </Helpers.settings_field>

            <Helpers.settings_field label={gettext("Last name")} layout={:row} for="user_last_name">
              <.input
                type="text"
                name="user[last_name]"
                id="user_last_name"
                value={name_input_value(last_name(@member_form[:name].value))}
                input_class="w-full"
              />
            </Helpers.settings_field>

            <Helpers.settings_field
              label={gettext("Date of birth")}
              layout={:row}
              for="user_birthday"
            >
              <.input
                type="date"
                name="user[birthday]"
                id="user_birthday"
                value={birthday_input_value(@member_form[:birthday].value)}
                errors={Inputs.translate_errors(@member_form.errors, :birthday)}
                input_class="w-full"
              />
            </Helpers.settings_field>

            <Helpers.settings_field
              label={gettext("Sharing your date of birth")}
              layout={:row}
              for="user_birthday_visibility"
            >
              <.input
                type="select"
                name="user[birthday_visibility]"
                id="user_birthday_visibility"
                value={to_string(@member_form[:birthday_visibility].value || :not_shared)}
                options={[
                  {gettext("I do not share it"), "not_shared"},
                  {gettext("Day and month"), "day_with_month"},
                  {gettext("Full date"), "full_date"}
                ]}
                input_class="w-full"
              />
            </Helpers.settings_field>

            <Helpers.settings_display_field>
              <div class="flex items-start gap-4 rounded-lg bg-grey-50 p-4 text-sm text-grey-700">
                <span class="shrink-0"><.icon name="hero-information-circle" class="size-5" /></span>
                <p>
                  {gettext(
                    "If you agree to share your date of birth, choose the appropriate option from the list."
                  )}
                </p>
              </div>
            </Helpers.settings_display_field>
          </div>

          <div class="flex w-full justify-end gap-3">
            <.button
              type="button"
              variant="ghost"
              phx-click="toggle_editing_account_name"
              size="small"
            >
              {gettext("Cancel")}
            </.button>

            <.button type="submit" variant="success" size="small">
              {gettext("Save")}
            </.button>
          </div>
        </form>
      <% else %>
        <div class="space-y-2">
          <.detail_row label={gettext("First name")}>
            {first_name(@current_user.member.name)}
          </.detail_row>
          <.detail_row label={gettext("Last name")}>
            {last_name(@current_user.member.name)}
          </.detail_row>
          <.detail_row label={gettext("Date of birth")}>
            {format_birthday(@current_user.member.birthday)}
          </.detail_row>
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
      title={gettext("Access data")}
      action={if(!@editing_credentials, do: "toggle_editing_credentials")}
      action_label={gettext("Edit access data")}
    >
      <.form
        :if={@editing_credentials}
        for={@email_form}
        id="email_form"
        phx-submit="change_email"
        class="space-y-4"
      >
        <div class="space-y-2">
          <Helpers.settings_display_field
            label={gettext("Changing your email:")}
            label_class="text-grey-900"
          >
          </Helpers.settings_display_field>

          <Helpers.settings_field
            label={gettext("New email address")}
            class="w-full"
            for={@email_form[:email].id}
            layout={:row}
          >
            <.input field={@email_form[:email]} type="email" required />
          </Helpers.settings_field>
          <Helpers.settings_field
            :if={@current_user.hashed_password}
            label={gettext("Your password")}
            class="w-full"
            for="email_form_current_password"
            layout={:row}
          >
            <.input
              field={@email_form[:current_password]}
              id="email_form_current_password"
              type="password"
              required
            />
          </Helpers.settings_field>
          <Helpers.settings_display_field
            label={
              gettext(
                "We will send a confirmation link to the new address. After opening it, confirm the change with the button on the displayed page"
              )
            }
            label_class="order-2 text-start px-1"
          >
          </Helpers.settings_display_field>
        </div>
        <div class="flex w-full justify-start gap-5 sm:justify-end">
          <.button type="submit" variant="success" size="small">
            {gettext("Save email address")}
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
          <Helpers.settings_display_field
            label={gettext("Changing your password:")}
            label_class="text-grey-900"
          >
          </Helpers.settings_display_field>
          <Helpers.settings_field
            label={gettext("Your password")}
            layout={:row}
            class="pb-6"
            for="current_password_for_password"
          >
            <.input
              type="password"
              name="current_password"
              id="current_password_for_password"
              value={@current_password}
              required
              input_class="w-full"
            />
          </Helpers.settings_field>

          <Helpers.settings_field
            label={gettext("New password")}
            layout={:row}
            for={@password_form[:password].id}
          >
            <.input
              field={@password_form[:password]}
              type="password"
              required
              input_class="w-full"
            />
          </Helpers.settings_field>

          <Helpers.settings_field
            label={gettext("Repeat password")}
            layout={:row}
            for={@password_form[:password_confirmation].id}
          >
            <.input
              field={@password_form[:password_confirmation]}
              type="password"
              required
              input_class="w-full"
            />
          </Helpers.settings_field>
          <Helpers.settings_display_field
            label={gettext("Enter the new password in both fields, then click \"save\"")}
            label_class="order-2 text-start px-1"
          >
          </Helpers.settings_display_field>
        </div>

        <div class="flex w-full justify-end gap-3">
          <.button
            type="button"
            variant="ghost"
            size="small"
            phx-click="toggle_editing_credentials"
          >
            {gettext("Cancel")}
          </.button>

          <.button
            type="submit"
            variant="success"
            size="small"
            phx-disable-with={pgettext("settings", "Saving...")}
          >
            {gettext("Save password")}
          </.button>
        </div>
      </.form>

      <div :if={!@editing_credentials} class="space-y-2">
        <.detail_row label={gettext("E-mail")}>{@current_user.email}</.detail_row>
        <.detail_row label={gettext("Password")}>****************</.detail_row>
      </div>
    </.account_section>
    """
  end

  attr :google_connected?, :boolean, required: true
  attr :current_user, :map, required: true

  defp google_login_section(assigns) do
    ~H"""
    <.account_section title={gettext("Log in with Google")}>
      <div class="flex flex-col gap-4">
        <Helpers.settings_display_field label={gettext("Linked account")} class="w-full">
          <%= if @google_connected? do %>
            <div class="flex items-center gap-2">
              <span>{@current_user.email}</span>
              <span class="text-moss-700">
                <.icon name="hero-check-circle-solid" class="size-5" />
              </span>
            </div>
          <% else %>
            {gettext("None")}
          <% end %>
        </Helpers.settings_display_field>

        <Helpers.settings_display_field>
          <div class="flex items-center gap-5">
            <.button
              type="button"
              variant="outline"
              size="small"
              phx-click="link_google_account"
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
              {if @google_connected?,
                do: gettext("Link another"),
                else: gettext("Connect with Google")}
            </.button>

            <.button
              :if={@google_connected?}
              type="button"
              variant="destructive"
              size="small"
              phx-click="unlink_google_account"
            >
              {gettext("Disconnect")}
            </.button>
          </div>
        </Helpers.settings_display_field>
      </div>
    </.account_section>
    """
  end

  defp language_section(assigns) do
    assigns =
      assign(assigns,
        locale: Gettext.get_locale(Firmowid.Gettext),
        languages: FirmowidWeb.Infrastructure.Plugs.Locale.languages()
      )

    ~H"""
    <.account_section title={gettext("Language")}>
      <.form for={%{}} action={~p"/jezyk"} id="locale_form">
        <Helpers.settings_display_field>
          <.segmented_control label={gettext("Language")}>
            <:option
              :for={{code, name} <- @languages}
              name="jezyk"
              value={code}
              lang={code}
              active={@locale == code}
            >
              {name}
            </:option>
          </.segmented_control>
        </Helpers.settings_display_field>
      </.form>
    </.account_section>
    """
  end

  attr :current_user, :map, required: true
  attr :owned_organizations, :list, required: true
  attr :delete_account_form, :map, required: true

  defp account_closure_section(assigns) do
    assigns =
      assign(assigns,
        closure_parts:
          split_bold(
            gettext("Are you sure you want to close your account? %{warning}",
              warning: "__BOLD__"
            )
          ),
        owned_parts:
          split_bold(
            gettext(
              "We will also delete the organizations you own and all their data: %{organizations}.",
              organizations: "__BOLD__"
            )
          )
      )

    ~H"""
    <.account_section title={gettext("Closing the account")}>
      <div class="flex flex-col gap-4">
        <.detail_row label={gettext("Account name")}>{@current_user.email}</.detail_row>
        <Helpers.settings_display_field>
          <.button
            class="max-w-[200px]"
            type="button"
            variant="destructive"
            size="small"
            phx-click={show_modal("confirm_modal")}
          >
            {gettext("Close account")}
          </.button>
        </Helpers.settings_display_field>
      </div>

      <.modal id="confirm_modal">
        <h3 class="text-lg font-semibold text-grey-900">
          {elem(@closure_parts, 0)}<b>{gettext("This cannot be undone.")}</b>{elem(@closure_parts, 1)}
        </h3>

        <p class="mt-3 text-sm text-grey-700">
          {gettext("We will delete your account and all data assigned to it.")}
          <%= if @owned_organizations != [] do %>
            {elem(@owned_parts, 0)}<b>{Enum.map_join(@owned_organizations, ", ", & &1.name)}</b>{elem(
              @owned_parts,
              1
            )}
          <% end %>
        </p>

        <.simple_form for={@delete_account_form} phx-submit="delete_account" id="delete_account_form">
          <.input
            field={@delete_account_form[:current_password]}
            type="password"
            required
            input_class="w-full mb-0"
            class="flex items-center gap-5 text-sm text-grey-700 [&>label]:mb-0"
            label={gettext("Password")}
          />

          <:actions>
            <div class="flex w-full flex-col-reverse gap-3 sm:flex-row sm:justify-end">
              <.button
                type="button"
                variant="secondary"
                phx-click={hide_modal("confirm_modal")}
              >
                {gettext("Cancel")}
              </.button>

              <.button
                type="submit"
                variant="destructive"
                phx-disable-with={gettext("Deleting...")}
              >
                {gettext("Close account")}
              </.button>
            </div>
          </:actions>
        </.simple_form>
      </.modal>
    </.account_section>
    """
  end

  defp split_bold(text), do: List.to_tuple(String.split(text, "__BOLD__", parts: 2))

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

  # The dash marks a missing part in the read-only view; inputs start empty instead.
  defp name_input_value("—"), do: ""
  defp name_input_value(value), do: value

  defp default_dash(nil), do: "—"
  defp default_dash(""), do: "—"
  defp default_dash(value), do: value

  defp birthday_input_value(nil), do: ""
  defp birthday_input_value(%Date{} = date), do: Date.to_iso8601(date)
  defp birthday_input_value(date) when is_binary(date), do: date

  defp format_birthday(nil), do: "—"
  defp format_birthday(""), do: "—"

  defp format_birthday(%Date{} = date) do
    TimeFormatter.format_date(date)
  end

  defp format_birthday(date) when is_binary(date) do
    TimeFormatter.format_date(date)
  end
end
