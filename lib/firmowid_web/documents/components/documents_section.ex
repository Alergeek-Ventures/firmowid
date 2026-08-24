defmodule FirmowidWeb.Documents.Components.DocumentsSection do
  @moduledoc "LiveComponent for listing, filtering, and uploading user documents."
  use FirmowidWeb, :live_component

  import FirmowidWeb.DesignSystem.Components.Button
  import FirmowidWeb.DesignSystem.Components.Link
  import Phoenix.Component, except: [link: 1]

  alias Firmowid.Ash.Blobs
  alias Firmowid.Ash.Blobs.Blob
  alias Firmowid.Ash.Payroll
  alias Firmowid.Ash.Timetracker
  alias FirmowidWeb.Infrastructure.Utilities.TimeFormatter

  require Logger

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:search, "")
     |> assign(:type_filter, nil)
     |> assign(:can_upload?, false)}
  end

  @impl true
  def update(assigns, socket) do
    can_upload? = admin_actor?(assigns.scope)

    socket =
      socket
      |> assign(Map.delete(assigns, :refetch))
      |> assign_new(:dimmed, fn -> false end)
      |> assign_new(:variant, fn -> :management end)
      |> assign(:can_upload?, can_upload?)
      |> maybe_allow_document_upload(can_upload?)
      |> refetch_documents()
      |> refetch_upload_counts()

    {:ok, socket}
  end

  defp maybe_allow_document_upload(socket, true) do
    if document_upload_allowed?(socket) do
      socket
    else
      allow_upload(socket, :document_upload,
        accept: ~w(.pdf .doc .docx),
        max_entries: 1,
        auto_upload: true,
        progress: &handle_progress/3
      )
    end
  end

  defp maybe_allow_document_upload(socket, false), do: socket

  defp document_upload_allowed?(socket) do
    uploads = socket.assigns[:uploads] || %{}
    Map.has_key?(uploads, :document_upload)
  end

  attr :variant, :atom, default: :management
  attr :class, :string, default: ""

  @impl true
  def render(assigns) do
    document_upload =
      assigns
      |> Map.get(:uploads, %{})
      |> Map.get(:document_upload)

    assigns =
      assigns
      |> assign(:profile?, assigns.variant == :profile)
      |> assign(:search_input_styles, search_input_styles(assigns.variant))
      |> assign(:document_upload, document_upload)

    ~H"""
    <div class={outer_styles(@variant)}>
      <section class={[
        section_styles(@variant),
        @dimmed && "opacity-60",
        @class
      ]}>
        <div class={header_wrapper_styles(@variant)}>
          <%= if @profile? do %>
            <div class="flex items-start justify-between gap-3">
              <h2 class="text-grey-900 text-base leading-none font-medium">Przesłane dokumenty</h2>
              <.toolbar
                id={@id}
                myself={@myself}
                search={@search}
                search_input_styles={@search_input_styles}
                can_upload?={@can_upload?}
                document_upload={@document_upload}
                currently_uploading_count={@currently_uploading_count}
                processing_blobs_count={@processing_blobs_count}
              />
            </div>
          <% else %>
            <h3 class="text-grey-900 text-base/tight font-medium">
              <div class="flex items-center justify-between">
                Przesłane dokumenty
                <.toolbar
                  id={@id}
                  myself={@myself}
                  search={@search}
                  search_input_styles={@search_input_styles}
                  can_upload?={@can_upload?}
                  document_upload={@document_upload}
                  currently_uploading_count={@currently_uploading_count}
                  processing_blobs_count={@processing_blobs_count}
                />
              </div>
            </h3>
          <% end %>

          <.filters myself={@myself} type_filter={@type_filter} class={filters_styles(@variant)} />
        </div>

        <.documents_list documents={@documents} variant={@variant} />
      </section>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :myself, :any, required: true
  attr :search, :string, required: true
  attr :search_input_styles, :string, required: true
  attr :can_upload?, :boolean, required: true
  attr :document_upload, :map, default: nil
  attr :currently_uploading_count, :integer, required: true
  attr :processing_blobs_count, :integer, required: true

  defp toolbar(assigns) do
    ~H"""
    <div class="flex items-center gap-4">
      <form class="flex gap-4" phx-submit="search" phx-target={@myself}>
        <div
          id={"#{@id}-search-container"}
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
            class={@search_input_styles}
          />
          <.button
            type="button"
            size="small"
            phx-click={
              JS.toggle_attribute({"data-expanded", "true", "false"},
                to: "##{@id}-search-container"
              )
              |> JS.focus(to: "##{@id}-search-container input")
            }
            variant="outline"
            class="py-2"
          >
            <Lucideicons.search />
          </.button>
        </div>
      </form>
      <form
        :if={@can_upload? && @document_upload}
        class="relative"
        phx-submit="upload"
        phx-change="upload"
        phx-target={@myself}
      >
        <.live_file_input
          upload={@document_upload}
          class="peer sr-only"
          aria-label="Wgraj dokument"
        />

        <.button
          as="label"
          variant="secondary"
          size="small"
          class="relative py-1.75"
          type="button"
          for={@document_upload.ref}
        >
          <.upload_indicator
            id={@id}
            currently_uploading_count={@currently_uploading_count}
            processing_blobs_count={@processing_blobs_count}
          />
          <.icon name="hero-plus" class="size-4" /> Dodaj umowę
        </.button>
      </form>
    </div>
    """
  end

  attr :myself, :any, required: true
  attr :type_filter, :string, required: true
  attr :class, :string, default: ""

  defp filters(assigns) do
    ~H"""
    <div class={["flex items-center gap-3", @class]}>
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
    """
  end

  attr :documents, :list, required: true
  attr :variant, :atom, required: true

  defp documents_list(%{variant: :profile} = assigns) do
    ~H"""
    <div class="scrollbar-card max-h-80 space-y-2 overflow-y-auto">
      <p :if={Enum.empty?(@documents)} class="text-grey-500 text-sm">
        Brak dokumentów.
      </p>
      <.document_element :for={document <- @documents} document={document} />
    </div>
    """
  end

  defp documents_list(assigns) do
    ~H"""
    <div class="relative w-full flex-1">
      <div class="scrollbar-card absolute inset-0 space-y-2 overflow-y-auto pr-2">
        <%= if Enum.empty?(@documents) do %>
          <div class="text-darkGrey mt-4 text-sm">Brak dokumentów</div>
        <% else %>
          <.document_element :for={document <- @documents} document={document} />
        <% end %>
      </div>
    </div>
    """
  end

  defp outer_styles(:profile), do: "flex w-full flex-col"
  defp outer_styles(_), do: "flex h-full min-h-0 flex-col"

  defp section_styles(:profile), do: "flex w-full flex-col gap-6 rounded-lg bg-white p-6 shadow"

  defp section_styles(_), do: "relative flex h-full min-h-0 flex-col gap-y-6 rounded-md bg-white p-6 text-black shadow"

  defp header_wrapper_styles(:profile), do: "space-y-6"
  defp header_wrapper_styles(_), do: "shrink-0"

  defp filters_styles(:profile), do: ""
  defp filters_styles(_), do: "pt-6"

  defp search_input_styles(:profile) do
    "group w-0 border-transparent px-0 opacity-0 transition-[width,opacity,padding] duration-200 ease-in-out group-data-[expanded=true]:w-42 group-data-[expanded=true]:px-2 group-data-[expanded=true]:opacity-100 focus:border-none focus:ring-0 focus:outline-hidden lg:group-data-[expanded=true]:w-56"
  end

  defp search_input_styles(_) do
    "w-0 border-transparent px-0 opacity-0 transition-[width,opacity,padding] duration-200 ease-in-out group-data-[expanded=true]:w-64 group-data-[expanded=true]:px-2 group-data-[expanded=true]:py-1 group-data-[expanded=true]:opacity-100 focus:border-none focus:ring-0 focus:outline-hidden"
  end

  @doc false
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
    if socket.assigns.can_upload? do
      {:noreply, refetch_upload_counts(socket)}
    else
      {:noreply, socket}
    end
  end

  defp refetch_documents(socket) do
    documents =
      build_documents(
        socket.assigns.user.id,
        socket.assigns.scope,
        %{
          search: socket.assigns.search,
          type_filter: socket.assigns.type_filter
        }
      )

    assign(socket, :documents, documents)
  end

  defp build_documents(user_id, scope, %{search: search, type_filter: type_filter}) do
    parsed = parse_search(search)

    hours_record_docs =
      if type_filter in [nil, "hours_record"] do
        %{user_id: user_id}
        |> maybe_add_month(parsed.month)
        |> maybe_add_year(parsed.year)
        |> Timetracker.query_to_list_hours_records(scope: scope)
        |> Ash.read!(scope: scope)
        |> Enum.map(fn doc ->
          %{
            id: doc.id,
            type: :hours_record,
            name: "Ewidencja #{String.pad_leading(Integer.to_string(doc.month), 2, "0")}.#{doc.year}",
            date: DateTime.to_date(doc.inserted_at),
            url: ~p"/czasosledz/ewidencja/#{doc.id}",
            file_name: "Ewidencja_#{doc.year}_#{doc.month}.pdf"
          }
        end)
      else
        []
      end

    employment_contract_docs =
      if type_filter in [nil, "employment_contract"] do
        search_arg = if parsed.text != "", do: parsed.text

        user_id
        |> Payroll.query_to_list_employment_contracts(search_arg, scope: scope)
        |> Ash.read!(scope: scope)
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
      else
        []
      end

    other_docs = []

    Enum.sort_by(
      hours_record_docs ++ employment_contract_docs ++ other_docs,
      & &1.date,
      {:desc, Date}
    )
  end

  defp parse_search(search) do
    tokens = search |> String.trim() |> String.split(~r/[\s.]+/, trim: true)

    {month, year, text_tokens} =
      Enum.reduce(tokens, {nil, nil, []}, fn token, {month, year, text} ->
        case Integer.parse(token) do
          {num, ""} when num in 1..12 and is_nil(month) ->
            {num, year, text}

          {num, ""} when num in 1900..9999 and is_nil(year) ->
            {month, num, text}

          _ ->
            {month, year, text ++ [token]}
        end
      end)

    %{month: month, year: year, text: text_tokens |> Enum.join(" ") |> String.trim()}
  end

  defp maybe_add_month(args, nil), do: args
  defp maybe_add_month(args, month), do: Map.put(args, :month, month)

  defp maybe_add_year(args, nil), do: args
  defp maybe_add_year(args, year), do: Map.put(args, :year, year)

  defp refetch_upload_counts(socket) do
    currently_uploading_count =
      case socket.assigns do
        %{uploads: %{document_upload: upload}} ->
          length(Enum.filter(upload.entries, &(!&1.done?)))

        _ ->
          0
      end

    processing_blobs_count =
      if admin_actor?(socket.assigns.scope) do
        Blobs.get_processing_blobs_count(:employment_contract, socket.assigns.scope)
      else
        0
      end

    socket
    |> assign(:processing_blobs_count, processing_blobs_count)
    |> assign(:currently_uploading_count, currently_uploading_count)
  end

  defp admin_actor?(%{actor: %{role: :admin}}), do: true
  defp admin_actor?(_scope), do: false

  defp handle_progress(name, _params, socket) do
    socket =
      if socket.assigns.can_upload? do
        case uploaded_entries(socket, name) do
          {[_ | _] = entries, []} ->
            handle_uploads(entries, socket)
            refetch_upload_counts(socket)

          _ ->
            socket
        end
      else
        socket
      end

    {:noreply, socket}
  end

  defp handle_uploads(entries, socket) do
    scope = socket.assigns.scope
    user_id = socket.assigns.user.id

    Enum.each(entries, fn entry ->
      case consume_uploaded_entry(socket, entry, fn %{path: path} ->
             {:ok,
              Blobs.create_blob_for_processing(
                path,
                entry.client_type,
                entry.client_name,
                :employment_contract,
                %{user_id: user_id},
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

  attr :id, :string, required: true
  attr :currently_uploading_count, :integer, required: true
  attr :processing_blobs_count, :integer, required: true

  defp upload_indicator(%{currently_uploading_count: 0, processing_blobs_count: 0} = assigns) do
    ~H"""
    """
  end

  defp upload_indicator(assigns) do
    ~H"""
    <span
      id={"#{@id}-upload-count-indicator"}
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
