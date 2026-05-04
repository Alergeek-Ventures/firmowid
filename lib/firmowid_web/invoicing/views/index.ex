# credo:disable-for-this-file ExDNA.Credo
# This LiveView currently combines orchestration for uploads, PubSub, and invoice grouping;
# removing duplication requires extracting domain-facing services across feature boundaries.
defmodule FirmowidWeb.Invoicing.Views.Index do
  @moduledoc false
  # TODO: move business logic (transaction grouping by party, get_active_months)
  # to domain actions/calculations — LiveView should only handle presentation
  use FirmowidWeb, :live_view

  import FirmowidWeb.Core.PubSubDebounce
  import FirmowidWeb.DesignSystem.Components.Button
  import FirmowidWeb.DesignSystem.Components.CoreComponents, except: [button: 1]
  import FirmowidWeb.DesignSystem.Components.Link
  import FirmowidWeb.DesignSystem.Components.MonthPicker
  import Phoenix.Component, except: [link: 1]

  alias Ash.Notifier.Notification
  alias Firmowid.Ash.Blobs
  alias Firmowid.Ash.Blobs.Blob
  alias Firmowid.Ash.Finances
  alias Firmowid.Ash.Finances.Requisition
  alias Firmowid.Ash.Finances.Transaction
  alias Firmowid.Ash.Invoicing
  alias Firmowid.Ash.Invoicing.CostInvoice
  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Ash.Invoicing.TransactionGroup
  alias Firmowid.Ash.Ksef
  alias FirmowidWeb.Core.Endpoint
  alias FirmowidWeb.Invoicing.Navigation
  alias Phoenix.Socket.Broadcast

  require Ash.Query

  # Load definitions for invoice queries
  @cost_invoice_loads [
    :transactions,
    :effective_total_amount,
    :effective_currency,
    :effective_seller_display_name
  ]
  @sales_invoice_loads [
    :gross_value,
    :sales_invoice_items,
    :buyer_display_name_label,
    :transactions,
    corrections: :sales_invoice_items,
    latest_correction: :sales_invoice_items
  ]

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    organization_id = user.organization_id

    if connected?(socket) do
      # Ash PubSub — invoicing resources
      Endpoint.subscribe("blob:created:#{organization_id}")
      Endpoint.subscribe("blob:updated:#{organization_id}")
      Endpoint.subscribe("blob:destroyed:#{organization_id}")
      Endpoint.subscribe("cost_invoice:created:#{organization_id}")
      Endpoint.subscribe("cost_invoice:updated:#{organization_id}")
      Endpoint.subscribe("sales_invoice:created:#{organization_id}")
      Endpoint.subscribe("sales_invoice:updated:#{organization_id}")
      Endpoint.subscribe("sales_invoice:destroyed:#{organization_id}")
      # Ash PubSub — finances
      Endpoint.subscribe("transaction:updated:#{organization_id}")
      Endpoint.subscribe("requisition:linked:#{organization_id}")
      Endpoint.subscribe("requisition:rejected:#{organization_id}")
      Endpoint.subscribe("requisition:error:#{organization_id}")
      # KSeF status (separate system)
      Ksef.subscribe_ksef_status(organization_id)
    end

    socket =
      if user.role == :admin do
        allow_upload(socket, :file,
          max_entries: 50,
          accept: ["application/pdf", "image/*"],
          progress: &handle_progress/3,
          auto_upload: true
        )
      else
        socket
      end

    connected_bank_accounts =
      [scope: socket.assigns.ash_scope]
      |> Finances.list_requisitions!()
      |> Enum.count(&(&1.status == :accepted))

    socket = assign(socket, :has_connected_bank_account, connected_bank_accounts > 0)

    active_months =
      get_active_months(socket.assigns.ash_scope) ++
        [Date.beginning_of_month(Date.utc_today())]

    socket = assign(socket, :active_months, active_months)

    socket =
      socket
      |> assign(:show_search, false)
      |> assign(:search_query, "")
      |> assign(:search_results, [])
      |> assign(:transactions_debounce_timer, nil)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="my-16 flex flex-col items-center justify-center gap-16 text-center md:hidden">
      <.icon name="hero-document-magnifying-glass-solid" class="size-16" />
      <div class="flex flex-col gap-4">
        <p class="font-bold">Podgląd dokumentów nie jest aktualnie dostępny na urządzeniu mobilnym</p>
        <p>Zeskanuj dokument naciskając przycisk poniżej, a będzie on dostępny na komputerze.</p>
      </div>
    </div>

    <div class="bg-lightGreyBg top-navbar sticky z-10 flex justify-between py-3 max-md:justify-center">
      <div class="flex items-center gap-4">
        <.month_picker
          id="month"
          active_months={@active_months}
          selected_date={@params.month}
        />

        <.button
          type="button"
          variant="secondary"
          size="big"
          id="open-search"
          phx-click="open-search"
          phx-hook="Tippy"
          data-tippy-content="Szukaj faktur"
        >
          <Lucideicons.search />
        </.button>
      </div>

      <div
        phx-drop-target={@current_user.role == :admin && @uploads.file.ref}
        class="flex flex-row gap-4"
      >
        <%= if @invoicing_entries != [] do %>
          <.live_component
            id="download-component"
            module={FirmowidWeb.Invoicing.Components.DownloadModal}
            month={@params.month}
          />
        <% end %>
        <form
          :if={@current_user.role == :admin}
          id="upload-form"
          phx-change="upload"
          phx-submit="upload"
        >
          <div class="hidden">
            <.live_file_input upload={@uploads.file} />
          </div>
          <FirmowidWeb.DesignSystem.Components.Button.button
            as="label"
            for={@uploads.file.ref}
            variant="secondary"
            accent="orange"
            class="relative"
          >
            <%= if @currently_uploading_count > 0 or @processing_blobs_count > 0 do %>
              <span
                id="upload-count-indicator"
                phx-hook="Tippy"
                data-tippy-content="Pliki są przetwarzane i za kilka chwil będą dostępne w Firmowidzie"
                class="bg-lightGreyBg absolute -top-3 -right-3 flex size-7 items-center justify-center overflow-hidden rounded-full"
              >
                <span class="absolute block size-full animate-[spin_2s_linear_infinite] bg-linear-to-r from-orange-200 to-orange-400" />
                <span class="bg-lightGreyBg z-10 flex size-5 items-center justify-center rounded-full">
                  <%= if @currently_uploading_count > 0 do %>
                    <.icon name="hero-arrow-up-circle-solid" class="size-5 leading-none text-white" />
                  <% else %>
                    <%= case @processing_blobs_count do %>
                      <% 1 -> %>
                        <.icon
                          name="hero-arrow-up-circle-solid"
                          class="size-5 leading-none text-white"
                        />
                      <% 0 -> %>
                      <% _ -> %>
                        <span>{@processing_blobs_count}</span>
                    <% end %>
                  <% end %>
                </span>
              </span>
            <% else %>
              <span
                id="upload-count-indicator"
                phx-hook="Tippy"
                data-tippy-content="Faktury od zagranicznych kontrahentów w formacie PDF lub ich zdjęcia (PNG, JPG)"
                class="absolute top-0 left-0 size-full"
              />
            <% end %>
            <Lucideicons.file_input />
            <span class="block sm:grow sm:text-center md:hidden lg:block">
              Faktura spoza KSeF
            </span>
          </FirmowidWeb.DesignSystem.Components.Button.button>
        </form>
        <.link
          :if={@current_user.role == :admin}
          navigate={~p"/sprzedazowe"}
          kind="button"
          variant="secondary"
          accent="turquoise"
          id="sales-invoice-link"
          class="max-md:hidden"
        >
          <Lucideicons.file_pen_line class="size-5" />
          <span class="max-xl:hidden">
            Wystaw fakturę
          </span>
        </.link>
      </div>
    </div>
    <.live_component
      module={FirmowidWeb.Invoicing.Components.SearchOverlay}
      id="invoice-search-overlay"
      show_search={@show_search}
      search_query={@search_query}
      search_results={@search_results}
    />

    <FirmowidWeb.Invoicing.Components.FilterBar.filter_bar
      params={@params}
      pending_count={@pending_invoicing_entries_count}
      is_month_closed={@is_month_closed}
      is_month_touched={@is_month_touched}
    />

    <div
      :if={@current_user.role == :admin}
      class="mt-2 flex flex-col gap-4 max-md:hidden"
    >
      <%= cond do %>
        <% @params.view_mode == :dashboard -> %>
          <FirmowidWeb.Invoicing.Components.Dashboard.dashboard
            unpaid_invoices={@dashboard_unpaid_invoices}
            unpaid_invoices_count={@dashboard_unpaid_invoices_count}
            unmatched_transactions={@dashboard_unmatched_transactions}
            unmatched_transactions_count={@dashboard_unmatched_transactions_count}
            matched_entries={@dashboard_matched_entries}
            matched_entries_count={@dashboard_matched_entries_count}
            suggestions={@dashboard_suggestions}
            suggestions_count={@dashboard_suggestions_count}
            month={@params.month}
            return_to={build_invoicing_url(@params)}
          />
        <% @is_month_closed and @params.filter == :unmatched -> %>
          <.live_component
            id="month-closed-zero-state"
            module={FirmowidWeb.Invoicing.Components.MonthClosedZeroState}
            month={@params.month}
          />
        <% true -> %>
          <FirmowidWeb.Invoicing.Components.EntriesTable.table
            mode={@params.filter}
            invoicing_entries={@invoicing_entries}
            return_to={build_invoicing_url(@params)}
          />
      <% end %>
    </div>

    <div
      :if={@current_user.role == :admin}
      id="file-drop-overlay"
      class="fixed top-[10lvw] left-[5lvw] z-20 hidden h-[80lvh] w-[90lvw] items-center justify-center rounded-lg bg-[#CEE6E666] opacity-0 transition-opacity"
      phx-hook="FileUploadDragNDrop"
      phx-drop-target={@current_user.role == :admin && @uploads.file.ref}
    >
      <div class="border-blueBg absolute top-0 left-0 size-full rounded-lg border-2 opacity-100" />
      <div class="bg-blueText flex flex-col items-center justify-center gap-8 rounded-xl p-4 py-8 text-white">
        <.icon name="hero-cloud-arrow-up" class="size-16" />
        <p class="max-w-[25lvw] text-center text-xl opacity-100">
          Przeciągnij faktury, aby załadować je do Firmowida.
        </p>
        <p class="max-w-[25lvw] text-center text-sm opacity-80">
          (max 50 plików, PDF, JPG oraz PNG)
        </p>
      </div>
    </div>
    """
  end

  @impl true
  def handle_params(params, _url, socket) do
    parsed = parse_url_params(params)

    socket =
      socket
      |> apply_action(socket.assigns.live_action, params)
      |> assign(:params, parsed)
      |> refetch_invoicing_entries()

    {:noreply, socket}
  end

  defp parse_url_params(params) do
    view_mode = parse_view_mode(Map.get(params, "view"))

    %{
      month: parse_month(Map.get(params, "month")),
      filter: parse_filter(Map.get(params, "filter")),
      subfilter: parse_subfilter(Map.get(params, "subfilter")),
      view_mode: view_mode
    }
  end

  defp parse_month(nil), do: Date.beginning_of_month(Date.utc_today())
  defp parse_month(date_string), do: Date.from_iso8601!(date_string)

  defp parse_filter(nil), do: :invoices
  defp parse_filter(filter_string), do: parse_filter_value(filter_string) || :invoices

  defp parse_filter_value("all"), do: :all
  defp parse_filter_value("invoices"), do: :invoices
  defp parse_filter_value("transactions"), do: :transactions
  defp parse_filter_value("unmatched"), do: :unmatched
  defp parse_filter_value(_filter_string), do: nil

  defp parse_view_mode("list"), do: :list
  defp parse_view_mode(nil), do: :dashboard
  defp parse_view_mode(_), do: :dashboard

  defp parse_subfilter(nil), do: nil
  defp parse_subfilter(subfilter_string), do: parse_subfilter_value(subfilter_string)

  defp parse_subfilter_value("oplacone"), do: :oplacone
  defp parse_subfilter_value("nieoplacone"), do: :nieoplacone
  defp parse_subfilter_value("dopasowane"), do: :dopasowane
  defp parse_subfilter_value("bez_dokumentu"), do: :bez_dokumentu
  defp parse_subfilter_value(_subfilter_string), do: nil

  @impl true
  def handle_event("change-month", %{"month" => month}, socket) do
    month = Date.from_iso8601!(month)

    {:noreply, update_param(socket, :month, month)}
  end

  def handle_event("change-filter", %{"filter" => filter}, socket) do
    case parse_filter_value(filter) do
      nil ->
        {:noreply, socket}

      parsed_filter ->
        params =
          socket.assigns.params
          |> Map.put(:filter, parsed_filter)
          |> Map.put(:view_mode, :list)
          |> Map.put(:subfilter, nil)

        {:noreply, update_params(socket, params)}
    end
  end

  def handle_event("change-subfilter", %{"subfilter" => subfilter}, socket) do
    case parse_subfilter_value(subfilter) do
      nil ->
        {:noreply, socket}

      parsed_subfilter ->
        next_subfilter =
          if socket.assigns.params.subfilter == parsed_subfilter do
            nil
          else
            parsed_subfilter
          end

        {:noreply, update_param(socket, :subfilter, next_subfilter)}
    end
  end

  @impl true
  def handle_event("upload", _, socket) do
    socket = refetch_upload_counts(socket)

    {:noreply, socket}
  end

  def handle_event("toggle-skip-invoicing", %{"id" => id, "type" => type}, socket) do
    socket = do_toggle_skip(socket, id, type)
    {:noreply, socket}
  end

  def handle_event("toggle-skip-invoicing-group", %{"transaction_ids" => transaction_ids}, socket) do
    socket = Enum.reduce(transaction_ids, socket, &do_toggle_skip(&2, &1, "transaction"))
    {:noreply, socket}
  end

  def handle_event("open-search", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_search, true)
     |> assign(:search_query, "")
     |> assign(:search_results, [])}
  end

  def handle_event("close-search", _params, socket) do
    {:noreply, assign(socket, :show_search, false)}
  end

  def handle_event("update-search", %{"q" => q}, socket) do
    q = String.trim(q)

    results =
      Invoicing.search_invoices(
        %{
          query: q,
          include_sales: true,
          include_cost: true
        },
        socket.assigns.ash_scope
      )

    {:noreply,
     socket
     |> assign(:search_results, results)
     |> assign(:search_query, q)}
  end

  def handle_event("goto-invoice", %{"id" => id, "type" => type}, socket) do
    path =
      case type do
        "cost" ->
          Navigation.cost_invoice_show_path(id, build_invoicing_url(socket.assigns.params))

        "sales" ->
          Navigation.sales_invoice_show_path(id, build_invoicing_url(socket.assigns.params))
      end

    {:noreply, push_navigate(socket, to: path)}
  end

  @impl true
  def handle_info(%Broadcast{payload: %Notification{resource: Transaction}}, socket) do
    {:noreply, debounce_refetch(socket, :invoicing_entries, 10_000)}
  end

  @impl true
  def handle_info({:debounced_refetch, :invoicing_entries}, socket) do
    {:noreply, refetch_invoicing_entries(socket)}
  end

  # Blob created — file is being processed, refresh list
  @impl true
  def handle_info(%Broadcast{payload: %Notification{resource: Blob, action: %{type: :create}}}, socket) do
    {:noreply, refetch_invoicing_entries(socket)}
  end

  # Blob updated — processing state transitions
  @impl true
  def handle_info(%Broadcast{payload: %Notification{resource: Blob, action: %{type: :update}, data: blob}}, socket) do
    if blob.processing_state == :failed do
      show_blob_processing_failure_toast(blob)
    end

    {:noreply, refetch_invoicing_entries(socket)}
  end

  # Blob destroyed — processing failed
  @impl true
  def handle_info(
        %Broadcast{
          payload:
            %Notification{resource: Blob, action: %{type: :destroy}, metadata: %{reason: :processing_failed}} =
              notification
        },
        socket
      ) do
    LiveToast.send_toast(:error, notification.data.original_filename, title: "Nie udało się wgrać pliku")

    {:noreply, refetch_invoicing_entries(socket)}
  end

  # Blob destroyed — invalid document uploaded
  @impl true
  def handle_info(
        %Broadcast{
          payload:
            %Notification{resource: Blob, action: %{type: :destroy}, metadata: %{reason: :invalid_document}} =
              notification
        },
        socket
      ) do
    LiveToast.send_toast(
      :error,
      "Plik #{notification.data.original_filename} nie zawiera wymaganych danych. Upewnij się, że wgrywasz fakturę, paragon lub rachunek.",
      title: "Nieprawidłowy dokument"
    )

    {:noreply, socket}
  end

  # Blob destroyed — normal cleanup (delete invoice, etc.)
  @impl true
  def handle_info(%Broadcast{payload: %Notification{resource: Blob, action: %{type: :destroy}}}, socket) do
    {:noreply, refetch_invoicing_entries(socket)}
  end

  # Cost invoice created — show success toast with link
  @impl true
  def handle_info(
        %Broadcast{payload: %Notification{resource: CostInvoice, action: %{type: :create}} = notification},
        socket
      ) do
    socket = refetch_invoicing_entries(socket)
    cost_invoice = notification.data

    LiveToast.send_toast(
      :success,
      "#{cost_invoice.issue_date} / #{cost_invoice.seller_display_name}",
      title: "Faktura załadowana",
      action: fn assigns ->
        assigns =
          assign(
            assigns,
            :issue_date,
            Date.beginning_of_month(cost_invoice.issue_date)
          )

        ~H"""
        <.link
          kind="unstyled"
          class="text-bold text-sm underline"
          navigate={
            Navigation.invoicing_index_path(%{
              month: @issue_date,
              filter: :invoices,
              subfilter: nil,
              view_mode: :dashboard
            })
          }
        >
          Wyświetl <.icon name="hero-arrow-right-solid" class="size-3" />
        </.link>
        """
      end
    )

    {:noreply, socket}
  end

  # Cost invoice connected to transaction — show match toast
  @impl true
  def handle_info(
        %Broadcast{payload: %Notification{resource: CostInvoice, action: %{name: :connect_transactions}, data: ci}},
        socket
      ) do
    socket = refetch_invoicing_entries(socket)
    cost_invoice = ci

    LiveToast.send_toast(
      :success,
      "#{cost_invoice.issue_date} / #{cost_invoice.seller_display_name}",
      title: "Połączenie faktury z transakcją",
      action: fn assigns ->
        assigns =
          assign(
            assigns,
            :issue_date,
            Date.beginning_of_month(cost_invoice.issue_date)
          )

        ~H"""
        <.link
          kind="unstyled"
          class="text-bold text-sm underline"
          navigate={
            Navigation.invoicing_index_path(%{
              month: @issue_date,
              filter: :invoices,
              subfilter: nil,
              view_mode: :dashboard
            })
          }
        >
          Wyświetl <.icon name="hero-arrow-right-solid" class="size-3" />
        </.link>
        """
      end
    )

    {:noreply, socket}
  end

  # Cost invoice — debounced refetch to allow CSS animation to complete
  @impl true
  def handle_info(%Broadcast{payload: %Notification{resource: CostInvoice}}, socket) do
    {:noreply, debounce_refetch(socket, :invoicing_entries, 10_000)}
  end

  # Sales invoice — debounced refetch to allow CSS animation to complete
  @impl true
  def handle_info(%Broadcast{payload: %Notification{resource: SalesInvoice}}, socket) do
    {:noreply, debounce_refetch(socket, :invoicing_entries, 10_000)}
  end

  @impl true
  def handle_info({:ksef_invoice_status, _payload}, socket) do
    {:noreply, refetch_invoicing_entries(socket)}
  end

  # Handle Ash native PubSub broadcasts for requisition status changes
  def handle_info(
        %Broadcast{topic: "requisition:" <> _, payload: %Notification{resource: Requisition, action: action}},
        socket
      ) do
    {toast_type, message} =
      case action do
        :accept ->
          {:success, "Konto bankowe zostało pomyślnie połączone!"}

        :reject ->
          {:error, "Połączenie z bankiem zostało odrzucone. Spróbuj ponownie."}

        :handle_check_error ->
          {:error, "Wystąpił błąd podczas łączenia konta bankowego. Spróbuj ponownie."}

        _ ->
          {:info, "Status połączenia z bankiem został zaktualizowany."}
      end

    LiveToast.send_toast(toast_type, message)

    {:noreply, socket}
  end

  defp show_blob_processing_failure_toast(%Blob{original_filename: filename, processing_metadata: metadata}) do
    case processing_failure_reason(metadata) do
      :invalid_document ->
        LiveToast.send_toast(
          :error,
          processing_failure_message(metadata, filename),
          title: "Nieprawidłowy dokument"
        )

      _ ->
        LiveToast.send_toast(:error, processing_failure_message(metadata, filename), title: "Nie udało się wgrać pliku")
    end
  end

  defp processing_failure_reason(%{"error_code" => "invalid_document"}), do: :invalid_document
  defp processing_failure_reason(%{error_code: "invalid_document"}), do: :invalid_document
  defp processing_failure_reason(%{"error" => ":invalid_document"}), do: :invalid_document
  defp processing_failure_reason(%{error: ":invalid_document"}), do: :invalid_document
  defp processing_failure_reason(_), do: :processing_failed

  defp processing_failure_message(%{"error_message" => message}, _filename) when is_binary(message), do: message

  defp processing_failure_message(%{error_message: message}, _filename) when is_binary(message), do: message

  defp processing_failure_message(_metadata, filename), do: filename

  defp update_param(socket, key, value) do
    params = Map.put(socket.assigns.params, key, value)
    update_params(socket, params)
  end

  defp update_params(socket, params) do
    url = build_invoicing_url(params)
    push_patch(socket, to: url)
  end

  defp build_invoicing_url(params) do
    Navigation.invoicing_index_path(params)
  end

  defp handle_progress(:file, _, socket) do
    socket =
      case uploaded_entries(socket, :file) do
        {[_ | _] = entries, []} ->
          handle_uploads(entries, socket)
          refetch_upload_counts(socket)

        _ ->
          socket
      end

    {:noreply, socket}
  end

  defp handle_uploads(entries, socket) do
    scope = socket.assigns.ash_scope

    for entry <- entries do
      consume_uploaded_entry(socket, entry, fn %{path: path} ->
        handle_upload_result(
          upload_cost_invoice(
            path,
            entry.client_type,
            entry.client_name,
            scope
          ),
          scope
        )

        {:ok, nil}
      end)
    end
  end

  defp handle_upload_result({:ok, {:existing_cost_invoice, cost_invoice}}, _scope) do
    LiveToast.send_toast(
      :info,
      "Ta faktura jest już w systemie",
      title: "Duplikat pliku",
      action: fn assigns ->
        assigns = assign(assigns, :cost_invoice_id, cost_invoice.id)

        ~H"""
        <.link
          kind="unstyled"
          class="text-bold text-sm underline"
          navigate={~p"/kosztowe/#{@cost_invoice_id}"}
        >
          Wyświetl <.icon name="hero-arrow-right-solid" class="size-3" />
        </.link>
        """
      end
    )
  end

  defp handle_upload_result({:ok, :blob_already_processing}, _scope) do
    LiveToast.send_toast(:info, "Ten plik jest już przetwarzany")
  end

  defp handle_upload_result({:ok, :blob_reprocessing_started}, _scope) do
    LiveToast.send_toast(:info, "Plik został dodany ponownie do kolejki przetwarzania")
  end

  defp handle_upload_result({:error, :blob_already_exists}, _scope) do
    LiveToast.send_toast(:info, "Ta faktura jest już w systemie")
  end

  defp handle_upload_result(_result, _scope), do: nil

  defp upload_cost_invoice(path, content_type, original_filename, scope) do
    Blobs.create_or_retry_cost_invoice_blob(path, content_type, original_filename, scope: scope)
  end

  defp do_toggle_skip(socket, id, "transaction") do
    scope = socket.assigns.ash_scope
    tx = Finances.get_transaction!(id, scope: scope)
    new_skip = !tx.skip_invoicing
    Finances.set_transaction_skip_invoicing!(tx, %{skip_invoicing: new_skip}, scope: scope)
    toggle_transaction_skip(socket, id, new_skip)
  end

  defp do_toggle_skip(socket, id, "cost_invoice") do
    scope = socket.assigns.ash_scope
    cost_invoice = Invoicing.get_cost_invoice!(id, scope: scope)
    new_skip = !cost_invoice.skip_invoicing
    Invoicing.toggle_cost_invoice_skip!(cost_invoice, scope: scope)
    toggle_entry_skip(socket, id, new_skip)
  end

  defp do_toggle_skip(socket, id, "sales_invoice") do
    scope = socket.assigns.ash_scope
    invoice = SalesInvoice.by_id!(id, scope: scope)
    new_skip = !invoice.skip_invoicing
    SalesInvoice.toggle_skip!(invoice, scope: scope)
    toggle_entry_skip(socket, id, new_skip)
  end

  # TODO: re-add Transaction struct constraints once legacy Ecto schema is removed
  defp toggle_transaction_skip(socket, id, new_skip) do
    entries =
      Enum.map(socket.assigns.invoicing_entries, fn
        %{__struct__: _, id: ^id, skip_invoicing: _} = tx ->
          Map.put(tx, :skip_invoicing, new_skip)

        %TransactionGroup{transactions: txns} = group ->
          updated =
            Enum.map(txns, fn
              %{__struct__: _, id: ^id, skip_invoicing: _} = tx ->
                Map.put(tx, :skip_invoicing, new_skip)

              other ->
                other
            end)

          %{group | transactions: updated}

        other ->
          other
      end)

    assign(socket, :invoicing_entries, entries)
  end

  # Generalized skip toggle for any entry with id and skip_invoicing fields
  defp toggle_entry_skip(socket, id, new_skip) do
    entries =
      Enum.map(socket.assigns.invoicing_entries, fn
        %{__struct__: _, id: ^id, skip_invoicing: _} = entry ->
          Map.put(entry, :skip_invoicing, new_skip)

        %TransactionGroup{transactions: txns} = group ->
          updated =
            Enum.map(txns, fn
              %{__struct__: _, id: ^id, skip_invoicing: _} = tx ->
                Map.put(tx, :skip_invoicing, new_skip)

              other ->
                other
            end)

          %{group | transactions: updated}

        other ->
          other
      end)

    assign(socket, :invoicing_entries, entries)
  end

  defp refetch_invoicing_entries(socket) do
    month = socket.assigns.params.month
    filter = socket.assigns.params.filter
    subfilter = socket.assigns.params.subfilter
    scope = socket.assigns.ash_scope
    date_range_from = Date.beginning_of_month(month)
    date_range_to = Date.end_of_month(month)

    entries = fetch_entries(date_range_from, date_range_to, filter, subfilter, scope)

    entries = group_cost_transactions_by_party(entries)

    socket = assign(socket, :invoicing_entries, entries)

    # Pending entries for badge count (no subfilter - we want all unmatched)
    pending_entries =
      fetch_entries(date_range_from, date_range_to, :unmatched, nil, scope)

    raw_pending_count = Enum.count(pending_entries)

    pending_invoicing_entries_count =
      pending_entries
      |> group_cost_transactions_by_party()
      |> Enum.count()

    # Check if any entries exist this month (regardless of filter)
    all_entries_count =
      date_range_from
      |> fetch_entries(date_range_to, :all, nil, scope)
      |> Enum.count()

    is_month_touched = all_entries_count > 0 or raw_pending_count > 0

    # No new transactions can be added after month ends
    has_month_ended =
      month
      |> Date.end_of_month()
      |> Date.compare(Date.utc_today()) == :lt

    socket =
      socket
      |> assign(:is_month_touched, is_month_touched)
      |> assign(:is_month_closed, is_month_touched and has_month_ended and raw_pending_count == 0)
      |> assign(:pending_invoicing_entries_count, pending_invoicing_entries_count)
      |> refetch_upload_counts()

    # Also fetch dashboard data (used when view_mode is :dashboard)
    fetch_dashboard_data(socket)
  end

  defp refetch_upload_counts(socket) do
    currently_uploading_count =
      case socket.assigns do
        %{uploads: %{file: upload}} ->
          length(Enum.filter(upload.entries, &(!&1.done?)))

        _ ->
          0
      end

    socket
    |> assign(
      :processing_blobs_count,
      Invoicing.get_processing_cost_invoices_count(socket.assigns.ash_scope)
    )
    |> assign(:currently_uploading_count, currently_uploading_count)
  end

  # ── Dashboard data fetching ─────────────────────────────────────────

  @dashboard_tile_limit 5

  defp fetch_dashboard_data(socket) do
    if socket.assigns.current_user.role == :admin do
      month = socket.assigns.params.month
      scope = socket.assigns.ash_scope
      date_range_from = Date.beginning_of_month(month)
      date_range_to = Date.end_of_month(month)

      unpaid_invoices = fetch_unpaid_invoices(date_range_from, date_range_to, scope)
      unmatched_transactions = fetch_unmatched_transactions(date_range_from, date_range_to, scope)
      matched_entries = fetch_matched_entries(date_range_from, date_range_to, scope)
      suggestions = fetch_suggestions(scope)

      socket
      |> assign(:dashboard_unpaid_invoices, unpaid_invoices.entries)
      |> assign(:dashboard_unpaid_invoices_count, unpaid_invoices.total_count)
      |> assign(:dashboard_unmatched_transactions, unmatched_transactions.entries)
      |> assign(:dashboard_unmatched_transactions_count, unmatched_transactions.total_count)
      |> assign(:dashboard_matched_entries, matched_entries.entries)
      |> assign(:dashboard_matched_entries_count, matched_entries.total_count)
      |> assign(:dashboard_suggestions, suggestions.entries)
      |> assign(:dashboard_suggestions_count, suggestions.total_count)
    else
      socket
      |> assign(:dashboard_unpaid_invoices, [])
      |> assign(:dashboard_unpaid_invoices_count, 0)
      |> assign(:dashboard_unmatched_transactions, [])
      |> assign(:dashboard_unmatched_transactions_count, 0)
      |> assign(:dashboard_matched_entries, [])
      |> assign(:dashboard_matched_entries_count, 0)
      |> assign(:dashboard_suggestions, [])
      |> assign(:dashboard_suggestions_count, 0)
    end
  end

  defp fetch_unpaid_invoices(from, to, scope) do
    cost_invoices =
      Invoicing.list_cost_invoices!(
        %{date_from: from, date_to: to, date_field: :due_date, reconciliation: :pending},
        load: @cost_invoice_loads,
        scope: scope
      )

    sales_invoices =
      Invoicing.list_sales_invoices!(
        %{
          date_from: from,
          date_to: to,
          date_field: :due_date,
          kind: :vat,
          reconciliation: :pending
        },
        load: @sales_invoice_loads,
        scope: scope
      )

    invoices = Enum.sort_by(cost_invoices ++ sales_invoices, &due_date_for_invoice/1, Date)

    %{entries: Enum.take(invoices, @dashboard_tile_limit), total_count: length(invoices)}
  end

  defp due_date_for_invoice(%CostInvoice{due_date: date}), do: date
  defp due_date_for_invoice(%SalesInvoice{due_date: date}), do: date

  defp fetch_unmatched_transactions(from, to, scope) do
    transactions =
      Finances.list_transactions!(%{date_from: from, date_to: to, reconciliation: :pending},
        load: [:cost_invoices, :sales_invoices],
        query: [sort: [booking_date: :desc]],
        scope: scope
      )

    %{entries: Enum.take(transactions, @dashboard_tile_limit), total_count: length(transactions)}
  end

  defp fetch_matched_entries(from, to, scope) do
    Invoicing.list_recently_matched_entries(from, to, scope,
      limit: @dashboard_tile_limit,
      cost_invoice_loads: @cost_invoice_loads,
      sales_invoice_loads: @sales_invoice_loads
    )
  end

  defp fetch_suggestions(scope) do
    suggestions = []

    # Check bank connection
    has_bank =
      [scope: scope]
      |> Finances.list_requisitions!()
      |> Enum.any?(&(&1.status == :accepted))

    suggestions =
      if has_bank do
        suggestions
      else
        [%{type: :connect_bank} | suggestions]
      end

    # Check KSeF connection
    has_ksef = Ksef.get_credential(scope) != nil

    suggestions =
      if has_ksef do
        suggestions
      else
        [%{type: :connect_ksef} | suggestions]
      end

    %{entries: suggestions, total_count: length(suggestions)}
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, :page_title, "Fakturowanie")
  end

  defp group_cost_transactions_by_party(entries) do
    # Separate transactions from other entries (invoices)
    # TODO: re-add Transaction struct constraints once legacy Ecto schema is removed
    {transactions, other_entries} =
      Enum.split_with(entries, fn
        %{__struct__: _, transaction_amount: _} -> true
        _ -> false
      end)

    # Split into cost (negative) and income (positive) transactions
    {cost_transactions, income_transactions} =
      Enum.split_with(transactions, fn %{transaction_amount: amount} ->
        Decimal.lt?(amount, 0)
      end)

    # Group cost transactions by creditor_name
    cost_by_party = Enum.group_by(cost_transactions, & &1.creditor_name)

    # Group income transactions by debtor_name
    income_by_party = Enum.group_by(income_transactions, & &1.debtor_name)

    # Process cost transaction groups
    {cost_groups, ungrouped_cost} =
      Enum.split_with(cost_by_party, fn {_party, txns} ->
        length(txns) >= 2 &&
          Enum.all?(txns, &groupable_transaction?/1)
      end)

    # Process income transaction groups
    {income_groups, ungrouped_income} =
      Enum.split_with(income_by_party, fn {_party, txns} ->
        length(txns) >= 2 &&
          Enum.all?(txns, &groupable_transaction?/1)
      end)

    # Build group structs
    cost_group_structs =
      Enum.map(cost_groups, fn {party, txns} ->
        build_transaction_group(party, txns)
      end)

    income_group_structs =
      Enum.map(income_groups, fn {party, txns} ->
        build_transaction_group(party, txns)
      end)

    # Flatten ungrouped transactions
    ungrouped_cost_flat = Enum.flat_map(ungrouped_cost, fn {_party, txns} -> txns end)
    ungrouped_income_flat = Enum.flat_map(ungrouped_income, fn {_party, txns} -> txns end)

    [
      cost_group_structs,
      income_group_structs,
      ungrouped_cost_flat,
      ungrouped_income_flat,
      other_entries
    ]
    |> Enum.concat()
    |> order_entries_for_display()
  end

  defp groupable_transaction?(%Transaction{creditor_name: "N/A"}), do: false
  defp groupable_transaction?(%Transaction{creditor_name: ""}), do: false
  defp groupable_transaction?(%Transaction{creditor_name: nil}), do: false

  defp groupable_transaction?(%Transaction{skip_invoicing: skip, cost_invoices: cost, sales_invoices: sales}) do
    not skip and cost == [] and sales == []
  end

  defp groupable_transaction?(_), do: false

  defp build_transaction_group(party, transactions) do
    total =
      Enum.reduce(transactions, Decimal.new(0), fn t, acc ->
        Decimal.add(acc, t.transaction_amount)
      end)

    # Use LATEST date for sorting
    latest_transaction = Enum.max_by(transactions, & &1.booking_date, Date)

    # Generate stable ID from party name
    id = "group-#{:erlang.phash2(party)}"

    %TransactionGroup{
      id: id,
      party: party,
      total: total,
      count: length(transactions),
      currency: latest_transaction.transaction_currency,
      date: latest_transaction.booking_date,
      transactions: transactions
    }
  end

  # ── Entries — direct resource calls ─────────────────────────────────

  defp fetch_entries(from, to, filter, subfilter, scope) do
    case {filter, subfilter} do
      {:all, _} ->
        [
          list_cost_invoices(from, to, %{date_field: :issue_date}, scope),
          list_sales_invoices(from, to, %{date_field: :issue_date, kind: :vat}, scope),
          list_transactions(from, to, %{}, scope)
        ]
        |> Enum.concat()
        |> order_entries_for_display()

      {:unmatched, _} ->
        [
          list_cost_invoices(from, to, %{date_field: :due_date, reconciliation: :pending}, scope),
          list_sales_invoices(
            from,
            to,
            %{date_field: :due_date, kind: :vat, reconciliation: :pending},
            scope
          ),
          list_transactions(from, to, %{reconciliation: :pending}, scope)
        ]
        |> Enum.concat()
        |> order_entries_for_display()

      # Faktury tab with subfilters
      {:invoices, :oplacone} ->
        [
          list_cost_invoices(
            from,
            to,
            %{date_field: :issue_date, reconciliation: :matched},
            scope
          ),
          list_sales_invoices(
            from,
            to,
            %{date_field: :issue_date, kind: :vat, reconciliation: :matched},
            scope
          )
        ]
        |> Enum.concat()
        |> order_entries_for_display()

      {:invoices, :nieoplacone} ->
        [
          list_cost_invoices(
            from,
            to,
            %{date_field: :issue_date, reconciliation: :pending},
            scope
          ),
          list_sales_invoices(
            from,
            to,
            %{date_field: :issue_date, kind: :vat, reconciliation: :pending},
            scope
          )
        ]
        |> Enum.concat()
        |> order_entries_for_display()

      {:invoices, _} ->
        [
          list_cost_invoices(from, to, %{date_field: :issue_date}, scope),
          list_sales_invoices(from, to, %{date_field: :issue_date, kind: :vat}, scope)
        ]
        |> Enum.concat()
        |> order_entries_for_display()

      # Transakcje tab with subfilters
      {:transactions, :dopasowane} ->
        from
        |> list_transactions(to, %{reconciliation: :matched}, scope)
        |> order_entries_for_display()

      {:transactions, :bez_dokumentu} ->
        from
        |> list_transactions(to, %{reconciliation: :pending}, scope)
        |> order_entries_for_display()

      {:transactions, _} ->
        from
        |> list_transactions(to, %{}, scope)
        |> order_entries_for_display()
    end
  end

  defp list_cost_invoices(from, to, extra_args, scope) do
    args = Map.merge(%{date_from: from, date_to: to, corrections: :exclude}, extra_args)
    Invoicing.list_cost_invoices!(args, load: @cost_invoice_loads, scope: scope)
  end

  defp list_sales_invoices(from, to, extra_args, scope) do
    args = Map.merge(%{date_from: from, date_to: to}, extra_args)

    Invoicing.list_sales_invoices!(args, load: @sales_invoice_loads, scope: scope)
  end

  defp list_transactions(from, to, extra_args, scope) do
    args = Map.merge(%{date_from: from, date_to: to}, extra_args)

    Finances.list_transactions!(args,
      load: [:cost_invoices, :sales_invoices, :bank_account],
      query: [sort: [booking_date: :desc]],
      scope: scope
    )
  end

  # ── Active months — 3 Ash reads + Elixir dedup ─────────────────────

  defp get_active_months(scope) do
    scope_opts = [scope: scope]

    sales_months =
      SalesInvoice
      |> Ash.Query.select([:issue_date])
      |> Ash.Query.for_read(:read, %{}, scope_opts)
      |> Ash.read!(scope_opts)
      |> Enum.map(& &1.issue_date)

    cost_months =
      CostInvoice
      |> Ash.Query.select([:issue_date])
      |> Ash.Query.for_read(:read, %{}, scope_opts)
      |> Ash.read!(scope_opts)
      |> Enum.map(& &1.issue_date)

    tx_months =
      Transaction
      |> Ash.Query.select([:booking_date])
      |> Ash.Query.for_read(:read, %{}, scope_opts)
      |> Ash.read!(scope_opts)
      |> Enum.map(& &1.booking_date)

    (sales_months ++ cost_months ++ tx_months)
    |> Enum.map(&Date.beginning_of_month/1)
    |> Enum.uniq()
    |> Enum.sort(Date)
  end

  # ── Entry sorting for display ──────────────────────────────────────

  @doc false
  defp order_entries_for_display(entries) do
    Enum.sort(entries, fn a, b ->
      cond do
        # Draft invoices first (only SalesInvoice)
        entry_draft?(a) != entry_draft?(b) ->
          entry_draft?(a)

        entry_matched?(a) != entry_matched?(b) ->
          # Unmatched first
          not entry_matched?(a)

        entry_date(a) != entry_date(b) ->
          # Newer first
          Date.after?(entry_date(a), entry_date(b))

        # Invoice number descending (only SalesInvoice)
        (inv_a = entry_invoice_number(a)) != (inv_b = entry_invoice_number(b)) ->
          inv_a >= inv_b

        true ->
          a.id < b.id
      end
    end)
  end

  defp entry_date(%SalesInvoice{issue_date: date}), do: date
  defp entry_date(%CostInvoice{issue_date: date}), do: date
  defp entry_date(%Transaction{booking_date: date}), do: date
  defp entry_date(%TransactionGroup{date: date}), do: date

  defp entry_matched?(%SalesInvoice{} = inv), do: Enum.any?(inv.transactions) or Map.get(inv, :skip_invoicing, false)

  defp entry_matched?(%CostInvoice{} = inv), do: Enum.any?(inv.transactions) or Map.get(inv, :skip_invoicing, false)

  defp entry_matched?(%Transaction{} = tx), do: Enum.any?(tx.cost_invoices ++ tx.sales_invoices) or tx.skip_invoicing

  # Groups only contain unmatched transactions by design
  defp entry_matched?(%TransactionGroup{}), do: false
  defp entry_matched?(_), do: false

  # Draft = no invoice number assigned (only SalesInvoice)
  defp entry_draft?(%SalesInvoice{invoice_number: num}), do: is_nil(num)
  defp entry_draft?(_), do: false

  defp entry_invoice_number(%SalesInvoice{invoice_number: num}), do: num
  defp entry_invoice_number(_), do: nil
end
