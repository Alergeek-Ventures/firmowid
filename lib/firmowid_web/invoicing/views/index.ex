# credo:disable-for-this-file ExDNA.Credo
# This LiveView currently combines orchestration for uploads, PubSub, and invoice grouping;
# removing duplication requires extracting domain-facing services across feature boundaries.
defmodule FirmowidWeb.Invoicing.Views.Index do
  @moduledoc false
  # TODO: move business logic (transaction grouping by party, get_active_months)
  # to domain actions/calculations — LiveView should only handle presentation
  use FirmowidWeb, :live_view

  import FirmowidUI.Components.Button
  import FirmowidUI.Components.Link
  import FirmowidWeb.Core.PubSubDebounce
  import FirmowidWeb.DesignSystem.Components.MonthPicker
  import FirmowidWeb.Infrastructure.Flags, only: [flag_enabled?: 2]
  import FirmowidWeb.Infrastructure.Hooks.RequireOrganization, only: [guard_upload_progress: 2]
  import Phoenix.Component, except: [link: 1]

  alias Ash.Notifier.Notification
  alias Firmowid.Analysis
  alias Firmowid.Analysis.TagDefinition
  alias Firmowid.Blobs
  alias Firmowid.Blobs.Blob
  alias Firmowid.Finances
  alias Firmowid.Finances.BankAccount
  alias Firmowid.Finances.Requisition
  alias Firmowid.Finances.Transaction
  alias Firmowid.Invoicing
  alias Firmowid.Invoicing.CostInvoice
  alias Firmowid.Invoicing.SalesInvoice
  alias Firmowid.Invoicing.TransactionGroup
  alias Firmowid.Ksef
  alias FirmowidWeb.Analysis.Components.ProjectCell
  alias FirmowidWeb.Analysis.Utilities.CategoryColors
  alias FirmowidWeb.Core.Endpoint
  alias FirmowidWeb.Infrastructure.Components.BlobProcessingToasts
  alias FirmowidWeb.Infrastructure.UserAuth
  alias FirmowidWeb.Infrastructure.Utilities.PosthogBusinessEvents
  alias FirmowidWeb.Invoicing.Components.EntriesTable
  alias FirmowidWeb.Invoicing.Utilities.Navigation
  alias FirmowidWeb.Invoicing.Utilities.QueryCodec
  alias Phoenix.Socket.Broadcast

  # Load definitions for invoice queries
  @cost_invoice_loads [
    :invoice_source,
    :transactions,
    :effective_amount,
    :effective_due_date,
    :effective_seller_display_name
  ]
  @sales_invoice_loads [
    :invoice_source,
    :effective_amount,
    :effective_due_date,
    :sales_invoice_items,
    :buyer_display_name_label,
    :transactions,
    corrections: :sales_invoice_items,
    latest_correction: :sales_invoice_items
  ]

  # Rendering every row of every month at once takes seconds, so the list of every
  # month shows a window of a few months and widens it as either end comes into view.
  @window_months 3

  @impl true
  def mount(_params, _session, socket) do
    if can_view_invoicing?(socket.assigns.current_user) do
      mount_invoicing(socket)
    else
      {:ok,
       redirect(socket,
         to:
           UserAuth.signed_in_path_for_user(
             socket.assigns.current_user,
             socket.assigns.current_org.id
           )
       )}
    end
  end

  defp mount_invoicing(socket) do
    user = socket.assigns.current_user
    organization_id = user.member.organization_id

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
      Endpoint.subscribe("bank_account:synced:#{organization_id}")
      Endpoint.subscribe("bank_account:sync_failed:#{organization_id}")
      Endpoint.subscribe("requisition:linked:#{organization_id}")
      Endpoint.subscribe("requisition:rejected:#{organization_id}")
      Endpoint.subscribe("requisition:expired:#{organization_id}")
      Endpoint.subscribe("requisition:error:#{organization_id}")
      # KSeF status (separate system)
      Ksef.subscribe_ksef_status(organization_id)
    end

    socket =
      if can_write_invoicing?(user) do
        allow_upload(socket, :file,
          max_entries: 50,
          accept: ["application/pdf", "image/*"],
          progress: guard_upload_progress(&handle_progress/3, :ash_scope),
          auto_upload: true
        )
      else
        socket
      end

    socket =
      socket
      |> assign(:page_title, "Fakturowanie")
      |> assign(:projects_column, nil)

    active_months =
      get_active_months(socket.assigns.ash_scope) ++
        [Date.beginning_of_month(Date.utc_today())]

    socket = assign(socket, :active_months, active_months)

    skipped_ksef_sales_invoices =
      Invoicing.list_skipped_ksef_sales_invoices!(scope: socket.assigns.ash_scope)

    socket = assign(socket, :skipped_ksef_sales_invoices, skipped_ksef_sales_invoices)

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
    [drop_before, drop_after] =
      "Drag invoices here to%{line_break}upload them to Firmowid."
      |> gettext(line_break: "__BREAK__")
      |> String.split("__BREAK__", parts: 2)

    assigns = assign(assigns, drop_before: drop_before, drop_after: drop_after)

    ~H"""
    <div class={
      [
        "sticky top-navbar z-10 flex justify-between bg-grey-100 py-4 max-md:static max-md:z-auto max-md:flex-col max-md:gap-3",
        # above the bar as much room as between it and the column headings below it, the same
        # before and while scrolling: the bar starts at the top of the page, as it sticks there
        @all_months? && "md:-mt-4 md:pt-11 md:pb-3"
      ]
    }>
      <div class="flex items-center gap-4 max-md:gap-3">
        <%!-- On the list of every month the label is the month scrolled to, set in the browser;
             the server renders the first one and leaves the input alone afterwards. --%>
        <.month_picker
          id="month"
          show_on_mobile
          active_months={@active_months}
          selected_date={@params.month}
          value={@all_months? && EntriesTable.month_label(@params.month)}
          widest_value={@all_months? && widest_month_label(@params.month)}
          phx-update={@all_months? && "ignore"}
          class="max-md:h-12 max-md:flex-1"
        />

        <.button
          :if={not @all_months?}
          type="button"
          variant="secondary"
          size="big"
          id="open-search"
          class="max-md:size-12 max-md:justify-center"
          phx-click="open-search"
          aria-label={gettext("Search invoices")}
          phx-hook="Tippy"
          data-tippy-content={gettext("Search invoices")}
        >
          <Lucideicons.search />
        </.button>
      </div>

      <%!-- On the list of every month, the picker scrolls to the month and the filters take the search's place, centred in the bar. --%>
      <FirmowidWeb.Invoicing.Components.FilterBar.inbox_filters :if={@all_months?} params={@params} />

      <div
        phx-drop-target={can_write_invoicing?(@current_user) && @uploads.file.ref}
        class="flex flex-row gap-4 max-md:contents"
      >
        <%= if @invoicing_entries != [] do %>
          <.live_component
            id="download-component"
            module={FirmowidWeb.Invoicing.Components.DownloadModal}
            month={(@all_months? && @visible_month) || @params.month}
          />
        <% end %>
        <.page_actions :if={can_write_invoicing?(@current_user)} label={gettext("Add invoice")}>
          <:action>
            <form id="upload-form" phx-change="upload" phx-submit="upload">
              <div class="hidden">
                <.live_file_input upload={@uploads.file} />
              </div>
              <FirmowidUI.Components.Button.button
                as="label"
                for={@uploads.file.ref}
                variant="secondary"
                accent="rust"
                class="relative"
                data-fab
              >
                <%= if @currently_uploading_count > 0 or @processing_blobs_count > 0 do %>
                  <span
                    id="upload-count-indicator"
                    phx-hook="Tippy"
                    data-tippy-content={
                      gettext(
                        "The files are being processed and will be available in Firmowid in a few moments"
                      )
                    }
                    class="absolute -top-3 -right-3 flex size-7 items-center justify-center overflow-hidden rounded-full bg-grey-100"
                  >
                    <span class="absolute block size-full animate-pulse bg-rust-600" />
                    <span class="z-10 flex size-5 items-center justify-center rounded-full bg-grey-100">
                      <Lucideicons.arrow_up
                        :if={@currently_uploading_count > 0 or @processing_blobs_count == 1}
                        class="size-4 leading-none text-rust-900"
                      />
                      <span :if={@currently_uploading_count == 0 and @processing_blobs_count > 1}>
                        {@processing_blobs_count}
                      </span>
                    </span>
                  </span>
                <% else %>
                  <span
                    id="upload-count-indicator"
                    phx-hook="Tippy"
                    data-tippy-content={
                      gettext(
                        "Invoices from foreign counterparties as PDF files or their photos (PNG, JPG)"
                      )
                    }
                    class="absolute top-0 left-0 size-full"
                  />
                <% end %>
                <Lucideicons.file_input />
                <span class="block sm:grow sm:text-center md:max-lg:sr-only">
                  {gettext("Invoice from outside KSeF")}
                </span>
              </FirmowidUI.Components.Button.button>
            </form>
          </:action>
          <:action>
            <.link
              navigate={Navigation.sales_invoice_creator_path()}
              kind="button"
              variant="secondary"
              accent="teal"
              id="sales-invoice-link"
              data-fab
            >
              <Lucideicons.file_pen_line class="size-5" />
              <span class="max-xl:sr-only max-md:not-sr-only">
                {gettext("Issue invoice")}
              </span>
            </.link>
          </:action>
        </.page_actions>
      </div>
    </div>
    <.live_component
      module={FirmowidWeb.Invoicing.Components.SearchOverlay}
      id="invoice-search-overlay"
      show_search={@show_search}
      search_query={@search_query}
      search_results={@search_results}
    />

    <%!-- With the inbox sidebar, invoices and transactions are separate places and the inbox takes the summary. --%>
    <FirmowidWeb.Invoicing.Components.FilterBar.filter_bar
      :if={not flag_enabled?(:inbox, assigns)}
      params={@params}
      pending_count={@pending_invoicing_entries_count}
      is_month_closed={@is_month_closed}
      is_month_touched={@is_month_touched}
    />
    <div class="relative mt-2 flex flex-col gap-4">
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
            return_to={Navigation.invoicing_index_path(@params)}
          />
        <% @is_month_closed and @params.filter == :unmatched -> %>
          <.live_component
            id="month-closed-zero-state"
            module={FirmowidWeb.Invoicing.Components.MonthClosedZeroState}
            month={@params.month}
          />
        <% true -> %>
          <EntriesTable.table
            mode={@params.filter}
            invoicing_entries={window_entries(@invoicing_entries, @month_window)}
            load_newer={newer_months?(@month_window) && "load-newer-months"}
            load_more={older_months?(@invoicing_entries, @month_window) && "load-older-months"}
            return_to={Navigation.invoicing_index_path(@params)}
            can_write_invoicing={can_write_invoicing?(@current_user)}
            projects={@projects_column}
          />
      <% end %>

      <div
        :if={can_write_invoicing?(@current_user)}
        id="file-drop-overlay"
        class="absolute -inset-3 z-20 hidden rounded-lg border-2 border-teal-200 bg-[#EDF5F599] opacity-60 transition-opacity"
        phx-hook="FileUploadDragNDrop"
        phx-drop-target={can_write_invoicing?(@current_user) && @uploads.file.ref}
      >
        <div class="sticky top-0 flex size-full max-h-dvh items-center justify-center">
          <div class="flex w-fit flex-col items-center gap-6 rounded-4xl bg-teal-200 px-10 pt-6 pb-8 text-teal-700">
            <.icon name="hero-cloud-arrow-up" class="size-16" />
            <p class="text-center text-xl font-medium">
              {@drop_before}<br />{@drop_after}
            </p>
            <p class="max-w-sm text-center text-sm text-teal-600">
              {gettext("(max 50 files, PDF, JPG and PNG)")}
            </p>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_params(params, _url, socket) do
    parsed = Navigation.parse_invoicing_index_params(params)

    socket =
      socket
      |> assign(:params, parsed)
      |> then(&assign(&1, :all_months?, all_months_list?(&1.assigns)))
      |> assign(:month_window, {0, @window_months})
      # Kept across patches, like the hook's own record of the month it last reported.
      |> assign_new(:visible_month, fn -> nil end)
      |> refetch_invoicing_entries()

    {:noreply, socket}
  end

  @impl true
  def handle_event("skipped-ksef-sales-invoices-viewed", _params, socket) do
    if socket.assigns.skipped_ksef_sales_invoices != [] do
      PosthogBusinessEvents.capture(socket, :ksef_skipped_sales_invoices_banner_viewed, %{
        skipped_invoice_count: length(socket.assigns.skipped_ksef_sales_invoices)
      })
    end

    {:noreply, socket}
  end

  # The list of every month already holds the chosen one, so the picker only scrolls
  # to it, first moving the window there when the month is not shown.
  def handle_event("change-month", %{"month" => month}, socket) do
    if socket.assigns.all_months? do
      target = Date.from_iso8601!(month)
      months = for {:month, month} <- socket.assigns.invoicing_entries, do: month
      # Months run newest first; a month without entries opens the next older one,
      # and a month older than every entry has nothing to show, so the hook only puts
      # the picker back on the month on screen.
      case Enum.find_index(months, &(Date.compare(&1, target) != :gt)) do
        nil ->
          {:noreply, push_event(socket, "scroll-to-month", %{month: month})}

        index ->
          {first, count} = socket.assigns.month_window

          window =
            if index in first..(first + count - 1)//1,
              do: {first, count},
              else: {index, @window_months}

          {:noreply,
           socket
           |> assign(:month_window, window)
           |> push_event("scroll-to-month", %{month: month})}
      end
    else
      {:noreply, update_param(socket, :month, Date.from_iso8601!(month))}
    end
  end

  # The list of every month downloads the month on screen, which the picker names.
  def handle_event("visible-month", %{"month" => month}, socket) do
    {:noreply, assign(socket, :visible_month, Date.from_iso8601!(month))}
  end

  def handle_event("load-older-months", _params, socket) do
    {:noreply, update(socket, :month_window, fn {first, count} -> {first, count + @window_months} end)}
  end

  def handle_event("load-newer-months", _params, socket) do
    {:noreply,
     update(socket, :month_window, fn {first, count} ->
       newer = min(first, @window_months)
       {first - newer, count + newer}
     end)}
  end

  def handle_event("change-filter", %{"filter" => filter}, socket) do
    case QueryCodec.parse_filter(filter) do
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
    case QueryCodec.parse_subfilter(subfilter) do
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
          Navigation.cost_invoice_show_path(
            id,
            Navigation.invoicing_index_path(socket.assigns.params)
          )

        "sales" ->
          Navigation.sales_invoice_show_path(
            id,
            Navigation.invoicing_index_path(socket.assigns.params)
          )
      end

    {:noreply, push_navigate(socket, to: path)}
  end

  @impl true
  def handle_info(%Broadcast{payload: %Notification{resource: Transaction}}, socket) do
    {:noreply, debounce_refetch(socket, :invoicing_entries, 10_000)}
  end

  # A project assigned in one row also shows on the transaction paying that invoice.
  @impl true
  def handle_info(:projects_changed, socket), do: {:noreply, refetch_invoicing_entries(socket)}

  def handle_info({:debounced_refetch, :invoicing_entries}, socket) do
    {:noreply, refetch_invoicing_entries(socket)}
  end

  # Blob created — file is being processed, refresh list
  @impl true
  def handle_info(
        %Broadcast{
          payload: %Notification{resource: Blob, data: %{processing_target: :cost_invoice}, action: %{type: :create}}
        },
        socket
      ) do
    {:noreply, refetch_invoicing_entries(socket)}
  end

  # Blob updated — processing state transitions
  @impl true
  def handle_info(
        %Broadcast{
          payload: %Notification{
            resource: Blob,
            action: %{type: :update},
            data: %{processing_target: :cost_invoice} = blob
          }
        },
        socket
      ) do
    if blob.processing_state == :failed do
      BlobProcessingToasts.show_failure_toast(blob)
    end

    {:noreply, refetch_invoicing_entries(socket)}
  end

  # Blob destroyed — processing failed
  @impl true
  def handle_info(
        %Broadcast{
          payload:
            %Notification{
              resource: Blob,
              data: %{processing_target: :cost_invoice},
              action: %{type: :destroy},
              metadata: %{reason: :processing_failed}
            } = notification
        },
        socket
      ) do
    LiveToast.send_toast(:error, notification.data.original_filename, title: gettext("Failed to upload the file"))

    {:noreply, refetch_invoicing_entries(socket)}
  end

  # Blob destroyed — invalid document uploaded
  @impl true
  def handle_info(
        %Broadcast{
          payload:
            %Notification{
              resource: Blob,
              data: %{processing_target: :cost_invoice},
              action: %{type: :destroy},
              metadata: %{reason: :invalid_document}
            } = notification
        },
        socket
      ) do
    LiveToast.send_toast(
      :error,
      gettext(
        "The file %{filename} does not contain the required data. Make sure you are uploading an invoice, receipt or bill.",
        filename: notification.data.original_filename
      ),
      title: gettext("Invalid document")
    )

    {:noreply, socket}
  end

  # Blob destroyed — normal cleanup (delete invoice, etc.)
  @impl true
  def handle_info(
        %Broadcast{
          payload: %Notification{resource: Blob, data: %{processing_target: :cost_invoice}, action: %{type: :destroy}}
        },
        socket
      ) do
    {:noreply, refetch_invoicing_entries(socket)}
  end

  # Blobs of other targets (attachments, employment contracts) share the topics
  def handle_info(%Broadcast{payload: %Notification{resource: Blob}}, socket) do
    {:noreply, socket}
  end

  # Cost invoice created — show success toast with link
  @impl true
  def handle_info(
        %Broadcast{payload: %Notification{resource: CostInvoice, action: %{type: :create}} = notification},
        socket
      ) do
    socket = refetch_invoicing_entries(socket)
    cost_invoice = notification.data
    cost_invoice_path = Navigation.cost_invoice_show_path(cost_invoice)

    LiveToast.send_toast(
      :success,
      "#{cost_invoice.issue_date} / #{cost_invoice.seller_display_name}",
      title: gettext("Invoice uploaded"),
      action: fn assigns ->
        assigns = assign(assigns, :cost_invoice_path, cost_invoice_path)

        ~H"""
        <.link
          kind="unstyled"
          class="text-sm font-bold underline"
          navigate={@cost_invoice_path}
        >
          {gettext("View")} <.icon name="hero-arrow-right-solid" class="size-3" />
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
      title: gettext("Invoice matched with a transaction"),
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
          class="text-sm font-bold underline"
          navigate={
            Navigation.invoicing_index_path(%{
              month: @issue_date,
              filter: :invoices,
              subfilter: nil,
              view_mode: :dashboard
            })
          }
        >
          {gettext("View")} <.icon name="hero-arrow-right-solid" class="size-3" />
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

  def handle_info(%Broadcast{payload: %Notification{resource: BankAccount}}, socket) do
    {:noreply, fetch_dashboard_data(socket)}
  end

  # Handle Ash native PubSub broadcasts for requisition status changes
  def handle_info(
        %Broadcast{topic: "requisition:" <> _, payload: %Notification{resource: Requisition, action: action}},
        socket
      ) do
    {toast_type, message} =
      case action do
        :accept ->
          {:success, gettext("The bank account was connected successfully!")}

        :reject ->
          {:error, gettext("The bank connection was rejected. Please try again.")}

        :handle_check_error ->
          {:error, gettext("An error occurred while connecting the bank account. Please try again.")}

        _ ->
          {:info, gettext("The bank connection status has been updated.")}
      end

    LiveToast.send_toast(toast_type, message)

    {:noreply, fetch_dashboard_data(socket)}
  end

  defp update_param(socket, key, value) do
    params = Map.put(socket.assigns.params, key, value)
    update_params(socket, params)
  end

  defp update_params(socket, params) do
    push_patch(socket, to: Navigation.invoicing_index_path(params))
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
        path
        |> Blobs.create_or_retry_cost_invoice_blob(entry.client_type, entry.client_name, scope: scope)
        |> handle_upload_result()

        {:ok, nil}
      end)
    end
  end

  defp handle_upload_result({:ok, {:existing_cost_invoice, cost_invoice}}) do
    LiveToast.send_toast(
      :info,
      gettext("This invoice is already in the system"),
      title: gettext("Duplicate file"),
      action: fn assigns ->
        assigns = assign(assigns, :cost_invoice_id, cost_invoice.id)

        ~H"""
        <.link
          kind="unstyled"
          class="text-sm font-bold underline"
          navigate={Navigation.cost_invoice_show_path(@cost_invoice_id)}
        >
          {gettext("View")} <.icon name="hero-arrow-right-solid" class="size-3" />
        </.link>
        """
      end
    )
  end

  defp handle_upload_result({:ok, :blob_already_processing}) do
    LiveToast.send_toast(:info, gettext("This file is already being processed"))
  end

  defp handle_upload_result({:ok, :blob_reprocessing_started}) do
    LiveToast.send_toast(:info, gettext("The file was added to the processing queue again"))
  end

  defp handle_upload_result({:error, :blob_already_exists}) do
    LiveToast.send_toast(:info, gettext("This invoice is already in the system"))
  end

  defp handle_upload_result(_result), do: nil

  defp do_toggle_skip(socket, id, "transaction") do
    scope = socket.assigns.ash_scope
    tx = Finances.get_transaction!(id, scope: scope)

    updated_transaction =
      Finances.set_transaction_skip_invoicing!(tx, %{skip_invoicing: !tx.skip_invoicing},
        load: [:reconciliation_status],
        scope: scope
      )

    update_entry(
      socket,
      id,
      Map.take(updated_transaction, [:skip_invoicing, :reconciliation_status])
    )
  end

  defp do_toggle_skip(socket, id, "cost_invoice") do
    scope = socket.assigns.ash_scope
    cost_invoice = Invoicing.get_cost_invoice!(id, scope: scope)
    new_skip = !cost_invoice.skip_invoicing
    Invoicing.toggle_cost_invoice_skip!(cost_invoice, scope: scope)
    update_entry(socket, id, %{skip_invoicing: new_skip})
  end

  defp do_toggle_skip(socket, id, "sales_invoice") do
    scope = socket.assigns.ash_scope
    invoice = SalesInvoice.by_id!(id, scope: scope)
    new_skip = !invoice.skip_invoicing
    SalesInvoice.toggle_skip!(invoice, scope: scope)
    update_entry(socket, id, %{skip_invoicing: new_skip})
  end

  # A row may also sit inside a group of one party's transactions.
  defp update_entry(socket, id, changes) do
    update = fn
      %{id: ^id} = entry -> Map.merge(entry, changes)
      other -> other
    end

    entries =
      Enum.map(socket.assigns.invoicing_entries, fn
        %TransactionGroup{} = group ->
          %{group | transactions: Enum.map(group.transactions, update)}

        entry ->
          update.(entry)
      end)

    assign(socket, :invoicing_entries, entries)
  end

  # Analysis members assign entries to the projects active in the month, behind the analysis flag.
  defp projects_column(assigns, month, scope) do
    if flag_enabled?(:analysis_dashboard, assigns) and
         scope.actor.member.role in [:admin, :accountant] do
      %{
        projects: Analysis.list_available_categories(month, scope),
        colors: CategoryColors.for_definitions(TagDefinition.list_tag_definitions!(scope: scope)),
        scope: scope,
        can_write: true
      }
    end
  end

  defp refetch_invoicing_entries(socket) do
    month = socket.assigns.params.month
    filter = socket.assigns.params.filter
    subfilter = socket.assigns.params.subfilter
    scope = socket.assigns.ash_scope
    date_range_from = Date.beginning_of_month(month)
    date_range_to = Date.end_of_month(month)
    all_months? = socket.assigns.all_months?

    # The inbox lists of invoices and transactions show every month, newest first.
    fetched_entries =
      if all_months?,
        do: fetch_entries(nil, nil, filter, subfilter, scope),
        else: fetch_entries(date_range_from, date_range_to, filter, subfilter, scope)

    projects_column = projects_column(socket.assigns, month, scope)

    entries =
      if projects_column,
        do: ProjectCell.preload(fetched_entries, scope),
        else: fetched_entries

    entries =
      if all_months?,
        do: with_month_separators(entries),
        else: group_cost_transactions_by_party(entries)

    socket
    |> assign(:invoicing_entries, entries)
    |> assign(:projects_column, projects_column)
    |> assign_month_status(fetched_entries)
    |> refetch_upload_counts()
    |> fetch_dashboard_data()
  end

  # The month's lists of unmatched and of all entries ignore the subfilter, so the list
  # read serves for them when it is one of the two.
  defp assign_month_status(socket, fetched_entries) do
    %{month: month, filter: filter} = socket.assigns.params
    scope = socket.assigns.ash_scope
    date_range_from = Date.beginning_of_month(month)
    date_range_to = Date.end_of_month(month)

    # Pending entries for badge count (no subfilter - we want all unmatched)
    pending_entries =
      if filter == :unmatched,
        do: fetched_entries,
        else: fetch_entries(date_range_from, date_range_to, :unmatched, nil, scope)

    raw_pending_count = Enum.count(pending_entries)

    pending_invoicing_entries_count =
      pending_entries
      |> group_cost_transactions_by_party()
      |> Enum.count()

    # Check if any entries exist this month (regardless of filter)
    is_month_touched =
      cond do
        raw_pending_count > 0 -> true
        filter == :all -> fetched_entries != []
        true -> fetch_entries(date_range_from, date_range_to, :all, nil, scope) != []
      end

    # No new transactions can be added after month ends
    has_month_ended =
      month
      |> Date.end_of_month()
      |> Date.compare(Date.utc_today()) == :lt

    socket
    |> assign(:is_month_touched, is_month_touched)
    |> assign(:is_month_closed, is_month_touched and has_month_ended and raw_pending_count == 0)
    |> assign(:pending_invoicing_entries_count, pending_invoicing_entries_count)
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
      Blobs.get_processing_blobs_count(:cost_invoice, socket.assigns.ash_scope)
    )
    |> assign(:currently_uploading_count, currently_uploading_count)
  end

  @dashboard_tile_limit 5

  # Only the dashboard shows its tiles; the lists leave them unread.
  defp fetch_dashboard_data(%{assigns: %{params: %{view_mode: :dashboard}}} = socket) do
    month = socket.assigns.params.month
    scope = socket.assigns.ash_scope
    date_range_from = Date.beginning_of_month(month)
    date_range_to = Date.end_of_month(month)

    unpaid_invoices = fetch_unpaid_invoices(date_range_from, date_range_to, scope)
    unmatched_transactions = fetch_unmatched_transactions(date_range_from, date_range_to, scope)
    matched_entries = fetch_matched_entries(date_range_from, date_range_to, scope)
    # With the inbox sidebar, bank accounts have their own settings page.
    bank_accounts_path =
      if flag_enabled?(:inbox, socket.assigns),
        do: ~p"/ustawienia/konta-bankowe",
        else: ~p"/ustawienia/firma"

    suggestions =
      fetch_suggestions(scope, socket.assigns.skipped_ksef_sales_invoices, bank_accounts_path)

    socket
    |> assign(:dashboard_unpaid_invoices, unpaid_invoices.entries)
    |> assign(:dashboard_unpaid_invoices_count, unpaid_invoices.total_count)
    |> assign(:dashboard_unmatched_transactions, unmatched_transactions.entries)
    |> assign(:dashboard_unmatched_transactions_count, unmatched_transactions.total_count)
    |> assign(:dashboard_matched_entries, matched_entries.entries)
    |> assign(:dashboard_matched_entries_count, matched_entries.total_count)
    |> assign(:dashboard_suggestions, suggestions.entries)
    |> assign(:dashboard_suggestions_count, suggestions.total_count)
  end

  defp fetch_dashboard_data(socket), do: socket

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
          reconciliation: :pending,
          submission: :confirmed
        },
        load: @sales_invoice_loads,
        scope: scope
      )

    invoices = Enum.sort_by(cost_invoices ++ sales_invoices, & &1.effective_due_date, Date)

    %{entries: Enum.take(invoices, @dashboard_tile_limit), total_count: length(invoices)}
  end

  defp fetch_unmatched_transactions(from, to, scope) do
    transactions =
      Finances.list_transactions!(%{date_from: from, date_to: to, reconciliation: :pending},
        load: [
          :direction,
          :signed_amount,
          :counterparty_display_name
        ],
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

  defp bank_attention_entries(scope, bank_accounts_path) do
    [scope: scope, load: [:requisition, :broken?]]
    |> Finances.list_bank_accounts!()
    # Keep the latest outcome independent of the last-success aggregate's filter.
    |> Ash.load!(:latest_successful_sync_at, scope: scope)
    |> Enum.filter(fn account ->
      not is_nil(account.gocardless_id) and
        (bank_connection_warning?(account) or awaiting_bank_sync?(account))
    end)
    |> Enum.group_by(&(&1.institution_id || &1.institution_name || &1.id))
    |> Enum.map(fn {_institution, accounts} ->
      account =
        Enum.find(accounts, &match?(%Requisition{status: :expired}, &1.requisition)) ||
          Enum.find(accounts, &bank_connection_warning?/1) || hd(accounts)

      # Show the oldest known gap among this bank's affected accounts.
      unsynced_since =
        accounts
        |> Enum.map(& &1.latest_successful_sync_at)
        |> Enum.reject(&is_nil/1)
        |> Enum.sort(DateTime)
        |> List.first()

      %{
        type: :bank_connection_attention,
        account: account,
        warning?: Enum.any?(accounts, &bank_connection_warning?/1),
        unsynced_since: unsynced_since,
        navigate:
          if(scope.actor.member.role == :admin,
            do: "#{bank_accounts_path}#konto-bankowe-#{account.id}"
          )
      }
    end)
    |> Enum.sort_by(&{not &1.warning?, &1.account.institution_name || ""})
  end

  defp fetch_suggestions(scope, skipped_invoices, bank_accounts_path) do
    bank_alerts = bank_attention_entries(scope, bank_accounts_path)

    ksef_warnings =
      if skipped_invoices == [] do
        []
      else
        [
          %{
            type: :skipped_ksef_sales_invoices,
            warning?: true,
            invoice_numbers: Enum.map(skipped_invoices, & &1.invoice_number)
          }
        ]
      end

    suggestions = []

    # Check bank connection
    has_bank = Finances.list_requisitions!(%{status: :accepted}, scope: scope) != []

    # Only an admin can connect a bank.
    suggestions =
      if has_bank or bank_alerts != [] or scope.actor.member.role != :admin do
        suggestions
      else
        [%{type: :connect_bank} | suggestions]
      end

    # Check KSeF connection
    has_ksef = Ksef.connected?(scope)

    suggestions =
      if has_ksef do
        suggestions
      else
        [%{type: :connect_ksef} | suggestions]
      end

    suggestions = ksef_warnings ++ bank_alerts ++ suggestions
    %{entries: suggestions, total_count: length(suggestions)}
  end

  defp bank_connection_warning?(account) do
    account.broken? == true or
      match?(
        %Requisition{status: status} when status in [:expired, :rejected],
        account.requisition
      )
  end

  defp awaiting_bank_sync?(%{requisition: %Requisition{status: :accepted, inserted_at: connected_at}} = account) do
    is_nil(account.latest_successful_sync_at) or
      DateTime.before?(account.latest_successful_sync_at, connected_at)
  end

  defp awaiting_bank_sync?(_account), do: false

  # Entries of `count` months from the `first` one; a list without month headings is whole.
  defp window_entries(entries, {first, count}) do
    headings =
      entries
      |> Enum.with_index()
      |> Enum.filter(&match?({{:month, _month}, _index}, &1))
      |> Enum.map(fn {_heading, index} -> index end)

    case headings do
      [] ->
        entries

      headings ->
        from = Enum.at(headings, first, length(entries))
        to = Enum.at(headings, first + count, length(entries))
        Enum.slice(entries, from, to - from)
    end
  end

  defp newer_months?({first, _count}), do: first > 0

  defp older_months?(entries, {first, count}), do: Enum.count(entries, &match?({:month, _month}, &1)) > first + count

  # The inbox lists of invoices and transactions show every month, each under its heading row.
  defp all_months_list?(assigns) do
    flag_enabled?(:inbox, assigns) and assigns.params.view_mode == :list and
      assigns.params.filter in [:invoices, :transactions]
  end

  # The picker on the list of every month names the month on screen; sized for the
  # longest name, it keeps its width, and the filters their place, while scrolling.
  defp widest_month_label(month) do
    1..12
    |> Enum.map(&EntriesTable.month_label(%{month | month: &1, day: 1}))
    |> Enum.max_by(&String.length/1)
  end

  # Entries are grouped within their month, so a group never spans two separators.
  defp with_month_separators(entries) do
    entries
    |> Enum.group_by(&(&1 |> entry_date() |> Date.beginning_of_month()))
    |> Enum.sort_by(fn {month, _entries} -> month end, {:desc, Date})
    |> Enum.flat_map(fn {month, month_entries} ->
      [{:month, month} | group_cost_transactions_by_party(month_entries)]
    end)
  end

  defp group_cost_transactions_by_party(entries) do
    {transactions, other_entries} = Enum.split_with(entries, &match?(%Transaction{}, &1))

    # Group by the raw counterparty within each direction. The display fallback is
    # intentionally not used here, as unrelated transactions must not share a group.
    {groups, ungrouped} =
      transactions
      |> Enum.group_by(&{if(&1.direction == :expense, do: :cost, else: :income), &1.counterparty_name})
      |> Enum.split_with(fn {_kind_and_party, txns} ->
        length(txns) >= 2 and Enum.all?(txns, & &1.groupable?) and
          same_currency_transactions?(txns)
      end)

    group_structs =
      Enum.map(groups, fn {{kind, party}, txns} -> build_transaction_group(kind, party, txns) end)

    order_entries_for_display(group_structs ++ Enum.flat_map(ungrouped, &elem(&1, 1)) ++ other_entries)
  end

  defp same_currency_transactions?([first | rest]) do
    currency = Money.to_currency_code(first.amount)
    Enum.all?(rest, &(Money.to_currency_code(&1.amount) == currency))
  end

  defp build_transaction_group(kind, party, transactions) do
    total =
      Enum.reduce(transactions, Decimal.new(0), fn transaction, acc ->
        signed_amount = transaction.signed_amount
        Decimal.add(acc, Money.to_decimal(signed_amount))
      end)

    currency =
      transactions
      |> List.first()
      |> then(&(&1.amount |> Money.to_currency_code() |> Atom.to_string()))

    # Use LATEST date for sorting
    latest_transaction = Enum.max_by(transactions, & &1.booking_date, Date)

    id = transaction_group_id(kind, party)

    %TransactionGroup{
      id: id,
      party: party,
      total: total,
      count: length(transactions),
      currency: currency,
      date: latest_transaction.booking_date,
      transactions: transactions
    }
  end

  defp transaction_group_id(kind, party) do
    "group-#{kind}-#{:erlang.phash2({kind, party})}"
  end

  # Unordered: the list orders its entries once they are grouped by party.
  defp fetch_entries(from, to, filter, subfilter, scope) do
    filter
    |> entry_reads(subfilter)
    |> Enum.flat_map(fn
      {:cost_invoices, args} ->
        list_cost_invoices(from, to, args, scope)

      {:sales_invoices, args} ->
        list_sales_invoices(from, to, Map.put(args, :kind, :vat), scope)

      {:transactions, args} ->
        list_transactions(from, to, args, scope)

      {:transactions, args, direction} ->
        from |> list_transactions(to, args, scope) |> Enum.filter(&(&1.direction == direction))
    end)
  end

  @issued %{date_field: :issue_date}
  @issued_matched %{date_field: :issue_date, reconciliation: :matched}
  @issued_pending %{date_field: :issue_date, reconciliation: :pending}
  @due_pending %{date_field: :due_date, reconciliation: :pending}

  # The side filters of the inbox lists: sales or purchase invoices, incoming or outgoing transactions.
  defp entry_reads(:invoices, :sprzedazowe), do: [{:sales_invoices, @issued}]
  defp entry_reads(:invoices, :zakupowe), do: [{:cost_invoices, @issued}]
  defp entry_reads(:transactions, :wplywy), do: [{:transactions, %{}, :income}]
  defp entry_reads(:transactions, :wydatki), do: [{:transactions, %{}, :expense}]

  defp entry_reads(:all, _subfilter), do: [{:cost_invoices, @issued}, {:sales_invoices, @issued}, {:transactions, %{}}]

  defp entry_reads(:unmatched, _subfilter) do
    [
      {:cost_invoices, @due_pending},
      {:sales_invoices, Map.put(@due_pending, :submission, :confirmed)},
      {:transactions, %{reconciliation: :pending}}
    ]
  end

  defp entry_reads(:invoices, :oplacone), do: [{:cost_invoices, @issued_matched}, {:sales_invoices, @issued_matched}]

  defp entry_reads(:invoices, :nieoplacone),
    do: [{:cost_invoices, @issued_pending}, {:sales_invoices, Map.put(@issued_pending, :submission, :confirmed)}]

  defp entry_reads(:invoices, _subfilter), do: [{:cost_invoices, @issued}, {:sales_invoices, @issued}]

  defp entry_reads(:transactions, :dopasowane), do: [{:transactions, %{reconciliation: :matched}}]

  defp entry_reads(:transactions, :bez_dokumentu), do: [{:transactions, %{reconciliation: :pending}}]

  defp entry_reads(:transactions, _subfilter), do: [{:transactions, %{}}]

  defp list_cost_invoices(from, to, extra_args, scope) do
    args = Map.merge(%{date_from: from, date_to: to, merge_corrections: true}, extra_args)

    Invoicing.list_cost_invoices!(args,
      load: @cost_invoice_loads,
      scope: scope,
      query: dated_only(from)
    )
  end

  defp list_sales_invoices(from, to, extra_args, scope) do
    args = Map.merge(%{date_from: from, date_to: to}, extra_args)

    Invoicing.list_sales_invoices!(args,
      load: @sales_invoice_loads,
      scope: scope,
      query: dated_only(from)
    )
  end

  # The list of every month asks for no date range, which would include invoices without an
  # issue date; they belong to no month, as a month's range never held them either.
  defp dated_only(nil), do: [filter: [issue_date: [is_nil: false]]]
  defp dated_only(_from), do: []

  defp list_transactions(from, to, extra_args, scope) do
    args = Map.merge(%{date_from: from, date_to: to}, extra_args)

    Finances.list_transactions!(args,
      load: [
        :amount,
        :cost_invoices,
        :sales_invoices,
        :bank_account,
        :direction,
        :signed_amount,
        :counterparty_name,
        :counterparty_display_name,
        :groupable?,
        :reconciliation_status
      ],
      # Grouped transactions keep this order, so same-day ones need the tie broken.
      query: [sort: [booking_date: :desc, id: :asc]],
      scope: scope
    )
  end

  defp get_active_months(scope) do
    sales_dates = Invoicing.list_sales_invoices!(query: [select: [:issue_date]], scope: scope)
    cost_dates = Invoicing.list_cost_invoices!(query: [select: [:issue_date]], scope: scope)

    transaction_dates =
      Finances.list_transactions!(query: [select: [:booking_date]], scope: scope)

    (Enum.map(sales_dates ++ cost_dates, & &1.issue_date) ++
       Enum.map(transaction_dates, & &1.booking_date))
    |> Enum.map(&Date.beginning_of_month/1)
    |> Enum.uniq()
    |> Enum.sort(Date)
  end

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

  defp entry_matched?(%struct{} = inv) when struct in [SalesInvoice, CostInvoice],
    do: inv.transactions != [] or inv.skip_invoicing

  defp entry_matched?(%Transaction{} = tx), do: tx.reconciliation_status in [:matched, :skipped]

  # Groups only contain unmatched transactions by design
  defp entry_matched?(%TransactionGroup{}), do: false

  # Draft = no invoice number assigned (only SalesInvoice)
  defp entry_draft?(%SalesInvoice{invoice_number: num}), do: is_nil(num)
  defp entry_draft?(_), do: false

  defp entry_invoice_number(%SalesInvoice{invoice_number: num}), do: num
  defp entry_invoice_number(_), do: nil

  defp can_write_invoicing?(user) do
    Ash.can_do_all?([{SalesInvoice, :draft}, {CostInvoice, :create}], user)
  end

  defp can_view_invoicing?(user) do
    Ash.can?({SalesInvoice, :list}, user)
  end
end
