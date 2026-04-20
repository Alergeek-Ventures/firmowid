defmodule FirmowidWeb.Invoicing.Components.DownloadModal do
  @moduledoc false
  use FirmowidWeb, :live_component

  import FirmowidWeb.DesignSystem.Components.Link
  import Phoenix.Component, except: [link: 1]

  attr :month, :any, required: true

  @impl true
  def mount(socket) do
    socket =
      assign(socket,
        include_digital: true,
        include_ksef: false,
        include_photos: false,
        include_sales: true,
        include_internal_note: true
      )

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    switch_form =
      to_form(%{"include_internal_note" => assigns.include_internal_note}, as: :download)

    assigns = assign(assigns, :any_selected, any_selected?(assigns))
    assigns = assign(assigns, :switch_form, switch_form)

    ~H"""
    <div>
      <FirmowidWeb.DesignSystem.Components.Button.button
        id="download-button"
        type="button"
        variant="secondary"
        phx-click={show_modal("download-modal")}
        data-tippy-content="Pobierz wszystkie faktury wystawione lub z datą sprzedaży w tym miesiącu"
        phx-hook="Tippy"
        class="relative max-md:hidden"
      >
        <Lucideicons.file_down />
        <span class="max-xl:hidden">
          Pobierz
        </span>
      </FirmowidWeb.DesignSystem.Components.Button.button>

      <.modal id="download-modal" on_cancel={hide_modal("download-modal")}>
        <div class="flex flex-col gap-8 p-4">
          <h3 class="text-lg font-semibold text-balance">Pobierz faktury</h3>
          <p class="text-pretty">
            W pliku
            <span class="bg-lightGreyBg inline-flex items-center gap-1 rounded border border-black px-2 py-1">
              <span aria-hidden="true"><.icon name="hero-document-solid" class="size-4" /></span>
              {@month |> Calendar.strftime("%Y-%m")}-dokumenty.zip
            </span>
            znajdą się wszystkie dokumenty, których
            <span class="font-bold">data wystawienia lub sprzedaży</span>
            przypada na aktualny miesiąc.
          </p>
          <div class="flex flex-col gap-3">
            <.filter_checkbox
              name="include_digital"
              label="Wgrane dokumenty cyfrowe (PDF)"
              checked={@include_digital}
              myself={@myself}
            />
            <.filter_checkbox
              name="include_sales"
              label="Faktury sprzedażowe"
              checked={@include_sales}
              myself={@myself}
            />
            <.filter_checkbox
              name="include_ksef"
              label="Kosztowe z KSeF (PDF generowane z danych KSeF)"
              checked={@include_ksef}
              myself={@myself}
            />
            <.filter_checkbox
              name="include_photos"
              label="Zdjęcia i skany dokumentów"
              checked={@include_photos}
              myself={@myself}
            />
          </div>

          <div class="border-lightGreyBg border-t pt-4">
            <.form for={@switch_form} phx-change="toggle-note-filter" phx-target={@myself}>
              <.switch
                field={@switch_form[:include_internal_note]}
                label="Dołącz komentarze wewnętrzne do generowanych PDF-ów"
              />
            </.form>
          </div>

          <.link
            kind="unstyled"
            navigate={download_href(@month, assigns)}
            download
            class={[
              "rounded-md py-2 text-center transition-colors",
              if(@any_selected,
                do: "cursor-pointer bg-black text-white hover:bg-gray-800",
                else: "pointer-events-none bg-gray-300 text-gray-500"
              )
            ]}
            aria-disabled={if(!@any_selected, do: "true")}
            tabindex={if(!@any_selected, do: "-1")}
          >
            Pobierz dokumenty
          </.link>
        </div>
      </.modal>
    </div>
    """
  end

  attr :name, :string, required: true
  attr :label, :string, required: true
  attr :checked, :boolean, required: true
  attr :myself, :any, required: true

  defp filter_checkbox(assigns) do
    ~H"""
    <.input
      name={@name}
      label={@label}
      phx-click="toggle-filter"
      phx-value-filter={@name}
      phx-target={@myself}
      value={@checked}
      type="checkbox"
    />
    """
  end

  @filter_keys ~w(include_digital include_ksef include_photos include_sales)

  @impl true
  def handle_event("toggle-filter", %{"filter" => filter}, socket) when filter in @filter_keys do
    key = String.to_existing_atom(filter)
    {:noreply, assign(socket, [{key, !socket.assigns[key]}])}
  end

  def handle_event("toggle-filter", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle-note-filter", %{"download" => %{"include_internal_note" => value}}, socket) do
    {:noreply, assign(socket, include_internal_note: value == "true")}
  end

  def handle_event("toggle-note-filter", _params, socket) do
    {:noreply, socket}
  end

  defp any_selected?(assigns) do
    assigns.include_digital || assigns.include_ksef || assigns.include_photos ||
      assigns.include_sales
  end

  defp download_href(month, assigns) do
    params =
      URI.encode_query(
        month: month,
        include_digital: assigns.include_digital,
        include_ksef: assigns.include_ksef,
        include_photos: assigns.include_photos,
        include_sales: assigns.include_sales,
        include_internal_note: assigns.include_internal_note
      )

    "/pobierz-miesiac?#{params}"
  end
end
