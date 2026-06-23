defmodule FirmowidWeb.Invoicing.Components.InvoiceDownloadModal do
  @moduledoc false
  use FirmowidWeb, :live_component

  alias FirmowidWeb.Invoicing.Utilities.Navigation

  attr :download_path, :string, required: true
  attr :button_label, :string, required: true
  attr :trigger_variant, :string, default: "secondary"
  attr :trigger_size, :string, default: "small"

  @impl true
  def mount(socket) do
    {:ok, assign(socket, include_internal_note: true)}
  end

  @impl true
  def render(assigns) do
    modal_id = "invoice-download-modal-#{assigns.id}"

    switch_form =
      to_form(%{"include_internal_note" => assigns.include_internal_note}, as: :download)

    assigns = assign(assigns, modal_id: modal_id, switch_form: switch_form)

    ~H"""
    <div>
      <FirmowidWeb.DesignSystem.Components.Button.button
        type="button"
        variant={@trigger_variant}
        size={@trigger_size}
        phx-click={show_modal(@modal_id)}
      >
        <Lucideicons.download />
        <span class="hidden xl:inline">{@button_label}</span>
      </FirmowidWeb.DesignSystem.Components.Button.button>

      <.modal id={@modal_id} on_cancel={hide_modal(@modal_id)}>
        <div class="flex flex-col gap-6 p-1">
          <div>
            <h3 class="text-lg font-semibold">Pobierz PDF</h3>
            <p class="mt-2 text-sm text-neutral-600">
              Wybierz, czy dołączyć stronę z komentarzem wewnętrznym.
            </p>
          </div>

          <.form
            for={@switch_form}
            id={"#{@modal_id}-note-filter-form"}
            phx-change="toggle-note-filter"
            phx-target={@myself}
          >
            <.switch
              field={@switch_form[:include_internal_note]}
              label="Dołącz komentarz wewnętrzny"
            />
          </.form>

          <div class="flex justify-end gap-3">
            <FirmowidWeb.DesignSystem.Components.Button.button
              type="button"
              id={"download-btn-#{@id}"}
              phx-hook="DownloadPdf"
              data-download-url={Navigation.pdf_download_path(@download_path, @include_internal_note)}
              data-modal-id={@modal_id}
            >
              <span data-download-idle>Pobierz</span>
              <span data-download-loading class="hidden items-center gap-2">
                <Lucideicons.loader_circle class="size-4 animate-spin" /> Generowanie PDF…
              </span>
            </FirmowidWeb.DesignSystem.Components.Button.button>
          </div>
        </div>
      </.modal>
    </div>
    """
  end

  @impl true
  def handle_event("toggle-note-filter", %{"download" => %{"include_internal_note" => value}}, socket) do
    {:noreply, assign(socket, include_internal_note: value == "true")}
  end
end
