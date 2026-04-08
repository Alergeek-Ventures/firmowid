defmodule FirmowidWeb.Invoicing.Components.DownloadModal do
  @moduledoc false
  use FirmowidWeb, :live_component

  attr :month, :any, required: true

  @impl true
  def mount(socket) do
    socket =
      assign(socket,
        include_digital: true,
        include_ksef: false,
        include_photos: false,
        include_sales: true
      )

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :any_selected, any_selected?(assigns))

    ~H"""
    <div>
      <button
        id="download-button"
        phx-click={show_modal("download-modal")}
        data-tippy-content="Pobierz wszystkie faktury wystawione lub z datą sprzedaży w tym miesiącu"
        phx-hook="Tippy"
        class="bg-greyButtonBg border-greyButtonBg hover:bg-darkGrey hover:border-darkGrey relative flex flex-row items-center justify-center gap-4 rounded-lg border px-3 py-2 transition-colors hover:text-white max-md:hidden"
      >
        <span aria-hidden="true"><.icon name="hero-cloud-arrow-down" class="size-6" /></span>
        <span class="max-xl:hidden">
          Pobierz
        </span>
      </button>

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
              label="Dokumenty cyfrowe (PDF)"
              checked={@include_digital}
              myself={@myself}
            />
            <.filter_checkbox
              name="include_ksef"
              label="Dokumenty z KSeF (XML)"
              checked={@include_ksef}
              myself={@myself}
            />
            <.filter_checkbox
              name="include_photos"
              label="Zdjęcia i skany dokumentów"
              checked={@include_photos}
              myself={@myself}
            />
            <.filter_checkbox
              name="include_sales"
              label="Faktury sprzedażowe"
              checked={@include_sales}
              myself={@myself}
            />
          </div>
          <a
            href={download_href(@month, assigns)}
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
          </a>
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
        include_sales: assigns.include_sales
      )

    "/pobierz-miesiac?#{params}"
  end
end
