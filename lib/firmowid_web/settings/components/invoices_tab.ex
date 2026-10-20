defmodule FirmowidWeb.Settings.Components.InvoicesTab do
  @moduledoc """
  Function components for invoice e-mail import settings.
  """

  use FirmowidWeb, :html

  import FirmowidUI.Components.Button

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

          <span class="rounded-full bg-orange-100 px-3 py-1 text-sm/tight text-orange-700">
            aktywny
          </span>
        </div>

        <.settings_row label="Adres odbiorczy">
          <div class="flex flex-col gap-3 sm:flex-row sm:items-center">
            <.button
              type="button"
              variant="secondary"
              accent="orange"
              size="small"
              phx-click="copy_inbound_email"
              phx-value-email={@inbound_email}
              class="w-full max-w-sm justify-between text-left sm:w-80"
            >
              <span class="min-w-0 truncate">{@inbound_email}</span>
              <.icon name="hero-envelope" class="size-4 shrink-0" />
            </.button>

            <span
              :if={@admin?}
              id="settings-regenerate-inbound-email-tooltip"
              phx-hook="Tippy"
              data-tippy-content="Wygeneruje nowy adres importu. Zaktualizuj reguły przekazywania poczty po zmianie."
              data-tippy-delay="100"
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
            </span>
          </div>
        </.settings_row>

        <div class="rounded-lg bg-grey-50 p-4 text-base leading-[1.4] text-grey-700">
          <div class="flex gap-4">
            <.icon name="hero-information-circle" class="mt-0.5 size-5 shrink-0 text-grey-600" />
            <p>
              Wysyłaj faktury kosztowe na ten adres. Firmowid zaimportuje je automatycznie,
              ale przyjmie tylko wiadomości z adresów dodanych do listy dozwolonych nadawców.
            </p>
          </div>
        </div>
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
          <p
            :if={Enum.empty?(@allowed_sender_emails)}
            class="rounded-lg bg-grey-50 px-4 py-3 text-sm leading-[1.35] text-grey-700"
          >
            Nie dodano jeszcze żadnych adresów. Import zadziała dopiero po dodaniu pierwszego nadawcy.
          </p>

          <div
            :for={email <- @allowed_sender_emails}
            class="flex min-h-11 items-center justify-between gap-3 rounded-lg bg-turquoise-100 px-3 py-2 text-sm leading-[1.35] text-turquoise-800 sm:min-h-10"
          >
            <span class="min-w-0 truncate">{email}</span>
            <.button
              :if={@admin?}
              type="button"
              variant="ghost"
              size="small"
              phx-click="remove_allowed_email"
              phx-value-email={email}
              class="size-10 shrink-0 p-0 text-turquoise-800 hover:bg-turquoise-200 hover:text-grey-900"
              aria-label={"Usuń #{email}"}
            >
              <.icon name="hero-x-mark" class="size-4" />
            </.button>
          </div>
        </div>

        <form :if={@admin?} phx-submit="add_allowed_email" class="space-y-3">
          <.settings_row label="Dodaj nowy adres" for="allowed_sender_email">
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
          </.settings_row>
        </form>

        <div
          :if={!@admin?}
          class="rounded-lg bg-grey-50 px-4 py-3 text-sm leading-[1.35] text-grey-700"
        >
          Tylko administrator może zmieniać adres odbiorczy i listę dozwolonych nadawców.
        </div>
      </section>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :for, :any, default: nil
  slot :inner_block, required: true

  defp settings_row(assigns) do
    ~H"""
    <div class="flex flex-col gap-1">
      <label for={@for} class="text-sm leading-[1.35] text-grey-700">{@label}</label>
      <div class="min-w-0">{render_slot(@inner_block)}</div>
    </div>
    """
  end

  defp inbound_email(%{inbound_email_nickname: nickname}) when is_binary(nickname) and nickname != "" do
    "#{nickname}@firmowid.pl"
  end

  defp inbound_email(_organization), do: "—"
end
