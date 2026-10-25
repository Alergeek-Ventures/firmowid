defmodule FirmowidWeb.Settings.Components.InvoicesTab do
  @moduledoc """
  Function components for invoice e-mail import settings and planned tax reserve assumptions.
  """

  use FirmowidWeb, :html

  import FirmowidUI.Components.Button

  alias Firmowid.Ash.Analysis.TaxForecast
  alias FirmowidWeb.Settings.Components.TaxForecastSettings
  alias Phoenix.LiveView.Rendered

  @doc """
  Renders the invoice e-mail settings route.
  """
  @spec invoices_tab(map()) :: Rendered.t()
  attr :current_org, :map, required: true
  attr :current_user, :map, required: true

  def invoices_tab(assigns) do
    assigns =
      assigns
      |> assign(:admin?, assigns.current_user.member.role == :admin)
      |> assign(:inbound_email, inbound_email(assigns.current_org))
      |> assign(:allowed_sender_emails, assigns.current_org.allowed_sender_emails || [])
      |> assign(:tax_forecast?, Ash.can?({TaxForecast, :get}, assigns.current_user))

    ~H"""
    <div
      id="settings-invoices-tab"
      phx-hook="CopyToClipboard"
      class="grid w-full gap-8 lg:grid-cols-2 lg:gap-x-12"
    >
      <section class="space-y-4">
        <div class="flex min-h-8 flex-wrap items-center gap-3">
          <h2 class="text-base leading-none font-semibold text-grey-900">
            Import e-mail faktur kosztowych
          </h2>

          <.badge tone="success">aktywny</.badge>
        </div>

        <.field_row label="Adres odbiorczy">
          <div class="flex flex-col gap-3 sm:flex-row sm:items-center">
            <.button
              type="button"
              variant="secondary"
              accent="rust"
              size="small"
              phx-click="copy_inbound_email"
              phx-value-email={@inbound_email}
              class="w-full max-w-sm justify-between text-left sm:w-80"
            >
              <span class="min-w-0 truncate">{@inbound_email}</span>
              <.icon name="hero-envelope" class="size-4 shrink-0" />
            </.button>

            <.tooltip
              :if={@admin?}
              id="settings-regenerate-inbound-email-tooltip"
              text="Wygeneruje nowy adres importu. Zaktualizuj reguły przekazywania poczty po zmianie."
            >
              <.button
                type="button"
                variant="secondary"
                size="small"
                phx-click="regenerate_inbound_nickname"
                data-confirm="Wygenerować nowy adres importu faktur? Dotychczasowy adres przestanie być właściwym miejscem do wysyłki nowych wiadomości."
              >
                Wygeneruj nowy adres
              </.button>
            </.tooltip>
          </div>
        </.field_row>

        <.alert>
          Wysyłaj faktury kosztowe na ten adres. Firmowid zaimportuje je automatycznie,
          ale przyjmie tylko wiadomości z adresów dodanych do listy dozwolonych nadawców.
        </.alert>
      </section>

      <section class="space-y-4">
        <div class="space-y-2">
          <h2 class="text-base leading-none font-semibold text-grey-900">
            Dozwoleni nadawcy
          </h2>
          <p class="max-w-prose text-sm leading-[1.35] text-grey-700">
            Dodaj adresy, z których dostawcy lub zespół mogą przesyłać faktury do Firmowida.
          </p>
        </div>

        <div class="space-y-3">
          <.empty_state
            :if={Enum.empty?(@allowed_sender_emails)}
            title="Nie dodano jeszcze żadnych adresów."
          >
            <:icon><Lucideicons.mail /></:icon>
            Import zadziała dopiero po dodaniu pierwszego nadawcy.
          </.empty_state>

          <div
            :for={email <- @allowed_sender_emails}
            class="flex min-h-11 items-center justify-between gap-3 rounded-lg bg-teal-100 px-3 py-2 text-sm leading-[1.35] text-teal-800 sm:min-h-10"
          >
            <span class="min-w-0 truncate">{email}</span>
            <.icon_button
              :if={@admin?}
              label={"Usuń #{email}"}
              phx-click="remove_allowed_email"
              phx-value-email={email}
            >
              <.icon name="hero-x-mark" class="size-4" />
            </.icon_button>
          </div>
        </div>

        <form :if={@admin?} phx-submit="add_allowed_email" class="space-y-3">
          <.field_row label="Dodaj nowy adres" for="allowed_sender_email">
            <div class="flex flex-col gap-3 sm:flex-row sm:items-center">
              <.input
                type="email"
                name="email"
                id="allowed_sender_email"
                value=""
                required
                placeholder="np. faktury@dostawca.pl"
                new
                class="w-full max-w-sm"
                input_class="w-full"
              />

              <.button type="submit" variant="secondary" size="small">
                Dodaj adres
              </.button>
            </div>
          </.field_row>
        </form>

        <.alert :if={!@admin?}>
          Tylko administrator może zmieniać adres odbiorczy i listę dozwolonych nadawców.
        </.alert>
      </section>

      <div :if={@tax_forecast?} class="border-bs border-grey-200 pbs-8 lg:col-span-2">
        <.live_component
          module={TaxForecastSettings}
          id="tax-forecast-settings"
          current_user={@current_user}
        />
      </div>
    </div>
    """
  end

  defp inbound_email(%{inbound_email_nickname: nickname}) when is_binary(nickname) and nickname != "" do
    "#{nickname}@firmowid.pl"
  end

  defp inbound_email(_organization), do: "—"
end
