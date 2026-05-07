defmodule FirmowidWeb.Settings.Components.ProfileTab do
  @moduledoc """
  Function components for the profile settings route.
  """

  use FirmowidWeb, :html

  import FirmowidWeb.DesignSystem.Components.Button
  import FirmowidWeb.Settings.Components.EditButton
  import Phoenix.Component, except: [link: 1]

  alias FirmowidWeb.Infrastructure.Utilities.TimeFormatter
  alias FirmowidWeb.Settings.Components.Helpers
  alias Phoenix.LiveView.Rendered

  @doc """
  Renders the self-profile route content.
  """
  @spec profile_tab(map()) :: Rendered.t()
  attr :current_user, :map, required: true
  attr :user_form, :map, required: true
  attr :editing_profile_employment, :boolean, required: true
  attr :editing_profile_finance, :boolean, required: true
  attr :editing_profile_contact, :boolean, required: true

  def profile_tab(assigns) do
    ~H"""
    <div class="grid items-start gap-8 lg:grid-cols-2 lg:gap-16">
      <.employment_section
        current_user={@current_user}
        user_form={@user_form}
        editing_profile_employment={@editing_profile_employment}
      />
      <.finance_section
        current_user={@current_user}
        user_form={@user_form}
        editing_profile_finance={@editing_profile_finance}
      />

      <.contact_section
        current_user={@current_user}
        user_form={@user_form}
        editing_profile_contact={@editing_profile_contact}
      />
    </div>
    """
  end

  attr :title, :string, required: true
  attr :action, :any, default: nil
  attr :action_label, :string, default: nil
  slot :inner_block, required: true

  defp profile_section(assigns) do
    ~H"""
    <section class="space-y-3">
      <div class="flex min-h-8 items-center gap-2.5">
        <h2 class="text-grey-900 text-base leading-none font-semibold">{@title}</h2>

        <span
          :if={@action}
          id={"settings-#{@action}-tooltip"}
          phx-hook="Tippy"
          data-tippy-content={@action_label || "Edytuj #{@title}"}
          data-tippy-delay="100"
        >
          <.edit_button
            type="button"
            phx-click={@action}
            aria-label={@action_label || "Edytuj #{@title}"}
          />
        </span>
      </div>

      {render_slot(@inner_block)}
    </section>
    """
  end

  attr :label, :string, required: true
  slot :inner_block, required: true

  defp detail_row(assigns) do
    ~H"""
    <Helpers.settings_display_field
      label={@label}
      class="w-full"
      value_class="break-words"
    >
      {render_slot(@inner_block)}
    </Helpers.settings_display_field>
    """
  end

  attr :current_user, :map, required: true
  attr :user_form, :map, required: true
  attr :editing_profile_employment, :boolean, required: true

  defp employment_section(assigns) do
    ~H"""
    <.profile_section
      title="Informacje o zatrudnieniu"
      action={if(!@editing_profile_employment, do: "toggle_editing_profile_employment")}
      action_label="Edytuj informacje o zatrudnieniu"
    >
      <%= if @editing_profile_employment do %>
        <.form for={@user_form} phx-submit="save" class="space-y-4">
          <div class="space-y-2">
            <.stacked_input field={@user_form[:position]} label="Stanowisko" type="text" />
            <.stacked_input field={@user_form[:employment_date]} label="Obowiązuje od" type="date" />
          </div>

          <div class="flex w-full justify-start gap-5 sm:justify-end">
            <.button
              type="button"
              variant="secondary"
              size="small"
              phx-click="toggle_editing_profile_employment"
            >
              Anuluj
            </.button>

            <.button type="submit" variant="primary" size="small">
              Zapisz
            </.button>
          </div>
        </.form>
      <% else %>
        <div class="space-y-2">
          <.detail_row label="Stanowisko">{present(@current_user.position)}</.detail_row>
          <.detail_row label="Obowiązuje od">
            {present_date(@current_user.employment_date)}
          </.detail_row>
        </div>
      <% end %>
    </.profile_section>
    """
  end

  attr :current_user, :map, required: true
  attr :user_form, :map, required: true
  attr :editing_profile_finance, :boolean, required: true

  defp finance_section(assigns) do
    ~H"""
    <.profile_section
      title="Finanse"
      action={if(!@editing_profile_finance, do: "toggle_editing_profile_finance")}
      action_label="Edytuj finanse"
    >
      <%= if @editing_profile_finance do %>
        <.form for={@user_form} phx-submit="save" class="w-full space-y-2">
          <.stacked_input field={@user_form[:bank_account_number]} label="Nr konta" type="text" />
          <div class="flex w-full justify-start gap-5 sm:justify-end">
            <.button
              type="button"
              variant="secondary"
              phx-click="toggle_editing_profile_finance"
              size="small"
            >
              Anuluj
            </.button>
            <.button type="submit" variant="primary" size="small">Zapisz</.button>
          </div>
        </.form>
      <% else %>
        <div class="w-full space-y-2">
          <.detail_row label="Nr konta">{present(@current_user.bank_account_number)}</.detail_row>
        </div>
      <% end %>
    </.profile_section>
    """
  end

  attr :current_user, :map, required: true
  attr :user_form, :map, required: true
  attr :editing_profile_contact, :boolean, required: true

  defp contact_section(assigns) do
    ~H"""
    <.profile_section
      title="Dane korespondencyjne"
      action={if(!@editing_profile_contact, do: "toggle_editing_profile_contact")}
      action_label="Edytuj dane korespondencyjne"
    >
      <%= if @editing_profile_contact do %>
        <.form for={@user_form} phx-submit="save" class="space-y-6">
          <div class="w-full space-y-2">
            <.stacked_input field={@user_form[:phone]} label="Numer telefonu" type="tel" />

            <.stacked_input field={@user_form[:slack_id]} label="Slack" type="text" />
            <.stacked_input
              field={@user_form[:residence_street]}
              label="Adres zamieszkania"
              type="text"
            />
            <.stacked_input field={@user_form[:residence_code]} label="Kod pocztowy" type="text" />
            <.stacked_input field={@user_form[:residence_city]} label="Miasto" type="text" />
            <.stacked_input
              field={@user_form[:correspondence_street]}
              label="Adres korespondencyjny"
              type="text"
            />
            <.stacked_input
              field={@user_form[:correspondence_code]}
              label="Kod korespondencyjny"
              type="text"
            />
            <.stacked_input
              field={@user_form[:correspondence_city]}
              label="Miasto korespondencyjne"
              type="text"
            />
          </div>

          <div class="flex w-full justify-start gap-5 sm:justify-end">
            <.button
              type="button"
              variant="secondary"
              size="small"
              phx-click="toggle_editing_profile_contact"
            >
              Anuluj
            </.button>
            <.button type="submit" variant="primary" size="small">Zapisz</.button>
          </div>
        </.form>
      <% else %>
        <div class="w-full space-y-2">
          <.detail_row label="Numer telefonu">{present(@current_user.phone)}</.detail_row>
          <.detail_row label="Slack">
            <span :if={slack_present?(@current_user)}>{present_slack(@current_user)}</span>
            <span :if={!slack_present?(@current_user)}>—</span>
          </.detail_row>
          <.detail_row label="Adres zamieszkania">
            {present_address(@current_user, :residence)}
          </.detail_row>
          <.detail_row label="Adres korespondencyjny">
            {present_address(@current_user, :correspondence)}
          </.detail_row>
        </div>
      <% end %>
    </.profile_section>
    """
  end

  attr :field, :map, required: true
  attr :label, :string, required: true
  attr :type, :string, required: true

  defp stacked_input(assigns) do
    ~H"""
    <Helpers.settings_field label={@label} class="w-full">
      <.input type={@type} name={@field.name} value={@field.value} />
    </Helpers.settings_field>
    """
  end

  defp present(nil), do: "—"
  defp present(""), do: "—"
  defp present(value), do: to_string(value)

  defp present_date(nil), do: "—"
  defp present_date(value), do: TimeFormatter.format_date(value)

  defp present_slack(%{slack_id: nil}), do: nil

  defp present_slack(%{slack_id: slack_id, slack_url: slack_url}) do
    slack_workspace = slack_url || "https://alergeekventures.slack.com"
    "#{slack_id} (#{slack_workspace})"
  end

  defp slack_present?(%{slack_id: slack_id}) when slack_id in [nil, ""], do: false
  defp slack_present?(_user), do: true

  defp present_address(user, type) do
    parts =
      case type do
        :residence ->
          [user.residence_street, postal_line(user.residence_code, user.residence_city)]

        :correspondence ->
          [
            user.correspondence_street,
            postal_line(user.correspondence_code, user.correspondence_city)
          ]
      end

    case Enum.reject(parts, &blank?/1) do
      [] -> "—"
      filled -> Enum.join(filled, ", ")
    end
  end

  defp postal_line(code, city) do
    [code, city]
    |> Enum.reject(&blank?/1)
    |> Enum.join(" ")
  end

  defp blank?(value), do: value in [nil, ""]
end
