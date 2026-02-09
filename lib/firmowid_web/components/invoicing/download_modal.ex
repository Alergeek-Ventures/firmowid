defmodule FirmowidWeb.Components.Invoicing.DownloadModal do
  @moduledoc false
  use FirmowidWeb, :live_component

  attr :month, :string, required: true

  @impl true
  def mount(socket) do
    socket = assign(socket, skip_scans: true)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <button
        id="download-button"
        phx-click={show_modal("download-modal")}
        data-tippy-content="Pobierz wszystkie faktury wystawione lub z datą sprzedaży w tym miesiącu"
        phx-hook="Tippy"
        class="relative flex flex-row gap-4 items-center justify-center
            rounded-lg px-3 py-2 max-md:hidden bg-greyButtonBg
            border-greyButtonBg hover:border-darkGrey hover:bg-darkGrey
            hover:text-white border transition-colors"
      >
        <.icon name="hero-cloud-arrow-down" class="w-6 h-6" />
        <span class="max-xl:hidden">
          Pobierz
        </span>
      </button>

      <.modal id="download-modal" on_cancel={hide_modal("download-modal")}>
        <div class="flex flex-col gap-8 p-4">
          <h3 class="text-lg font-semibold">Pobierz faktury</h3>
          <p>
            W pliku
            <span class="inline-flex items-center gap-1 bg-lightGreyBg border border-black rounded px-2 py-1">
              <.icon name="hero-document-solid" class="w-4 h-4" />
              {@month |> Calendar.strftime("%Y-%m")}-dokumenty.zip
            </span>
            znajdą się wszystkie dokumenty, których
            <span class="font-bold">data wystawienia lub sprzedaży</span>
            przypada na aktualny miesiąc.
          </p>
          <label class="flex flex-row gap-2 items-center">
            <.input
              name="skip-scans"
              phx-click="set-skip-scans"
              phx-target={@myself}
              value={@skip_scans}
              type="checkbox"
            /> Pobierz tylko cyfrowe dokumenty (pomiń zdjęcia i skany)
          </label>
          <a
            href={"/pobierz-miesiac?month=#{@month}&skip_scans=#{@skip_scans}"}
            download
            class={[
              "bg-black text-white text-center",
              "py-2 rounded-md"
            ]}
          >
            Pobierz dokumenty
          </a>
        </div>
      </.modal>
    </div>
    """
  end

  @impl true
  def handle_event("set-skip-scans", _, socket) do
    socket = assign(socket, skip_scans: !socket.assigns.skip_scans)

    {:noreply, socket}
  end
end
