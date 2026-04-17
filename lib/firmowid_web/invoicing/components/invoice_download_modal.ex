defmodule FirmowidWeb.Invoicing.Components.InvoiceDownloadModal do
  @moduledoc false
  use FirmowidWeb, :live_component

  attr :download_path, :string, required: true
  attr :button_class, :any, required: true
  attr :button_label, :string, required: true

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
      <button type="button" class={@button_class} phx-click={show_modal(@modal_id)}>
        <Lucideicons.download />
        <span class="hidden xl:inline">{@button_label}</span>
      </button>

      <.modal id={@modal_id} on_cancel={hide_modal(@modal_id)}>
        <div class="flex flex-col gap-6 p-1">
          <div>
            <h3 class="text-lg font-semibold">Pobierz PDF</h3>
            <p class="mt-2 text-sm text-neutral-600">
              Wybierz, czy dołączyć stronę z komentarzem wewnętrznym.
            </p>
          </div>

          <.form for={@switch_form} phx-change="toggle-note-filter" phx-target={@myself}>
            <.switch
              field={@switch_form[:include_internal_note]}
              label="Dołącz komentarz wewnętrzny"
            />
          </.form>

          <div class="flex justify-end gap-3">
            <button
              type="button"
              id={"download-btn-#{@id}"}
              phx-hook="DownloadPdf"
              data-download-path={@download_path}
              data-include-note={to_string(@include_internal_note)}
              data-modal-id={@modal_id}
              class={["js-download-button", button_styles()]}
            >
              <span data-download-idle>Pobierz</span>
              <span data-download-loading class="hidden items-center gap-2">
                <Lucideicons.loader_circle class="size-4 animate-spin" /> Generowanie PDF…
              </span>
            </button>
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
