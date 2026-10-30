defmodule FirmowidWeb.Invoicing.Components.DownloadModal do
  @moduledoc false
  use FirmowidWeb, :live_component

  import FirmowidUI.Components.Link
  import Phoenix.Component, except: [link: 1]

  alias FirmowidWeb.Invoicing.Utilities.Navigation

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

    intro_parts =
      "The file %{file} will contain all documents whose %{dates} falls in the current month."
      |> gettext(file: "__FILE__", dates: "__DATES__")
      |> String.split(~r/__FILE__|__DATES__/, include_captures: true)

    assigns = assign(assigns, :intro_parts, intro_parts)

    ~H"""
    <div class="max-md:hidden">
      <FirmowidUI.Components.Button.button
        id="download-button"
        type="button"
        variant="secondary"
        phx-click={show_modal("download-modal")}
        data-tippy-content={gettext("Download all invoices issued or with a sale date in this month")}
        phx-hook="Tippy"
        class="relative"
      >
        <Lucideicons.file_down />
        <span class="max-xl:sr-only">
          {gettext("Download")}
        </span>
      </FirmowidUI.Components.Button.button>

      <.modal id="download-modal" on_cancel={hide_modal("download-modal")}>
        <div class="flex flex-col gap-8 p-4">
          <h3 class="text-lg font-semibold text-balance">{gettext("Download invoices")}</h3>
          <p class="text-pretty">
            <.intro_part :for={part <- @intro_parts} part={part} month={@month} />
          </p>
          <div class="flex flex-col gap-3">
            <.filter_checkbox
              name="include_digital"
              label={gettext("Uploaded digital documents (PDF)")}
              checked={@include_digital}
              myself={@myself}
            />
            <.filter_checkbox
              name="include_sales"
              label={pgettext("invoice download option", "Sales invoices")}
              checked={@include_sales}
              myself={@myself}
            />
            <.filter_checkbox
              name="include_ksef"
              label={gettext("Cost invoices from KSeF (PDF generated from KSeF data)")}
              checked={@include_ksef}
              myself={@myself}
            />
            <.filter_checkbox
              name="include_photos"
              label={gettext("Photos and scans of documents")}
              checked={@include_photos}
              myself={@myself}
            />
          </div>

          <div class="border-t border-grey-100 pt-4">
            <.form
              for={@switch_form}
              id="download-modal-note-filter-form"
              phx-change="toggle-note-filter"
              phx-target={@myself}
            >
              <.switch
                field={@switch_form[:include_internal_note]}
                label={gettext("Include internal comments in generated PDFs")}
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
                do: "cursor-pointer bg-black text-white hover:bg-grey-700",
                else: "pointer-events-none bg-grey-200 text-grey-600"
              )
            ]}
            aria-disabled={if(!@any_selected, do: "true")}
            tabindex={if(!@any_selected, do: "-1")}
          >
            {gettext("Download documents")}
          </.link>
        </div>
      </.modal>
    </div>
    """
  end

  attr :part, :string, required: true
  attr :month, :any, required: true

  defp intro_part(%{part: "__FILE__"} = assigns) do
    ~H"""
    <span class="inline-flex items-center gap-1 rounded border border-black bg-grey-100 px-2 py-1">
      <span aria-hidden="true"><.icon name="hero-document-solid" class="size-4" /></span>
      {@month |> Calendar.strftime("%Y-%m")}-dokumenty.zip
    </span>
    """
  end

  defp intro_part(%{part: "__DATES__"} = assigns) do
    ~H"""
    <span class="font-bold">{gettext("issue or sale date")}</span>
    """
  end

  defp intro_part(assigns), do: ~H"{@part}"

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
    Navigation.month_download_path(month, assigns)
  end
end
