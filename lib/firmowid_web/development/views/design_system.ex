defmodule FirmowidWeb.Development.Views.DesignSystem do
  @moduledoc """
  Development-only catalog of the design system: tokens and every shared primitive
  with its variants and states, rendered from the real components.

  Like the development guide, its route exists only in the development environment
  and is open to authenticated organization members.
  """
  use FirmowidWeb, :live_view

  import FirmowidUI.Components.Button
  import FirmowidUI.Components.Link
  import Phoenix.Component, except: [link: 1]

  # Dev-only route: verified routes would warn in environments without it.
  @catalog_path "/development/design-system"
  @guide_path "/development"
  @palettes ~w(grey rust teal moss brick)
  @steps ~w(50 100 200 300 400 500 600 700 800 900 950)
  @text_sizes [
    {"text-caps-sm", "11px"},
    {"text-xs", "12px"},
    {"text-sm", "14px"},
    {"text-base", "16px"},
    {"text-h5", "18px"},
    {"text-lg", "20px"},
    {"text-xl", "23px"},
    {"text-2xl", "27px"},
    {"text-3xl", "40px"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Design system",
       catalog_path: @catalog_path,
       guide_path: @guide_path,
       palettes: @palettes,
       steps: @steps,
       text_sizes: @text_sizes,
       form: to_form(%{"powiadomienia" => "true", "zgoda" => "false", "okres" => "miesiac"})
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply,
     assign(socket,
       tab: Map.get(params, "zakladka", "komponenty"),
       scope: Map.get(params, "zakres", "aktywne")
     )}
  end

  @impl true
  def handle_event("noop", _params, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto flex w-full max-w-7xl flex-col gap-12 pb-16">
      <header class="flex flex-col gap-2 pt-4">
        <h1 class="text-2xl font-semibold text-grey-900">Design system</h1>
        <p class="max-w-2xl text-sm/snug text-grey-700">
          Tokeny z <code class="font-mono">DESIGN.md</code>
          i wszystkie komponenty bazowe z wariantami. Strona renderuje prawdziwe komponenty,
          więc jest punktem odniesienia przy przeglądzie UI.
        </p>
      </header>

      <.catalog_section title="Kolory">
        <div class="flex flex-col gap-2">
          <div :for={palette <- @palettes} class="flex items-center gap-1">
            <span class="w-14 text-sm text-grey-700">{palette}</span>
            <div
              :for={step <- @steps}
              class="flex h-12 flex-1 flex-col justify-end rounded-md p-1.5 text-[10px]"
              style={"background-color: var(--color-#{palette}-#{step})"}
            >
              <span class={[
                "rounded bg-white/80 px-1 text-grey-900",
                step in ~w(50 100 200 300 400) && "bg-transparent"
              ]}>
                {step}
              </span>
            </div>
          </div>
        </div>
      </.catalog_section>

      <.catalog_section title="Typografia">
        <div class="flex flex-col gap-3">
          <div :for={{class, size} <- @text_sizes} class="flex items-baseline gap-4">
            <span class="w-40 shrink-0 font-mono text-xs text-grey-600">{class} · {size}</span>
            <span class={["text-grey-900", sample_styles(class)]}>Faktura FV/10/2026 za 4 480,00 zł</span>
          </div>
        </div>
      </.catalog_section>

      <.catalog_section title="Promienie, cienie i focus">
        <div class="flex flex-wrap gap-6">
          <div
            :for={radius <- ~w(rounded-sm rounded-md rounded-lg rounded-full)}
            class={[
              "flex size-24 items-center justify-center border border-grey-200 bg-white",
              sample_styles(radius)
            ]}
          >
            <span class="font-mono text-xs text-grey-600">{radius}</span>
          </div>
          <div class="flex size-24 items-center justify-center rounded-md bg-white shadow-card">
            <span class="font-mono text-xs text-grey-600">shadow-card</span>
          </div>
          <div class="flex size-24 items-center justify-center rounded-md bg-white shadow-lg ring-1 ring-grey-700/10">
            <span class="font-mono text-xs text-grey-600">shadow-lg</span>
          </div>
          <div class="flex items-center gap-4 rounded-lg bg-black p-4 [--focus-ring:var(--color-white)]">
            <.button type="button" variant="outline" size="small" class="border-white/30 text-white">
              Tab tutaj (ciemne tło)
            </.button>
          </div>
        </div>
      </.catalog_section>

      <.catalog_section title="Przyciski">
        <div class="flex flex-col gap-4">
          <div :for={size <- ~w(big small)} class="flex flex-wrap items-center gap-3">
            <.button type="button" size={size} variant="special">Special</.button>
            <.button type="button" size={size} variant="primary" accent="rust">Primary koszt</.button>
            <.button type="button" size={size} variant="primary" accent="teal">
              Primary sprzedaż
            </.button>
            <.button type="button" size={size} variant="secondary">Secondary</.button>
            <.button type="button" size={size} variant="secondary" accent="rust">
              Secondary koszt
            </.button>
            <.button type="button" size={size} variant="secondary" accent="teal">
              Secondary sprzedaż
            </.button>
            <.button type="button" size={size} variant="tertiary">Tertiary</.button>
            <.button type="button" size={size} variant="outline">Outline</.button>
            <.button type="button" size={size} variant="ghost">Ghost</.button>
            <.button type="button" size={size} variant="destructive">Usuń</.button>
            <.button type="button" size={size} variant="success">Zatwierdź</.button>
            <.button type="button" size={size} variant="primary" disabled>Wyłączony</.button>
          </div>
          <div class="flex flex-wrap items-center gap-3">
            <.icon_button label="Edytuj" size="small"><Lucideicons.pencil /></.icon_button>
            <.icon_button label="Edytuj" size="big"><Lucideicons.pencil /></.icon_button>
            <.icon_button label="Szukaj" variant="secondary" size="big">
              <Lucideicons.search />
            </.icon_button>
            <.icon_button label="Pobierz" variant="outline"><Lucideicons.download /></.icon_button>
            <.menu id="catalog-menu" label="Więcej akcji">
              <.menu_item navigate={@catalog_path}>
                <Lucideicons.pencil /> Edytuj
              </.menu_item>
              <.menu_item phx-click="noop"><Lucideicons.archive /> Archiwizuj</.menu_item>
              <.menu_item phx-click="noop" tone="danger"><Lucideicons.trash_2 /> Usuń</.menu_item>
            </.menu>
          </div>
        </div>
      </.catalog_section>

      <.catalog_section title="Odznaki i komunikaty">
        <div class="flex flex-col gap-4">
          <div class="flex flex-wrap gap-2">
            <.badge>szkic</.badge>
            <.badge tone="success">opłacona</.badge>
            <.badge tone="danger">po terminie</.badge>
            <.badge tone="cost">koszt</.badge>
            <.badge tone="sales">sprzedaż</.badge>
          </div>
          <.alert title="Synchronizacja z KSeF trwa">
            Nowe faktury pojawią się na liście w ciągu kilku minut.
          </.alert>
          <.alert tone="success" title="Faktura wysłana">Klient dostał fakturę e-mailem.</.alert>
          <.alert tone="danger" title="Nie udało się połączyć z bankiem">
            Odnów zgodę w ustawieniach banku.
            <:actions>
              <.button type="button" size="small" variant="outline">Odnów zgodę</.button>
            </:actions>
          </.alert>
          <.empty_state title="Brak projektów w tym miesiącu">
            <:icon><Lucideicons.presentation /></:icon>
            Dodaj projekt, żeby przypisywać do niego godziny i koszty.
            <:action>
              <.button type="button" variant="secondary"><Lucideicons.plus /> Dodaj projekt</.button>
            </:action>
          </.empty_state>
        </div>
      </.catalog_section>

      <.catalog_section title="Nawigacja">
        <div class="flex flex-col gap-6">
          <.tabs label="Sekcje katalogu">
            <:tab
              patch={"#{@catalog_path}?zakladka=komponenty"}
              active={@tab == "komponenty"}
            >
              Komponenty
            </:tab>
            <:tab patch={"#{@catalog_path}?zakladka=tokeny"} active={@tab == "tokeny"}>
              Tokeny
            </:tab>
            <:tab patch={"#{@catalog_path}?zakladka=wzorce"} active={@tab == "wzorce"}>
              Wzorce
            </:tab>
          </.tabs>
          <.segmented_control label="Zakres listy">
            <:option
              patch={"#{@catalog_path}?zakres=aktywne"}
              active={@scope == "aktywne"}
            >
              Aktywne
            </:option>
            <:option
              patch={"#{@catalog_path}?zakres=zarchiwizowane"}
              active={@scope == "zarchiwizowane"}
            >
              Zarchiwizowane
            </:option>
          </.segmented_control>
        </div>
      </.catalog_section>

      <.catalog_section title="Formularze">
        <.form for={@form} phx-change="noop" class="grid max-w-3xl gap-6 md:grid-cols-2">
          <.search_field name="szukaj" placeholder="Szukaj kontrahenta" />
          <.search_field name="szukaj_maly" placeholder="Szukaj (mały)" size="small" />
          <.field_row label="Nazwa projektu" for="catalog-name">
            <.input id="catalog-name" name="nazwa" value="" new placeholder="np. Firmowid" />
          </.field_row>
          <.field_row label="NIP" layout="inline">
            <span class="font-mono">6161525811</span>
          </.field_row>
          <.switch field={@form[:powiadomienia]} label="Powiadomienia e-mail" />
          <.switch field={@form[:powiadomienia]} label="Sprzedaż" color="teal" />
          <.input type="checkbox" field={@form[:zgoda]} label="Akceptuję regulamin" />
          <.radio_group field={@form[:okres]}>
            <:radio value="miesiac">Miesiąc</:radio>
            <:radio value="rok">Rok</:radio>
          </.radio_group>
          <.tooltip id="catalog-tooltip" text="Kwota netto bez VAT">
            <span class="text-sm text-grey-700 underline decoration-dotted">4 480,00 zł</span>
          </.tooltip>
        </.form>
      </.catalog_section>

      <.catalog_section title="Karta">
        <div class="grid max-w-3xl gap-6 md:grid-cols-2">
          <.card>
            <.card_header>
              Dane firmy
              <:actions>
                <.icon_button label="Edytuj dane firmy"><Lucideicons.pencil /></.icon_button>
              </:actions>
            </.card_header>
            <.field_row label="Nazwa">Bytecraft Collective sp. z o.o.</.field_row>
          </.card>
        </div>
      </.catalog_section>

      <.link navigate={@guide_path} kind="text">Wróć do przewodnika deweloperskiego</.link>
    </div>
    """
  end

  # Token classes shown in the catalog are literals in this module, so Tailwind sees them.
  defp sample_styles(token_class), do: token_class

  attr :title, :string, required: true
  slot :inner_block, required: true

  defp catalog_section(assigns) do
    ~H"""
    <section class="flex flex-col gap-4">
      <h2 class="text-lg font-semibold text-grey-900">{@title}</h2>
      {render_slot(@inner_block)}
    </section>
    """
  end
end
