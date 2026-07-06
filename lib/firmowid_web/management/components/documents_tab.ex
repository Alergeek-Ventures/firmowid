defmodule FirmowidWeb.Management.Components.DocumentsTab do
  @moduledoc "LiveComponent for managing employee documents, uploads, and processing status."
  use FirmowidWeb, :live_component

  import FirmowidWeb.DesignSystem.Components.Button
  import FirmowidWeb.DesignSystem.Components.Link
  import FirmowidWeb.Management.Components.Card
  import Phoenix.Component, except: [link: 1]

  alias Firmowid.Ash.Blobs
  alias Firmowid.Ash.Blobs.Blob
  alias Firmowid.Ash.Payroll
  alias Firmowid.Ash.Timetracker.HoursRecord
  alias FirmowidWeb.Infrastructure.Utilities.TimeFormatter

  require Logger

  @impl true
  def mount(socket) do
    socket =
      socket
      |> assign(:search, "")
      |> assign(:type_filter, nil)
      |> allow_upload(:document_upload,
        accept: ~w(.pdf .doc .docx),
        max_entries: 1,
        auto_upload: true,
        progress: &handle_progress/3
      )

    {:ok, socket}
  end

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(Map.delete(assigns, :refetch))
      |> refetch_documents()
      |> refetch_upload_counts()

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex h-full min-h-0 flex-col">
      <.card class="relative z-10 flex h-full min-h-0 flex-col" dimmed={@employee.archived_at}>
        <div class="shrink-0">
          <.card_header>
            <div class="flex items-center justify-between">
              Przesłane dokumenty
              <div class="flex items-center gap-4">
                <form class="flex gap-4" phx-submit="search" phx-target={@myself}>
                  <div
                    id="search-container"
                    data-expanded={to_string(@search != "")}
                    class="data-[expanded=true]:bg-greyButtonBg group flex items-center justify-center rounded-lg transition-shadow data-[expanded=true]:focus-within:ring-2"
                  >
                    <.input
                      type="text"
                      name="szukaj"
                      value={@search}
                      placeholder="Szukaj dokumentu"
                      phx-change="search"
                      phx-debounce="300"
                      phx-target={@myself}
                      input_class="py-0 px-1 bg-transparent border-none"
                      class="w-0 border-transparent px-0 opacity-0 transition-[width,opacity,padding] duration-200 ease-in-out group-data-[expanded=true]:w-64 group-data-[expanded=true]:px-2 group-data-[expanded=true]:py-1 group-data-[expanded=true]:opacity-100 focus:border-none focus:ring-0 focus:outline-hidden"
                    />
                    <.button
                      type="button"
                      size="small"
                      phx-click={
                        JS.toggle_attribute({"data-expanded", "true", "false"},
                          to: "#search-container"
                        )
                        |> JS.focus(to: "#search-container input")
                      }
                      variant="outline"
                      class="py-2"
                    >
                      <Lucideicons.search />
                    </.button>
                  </div>
                </form>
                <form class="relative" phx-submit="upload" phx-change="upload" phx-target={@myself}>
                  <.live_file_input
                    upload={@uploads.document_upload}
                    class="peer sr-only"
                    aria-label="Wgraj dokument"
                  />

                  <.button
                    as="label"
                    variant="secondary"
                    size="small"
                    class="relative py-1.75"
                    type="button"
                    for={@uploads.document_upload.ref}
                  >
                    <.upload_indicator
                      currently_uploading_count={@currently_uploading_count}
                      processing_blobs_count={@processing_blobs_count}
                    />
                    <.icon name="hero-plus" class="size-4" /> Dodaj umowe
                  </.button>
                </form>
              </div>
            </div>
            <div class="flex items-center gap-3 pt-6">
              <span class="text-darkGrey/70 text-sm font-normal">Filtry:</span>

              <div class="flex flex-wrap items-center gap-2">
                <.button
                  class="font-normal"
                  type="button"
                  variant="filter"
                  data-active={@type_filter == "hours_record"}
                  phx-click="toggle_type"
                  phx-value-typ={:hours_record}
                  phx-target={@myself}
                >
                  <.icon name="hero-clock" class="size-4" /> ewidencja
                </.button>

                <.button
                  class="font-normal"
                  type="button"
                  variant="filter"
                  data-active={@type_filter == "employment_contract"}
                  phx-click="toggle_type"
                  phx-value-typ={:employment_contract}
                  phx-target={@myself}
                >
                  <.icon name="hero-document" class="size-4" /> umowa
                </.button>

                <.button
                  class="font-normal"
                  type="button"
                  variant="filter"
                  data-active={@type_filter == "other"}
                  phx-click="toggle_type"
                  phx-value-typ={:other}
                  phx-target={@myself}
                >
                  <.icon name="hero-ellipsis-horizontal" class="size-4" /> inne
                </.button>
              </div>
            </div>
          </.card_header>
        </div>

        <div class="relative w-full flex-1">
          <div class="scrollbar-card absolute inset-0 space-y-2 overflow-y-auto pr-2">
            <%= if Enum.empty?(@documents) do %>
              <div class="text-darkGrey mt-4 text-sm">Brak dokumentów</div>
            <% else %>
              <%= for document <- @documents do %>
                <.document_element document={document} />
              <% end %>
            <% end %>
          </div>
        </div>
      </.card>
    </div>
    """
  end

  def document_element(assigns) do
    ~H"""
    <.link
      kind="unstyled"
      navigate={@document.url}
      download={@document.file_name}
      class="group flex items-center justify-between gap-4 rounded-md px-2 py-2.5 transition"
    >
      <div class="flex items-center gap-3">
        <div class="bg-grey-100 flex size-7 items-center justify-center rounded-md">
          <%= case @document.type do %>
            <% :hours_record -> %>
              <.icon name="hero-clock" class="text-darkGrey size-5" />
            <% :employment_contract -> %>
              <.icon name="hero-document" class="text-darkGrey size-5" />
            <% _ -> %>
              <.icon name="hero-ellipsis-horizontal" class="text-darkGrey size-5" />
          <% end %>
        </div>
        <div class="group-hover:underline">
          {@document.name}
        </div>
      </div>

      <div class="text-darkGrey text-sm">
        {TimeFormatter.format_date(@document.date)}
      </div>
    </.link>
    """
  end

  @impl true
  def handle_event("search", %{"szukaj" => search}, socket) do
    {:noreply,
     socket
     |> assign(:search, search)
     |> refetch_documents()}
  end

  def handle_event("toggle_type", %{"typ" => type}, socket) do
    type = if socket.assigns.type_filter == type, do: nil, else: type

    {:noreply,
     socket
     |> assign(:type_filter, type)
     |> refetch_documents()}
  end

  def handle_event("validate_upload", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("upload", _params, socket) do
    socket = refetch_upload_counts(socket)
    {:noreply, socket}
  end

  defp refetch_documents(socket) do
    documents =
      build_documents(
        socket.assigns.employee.id,
        socket.assigns.scope,
        %{
          search: socket.assigns.search,
          type_filter: socket.assigns.type_filter
        }
      )

    assign(socket, :documents, documents)
  end

  defp refetch_upload_counts(socket) do
    currently_uploading_count =
      case socket.assigns do
        %{uploads: %{document_upload: upload}} ->
          length(Enum.filter(upload.entries, &(!&1.done?)))

        _ ->
          0
      end

    count = Blobs.get_processing_blobs_count(:employment_contract, socket.assigns.scope)

    socket
    |> assign(:processing_blobs_count, count)
    |> assign(:currently_uploading_count, currently_uploading_count)
  end

  defp build_documents(user_id, scope, filters) do
    %{search: search, type_filter: type_filter} = filters

    hours_record_docs =
      HoursRecord
      |> Ash.Query.for_read(:list, %{user_id: user_id}, scope: scope)
      |> Ash.read!(scope: scope)
      |> Enum.map(fn doc ->
        %{
          id: doc.id,
          type: :hours_record,
          name: "Ewidencja #{String.pad_leading(Integer.to_string(doc.month), 2, "0")}.#{doc.year}",
          date: doc.inserted_at,
          url: ~p"/czasosledz/ewidencja/#{doc.id}",
          file_name: "Ewidencja_#{doc.year}_#{doc.month}.pdf"
        }
      end)

    employment_contract_docs =
      user_id
      |> Payroll.list_employment_contracts!(scope: scope)
      |> Enum.map(fn doc ->
        %{
          id: doc.id,
          type: :employment_contract,
          name: "Umowa o pracę #{doc.starts_at}",
          date: doc.starts_at,
          url: ~p"/zarzadzanie/umowy/#{doc.id}",
          file_name: "Umowa_#{doc.worker_full_name}_#{doc.starts_at}.pdf"
        }
      end)

    other_docs = []

    case_result =
      case type_filter do
        "hours_record" -> hours_record_docs
        "employment_contract" -> employment_contract_docs
        "other" -> other_docs
        _ -> hours_record_docs ++ other_docs ++ employment_contract_docs
      end

    documents =
      case_result
      |> Enum.filter(fn doc ->
        doc[:name] |> String.downcase() |> String.contains?(String.downcase(search))
      end)
      |> Enum.sort_by(
        fn doc ->
          case doc[:date] do
            %DateTime{} = dt -> DateTime.to_date(dt)
            %Date{} = d -> d
          end
        end,
        {:desc, Date}
      )

    documents
  end

  defp handle_progress(name, _params, socket) do
    socket =
      case uploaded_entries(socket, name) do
        {[_ | _] = entries, []} ->
          handle_uploads(entries, socket)
          refetch_upload_counts(socket)

        _ ->
          socket
      end

    {:noreply, socket}
  end

  defp handle_uploads(entries, socket) do
    scope = socket.assigns.scope

    Enum.each(entries, fn entry ->
      case consume_uploaded_entry(socket, entry, fn %{path: path} ->
             {:ok,
              Blobs.create_blob_for_processing(
                path,
                entry.client_type,
                entry.client_name,
                :employment_contract,
                %{user_id: socket.assigns.employee_id},
                scope: scope
              )}
           end) do
        {:ok, %Blob{}} ->
          LiveToast.send_toast(:success, "Plik został wysłany.")

        {:error, err} ->
          Logger.warning("Upload failed: #{inspect(err)}")
          LiveToast.send_toast(:error, "Wystąpił błąd podczas wysyłania pliku.")
      end
    end)

    :ok
  end

  defp upload_indicator(%{currently_uploading_count: 0, processing_blobs_count: 0} = assigns) do
    ~H"""
    """
  end

  defp upload_indicator(assigns) do
    ~H"""
    <span
      id="upload-count-indicator"
      phx-hook="Tippy"
      data-tippy-content="Pliki są przetwarzane i za kilka chwil będą dostępne w Firmowidzie"
      class="bg-lightGreyBg absolute -top-3.5 -right-3.5 flex size-7 items-center justify-center overflow-hidden rounded-full"
    >
      <span class="absolute block size-full animate-pulse bg-orange-600" />
      <span class="bg-lightGreyBg z-10 flex size-5 items-center justify-center rounded-full">
        <.upload_indicator_icon
          currently_uploading_count={@currently_uploading_count}
          processing_blobs_count={@processing_blobs_count}
        />
      </span>
    </span>
    """
  end

  defp upload_indicator_icon(%{currently_uploading_count: count} = assigns) when count > 0 do
    ~H"""
    <Lucideicons.arrow_up class="size-4 leading-none text-orange-900" />
    """
  end

  defp upload_indicator_icon(%{processing_blobs_count: 1} = assigns) do
    ~H"""
    <.icon name="hero-arrow-up-circle-solid" class="size-5 leading-none text-white" />
    """
  end

  defp upload_indicator_icon(%{processing_blobs_count: 0} = assigns) do
    ~H"""
    """
  end

  defp upload_indicator_icon(assigns) do
    ~H"""
    <span>{@processing_blobs_count}</span>
    """
  end
end
