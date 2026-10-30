defmodule FirmowidWeb.Documents.Components.DocumentsSection do
  @moduledoc "LiveComponent for listing, filtering, and uploading user documents."
  use FirmowidWeb, :live_component

  import FirmowidUI.Components.Button
  import FirmowidUI.Components.Link
  import FirmowidWeb.Infrastructure.Flags, only: [flag_enabled?: 2]
  import Phoenix.Component, except: [link: 1]

  alias Firmowid.Blobs
  alias Firmowid.Blobs.Blob
  alias Firmowid.ErrorKind
  alias Firmowid.Payroll
  alias Firmowid.Timetracker
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
  def update(%{refetch: true} = _assigns, socket) do
    socket =
      socket
      |> refetch_documents()
      |> refetch_upload_counts()

    {:ok, socket}
  end

  def update(assigns, socket) do
    can_upload? = admin_actor?(assigns.scope)

    socket =
      socket
      |> assign(Map.delete(assigns, :refetch))
      |> assign_new(:dimmed, fn -> false end)
      |> assign_new(:variant, fn -> :management end)
      |> assign_new(:current_contract_id, fn -> nil end)
      |> assign_new(:feature_flags, fn -> %{} end)
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
      |> assign(
        :documents,
        Enum.reject(assigns.documents, fn document ->
          document.type == :other and not flag_enabled?(:accurate_salary_calculation, assigns)
        end)
      )

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
              <h2 class="text-base leading-none font-medium text-grey-900">
                {gettext("Uploaded documents")}
              </h2>
              <.toolbar
                id={@id}
                myself={@myself}
                search={@search}
                search_input_styles={@search_input_styles}
                can_upload?={@can_upload?}
                feature_flags={@feature_flags}
                document_upload={@document_upload}
                currently_uploading_count={@currently_uploading_count}
                processing_blobs_count={@processing_blobs_count}
              />
            </div>
          <% else %>
            <h3 class="text-base/tight font-medium text-grey-900">
              <div class="flex items-center justify-between">
                {gettext("Uploaded documents")}
                <.toolbar
                  id={@id}
                  myself={@myself}
                  search={@search}
                  search_input_styles={@search_input_styles}
                  can_upload?={@can_upload?}
                  feature_flags={@feature_flags}
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
  attr :feature_flags, :map, required: true
  attr :document_upload, :map, default: nil
  attr :currently_uploading_count, :integer, required: true
  attr :processing_blobs_count, :integer, required: true

  defp toolbar(assigns) do
    ~H"""
    <div class="flex items-center gap-4">
      <form class="flex gap-3" phx-submit="search" phx-target={@myself}>
        <div
          id={"#{@id}-search-container"}
          data-expanded={to_string(@search != "")}
          class="group flex items-center justify-center rounded-lg transition-shadow data-[expanded=true]:bg-grey-200 data-[expanded=true]:focus-within:ring-2"
        >
          <.input
            type="text"
            name="szukaj"
            value={@search}
            placeholder={gettext("Search document")}
            phx-change="search"
            phx-debounce="300"
            phx-target={@myself}
            input_class="py-0 px-1 bg-transparent! border-none z-10 font-normal"
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
            class="py-2 group-data-[expanded=true]:rounded-r-lg"
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
          aria-label={gettext("Upload document")}
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
          <.icon name="hero-plus" class="size-4" />
          <%= if flag_enabled?(:accurate_salary_calculation, assigns) do %>
            {gettext("Add employee document")}
          <% else %>
            {gettext("Add contract")}
          <% end %>
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
    <.filter_pills class={@class}>
      <:pill
        active={@type_filter == "hours_record"}
        phx-click="toggle_type"
        phx-value-typ={:hours_record}
        phx-target={@myself}
      >
        <.icon name="hero-clock" class="size-4" /> {pgettext("document filter", "record")}
      </:pill>
      <:pill
        active={@type_filter == "employment_contract"}
        phx-click="toggle_type"
        phx-value-typ={:employment_contract}
        phx-target={@myself}
      >
        <.icon name="hero-document" class="size-4" /> {pgettext("document filter", "contract")}
      </:pill>
      <:pill
        active={@type_filter == "other"}
        phx-click="toggle_type"
        phx-value-typ={:other}
        phx-target={@myself}
      >
        <.icon name="hero-ellipsis-horizontal" class="size-4" /> {pgettext("document filter", "other")}
      </:pill>
    </.filter_pills>
    """
  end

  attr :documents, :list, required: true
  attr :variant, :atom, required: true

  defp documents_list(%{variant: :profile} = assigns) do
    ~H"""
    <div class="scrollbar-card h-100 max-h-100 space-y-2 overflow-y-auto">
      <%= if Enum.empty?(@documents) do %>
        <div class="flex size-full items-center justify-center rounded-lg bg-grey-50 text-sm text-grey-700">
          <p>{gettext("No documents")}</p>
        </div>
      <% else %>
        <.document_element :for={document <- @documents} document={document} />
      <% end %>
    </div>
    """
  end

  defp documents_list(assigns) do
    ~H"""
    <div class="relative w-full flex-1">
      <div class="absolute inset-0 scrollbar-card space-y-2 overflow-y-auto pr-2">
        <%= if Enum.empty?(@documents) do %>
          <div class="flex size-full items-center justify-center rounded-lg bg-grey-50 text-sm text-grey-700">
            <p>{gettext("No documents")}</p>
          </div>
        <% else %>
          <.document_element :for={document <- @documents} document={document} />
        <% end %>
      </div>
    </div>
    """
  end

  defp outer_styles(:profile), do: "flex h-full w-full flex-col"
  defp outer_styles(_), do: "flex h-full min-h-0 flex-col"

  defp section_styles(:profile), do: "flex w-full h-full flex-col gap-6 rounded-lg bg-white p-6"

  defp section_styles(_), do: "relative flex h-full min-h-0 flex-col gap-y-6 rounded-md bg-white p-6 text-black"

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
      redirect={@document.url}
      download={@document.file_name}
      class="group flex items-center justify-between gap-4 rounded-md px-2 py-2.5 transition"
    >
      <div class="flex items-center gap-3">
        <div class="flex size-7 items-center justify-center rounded-md bg-grey-100">
          <%= case @document.type do %>
            <% :hours_record -> %>
              <.icon name="hero-clock" class="size-5 text-grey-700" />
            <% :employment_contract -> %>
              <.icon name="hero-document" class="size-5 text-grey-700" />
            <% _ -> %>
              <.icon name="hero-ellipsis-horizontal" class="size-5 text-grey-700" />
          <% end %>
        </div>
        <div class="group-hover:underline">
          {@document.name}
        </div>
      </div>

      <div class="flex items-center gap-4 text-sm text-grey-700">
        {contract_status_badge(@document)}
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
      socket.assigns.user
      |> build_documents(
        socket.assigns.scope,
        %{
          search: socket.assigns.search,
          type_filter: socket.assigns.type_filter
        }
      )
      |> badge_only_current_contract(socket.assigns[:current_contract_id])

    assign(socket, :documents, documents)
  end

  # Contracts are never retired, so a user accumulates several `:active` ones as
  # renewals land. Only the current contract should be badged as such, so we remove the `:status` key from all other active contracts.
  defp badge_only_current_contract(documents, nil), do: documents

  defp badge_only_current_contract(documents, current_contract_id) do
    Enum.map(documents, fn
      %{type: :employment_contract, status: :active, id: ^current_contract_id} = document ->
        document

      %{type: :employment_contract, status: :active} = document ->
        Map.delete(document, :status)

      document ->
        document
    end)
  end

  defp build_documents(user, scope, %{search: search, type_filter: type_filter}) do
    parsed = parse_search(search)

    contracts =
      Payroll.list_employment_contracts!(%{member_id: user.member.id},
        scope: scope,
        load: [:blob]
      )

    hours_record_docs =
      if type_filter in [nil, "hours_record"] do
        %{member_id: user.member.id}
        |> maybe_add_month(parsed.month)
        |> maybe_add_year(parsed.year)
        |> Timetracker.query_to_list_hours_records(scope: scope)
        |> Ash.Query.load([:blob], scope: scope)
        |> Ash.read!(scope: scope)
        |> Enum.map(fn doc ->
          %{
            id: doc.id,
            type: :hours_record,
            name:
              gettext("Timesheet %{date}",
                date: "#{String.pad_leading(Integer.to_string(doc.month), 2, "0")}.#{doc.year}"
              ),
            date: DateTime.to_date(doc.inserted_at),
            url: ~p"/czasosledz/ewidencja/#{doc.id}",
            file_name: doc.blob.original_filename
          }
        end)
      else
        []
      end

    employment_contract_docs =
      if type_filter in [nil, "employment_contract"] do
        contracts
        |> Enum.filter(&matches_date?(&1.starts_at, parsed))
        |> Enum.map(fn doc ->
          %{
            id: doc.id,
            type: :employment_contract,
            status: doc.status,
            name:
              gettext("Contract %{date}",
                date: "#{String.pad_leading(Integer.to_string(doc.starts_at.month), 2, "0")}.#{doc.starts_at.year}"
              ),
            date: doc.starts_at,
            url: ~p"/zarzadzanie/umowy/#{doc.id}",
            file_name: doc.blob.original_filename
          }
        end)
      else
        []
      end

    other_docs =
      if type_filter in [nil, "other"] do
        contract_blob_ids = MapSet.new(contracts, & &1.blob_id)

        %{member_id: user.member.id, processing_target: :employment_contract}
        |> Blobs.list_blobs!(scope: scope, load: [:url])
        |> Enum.filter(fn blob ->
          blob.processing_state == :succeeded and
            not MapSet.member?(contract_blob_ids, blob.id) and
            matches_date?(DateTime.to_date(blob.inserted_at), parsed) and
            String.contains?(
              String.downcase(blob.original_filename),
              String.downcase(parsed.text)
            )
        end)
        |> Enum.map(fn blob ->
          %{
            id: blob.id,
            type: :other,
            name: blob.original_filename,
            date: DateTime.to_date(blob.inserted_at),
            url: blob.url,
            file_name: blob.original_filename
          }
        end)
      else
        []
      end

    Enum.sort_by(
      hours_record_docs ++ employment_contract_docs ++ other_docs,
      & &1.date,
      {:desc, Date}
    )
  end

  defp matches_date?(date, parsed),
    do: (is_nil(parsed.month) or date.month == parsed.month) and (is_nil(parsed.year) or date.year == parsed.year)

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

  defp admin_actor?(%{actor: %{member: %{role: :admin}}}), do: true
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
    member_id = socket.assigns.user.member.id

    Enum.each(entries, fn entry ->
      case consume_uploaded_entry(socket, entry, fn %{path: path} ->
             {:ok,
              Blobs.create_blob_for_processing(
                path,
                entry.client_type,
                entry.client_name,
                :employment_contract,
                %{member_id: member_id},
                scope: scope
              )}
           end) do
        {:ok, %Blob{}} ->
          LiveToast.send_toast(:success, gettext("The file was uploaded."))

        {:error, err} ->
          Logger.warning("Upload failed", error_kind: ErrorKind.classify(err))
          LiveToast.send_toast(:error, gettext("An error occurred while uploading the file."))
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
      data-tippy-content={
        gettext("The files are being processed and will be available in Firmowid in a few moments")
      }
      class="absolute -top-3.5 -right-3.5 flex size-7 items-center justify-center overflow-hidden rounded-full bg-grey-100"
    >
      <span class="absolute block size-full animate-pulse bg-rust-600" />
      <span class="z-10 flex size-5 items-center justify-center rounded-full bg-grey-100">
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
    <Lucideicons.arrow_up class="size-4 leading-none text-rust-900" />
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

  attr :status, :atom, required: true

  defp contract_status_badge(%{status: :pending_signature} = assigns) do
    ~H"""
    <span class="rounded-2xl bg-teal-100 px-4 py-1 text-sm text-teal-700">
      {gettext("Pending")}
    </span>
    """
  end

  defp contract_status_badge(%{status: :signed} = assigns) do
    ~H"""
    <span class="rounded-2xl bg-teal-100 px-4 py-1 text-sm text-teal-700">
      {pgettext("contract status", "signed")}
    </span>
    """
  end

  defp contract_status_badge(%{status: :active} = assigns) do
    ~H"""
    <span class="rounded-2xl bg-moss-100 px-4 py-1 text-sm text-moss-700">
      {pgettext("contract status", "current contract")}
    </span>
    """
  end

  defp contract_status_badge(assigns) do
    ~H"""
    """
  end
end
