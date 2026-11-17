# credo:disable-for-this-file ExDNA.Credo
# This LiveView currently combines orchestration for uploads, PubSub, and invoice grouping;
# removing duplication requires extracting domain-facing services across feature boundaries.
defmodule FirmowidWeb.Invoicing.Views.Index do
  @moduledoc false
  # TODO: move business logic (transaction grouping by party, get_active_months)
  # to domain actions/calculations — LiveView should only handle presentation
  use FirmowidWeb, :live_view

  import FirmowidUI.Components.Link
  import FirmowidWeb.Core.PubSubDebounce
  import FirmowidWeb.DesignSystem.Components.MonthPicker
  import FirmowidWeb.Infrastructure.Flags, only: [flag_enabled?: 2]
  import FirmowidWeb.Infrastructure.Hooks.RequireOrganization, only: [guard_upload_progress: 2]
  import Phoenix.Component, except: [link: 1]

  alias Ash.Notifier.Notification
  alias Firmowid.Analysis
  alias Firmowid.Analysis.TagDefinition
  alias Firmowid.Blobs.Blob
  alias Firmowid.Finances
  alias Firmowid.Finances.ExpectedTransaction
  alias Firmowid.Finances.Requisition
  alias Firmowid.Finances.Transaction
  alias Firmowid.Invoicing
  alias Firmowid.Invoicing.CostInvoice
  alias Firmowid.Invoicing.SalesInvoice
  alias Firmowid.Invoicing.TransactionGroup
  alias Firmowid.Ksef
  alias FirmowidWeb.Analysis.Utilities.CategoryColors
  alias FirmowidWeb.Core.Endpoint
  alias FirmowidWeb.Inbox.Utilities.Navigation, as: InboxNavigation
  alias FirmowidWeb.Infrastructure.UserAuth
  alias FirmowidWeb.Invoicing.Components.CostInvoiceUpload
  alias FirmowidWeb.Invoicing.Components.EntriesTable
  alias FirmowidWeb.Invoicing.Utilities.Navigation
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
    :is_paid_on_issue,
    :transactions,
    corrections: :sales_invoice_items,
    latest_correction: :sales_invoice_items
  ]

  # A busy company has hundreds of rows a month, and rendering them takes seconds, so the
  # list shows a screenful and a margin, and adds as many again as either end comes into view.
  @window_rows 40

  # Files of one upload change state in bursts, each change asking for the whole
  # page again; long enough to gather a burst, short enough to feel immediate.
  @gather_ms 500

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

      if flag_enabled?(:taxes, socket.assigns),
        do: Endpoint.subscribe("expected_transaction:updated:#{organization_id}")

      Endpoint.subscribe("requisition:linked:#{organization_id}")
      Endpoint.subscribe("requisition:rejected:#{organization_id}")
      Endpoint.subscribe("requisition:expired:#{organization_id}")
      Endpoint.subscribe("requisition:error:#{organization_id}")
      # KSeF status (separate system)
      Ksef.subscribe_ksef_status(organization_id)
    end

    socket =
      if can_write_invoicing?(user) do
        allow_upload(
          socket,
          :file,
          [progress: guard_upload_progress(&handle_progress/3, :ash_scope)] ++
            CostInvoiceUpload.upload_options()
        )
      else
        socket
      end

    socket =
      socket
      |> assign(:page_title, "Fakturowanie")
      |> assign(:projects_column, nil)
      |> assign(:projects_loaded_at, nil)

    active_months =
      get_active_months(socket.assigns.ash_scope, flag_enabled?(:taxes, socket.assigns)) ++
        [Date.beginning_of_month(Date.utc_today())]

    socket = assign(socket, :active_months, active_months)

    socket =
      socket
      |> assign(:transactions_debounce_timer, nil)
      |> assign(:refetch_gathering?, false)

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
    <%!-- From md the action labels show as the bar has room for them, which also depends on
         the sidebar: issuing an invoice keeps its label longest, then the invoice from outside
         KSeF, then the download; on phones the actions float and keep their labels. Above the
         bar as much room as between it and the column headings below it, the same before and
         while scrolling: the bar starts at the top of the page, as it sticks there. --%>
    <div class="sticky top-navbar z-10 flex justify-between bg-grey-100 py-4 max-md:static max-md:z-auto max-md:flex-col max-md:gap-3 md:@container md:-mt-4 md:gap-4 md:pt-11 md:pb-3">
      <div class="flex items-center gap-3 max-md:flex-wrap">
        <%!-- The label is the month scrolled to, set in the browser; the server renders the
             first one and leaves the input alone afterwards. --%>
        <.month_picker
          id="month"
          show_on_mobile
          active_months={@active_months}
          selected_date={@params.month}
          value={EntriesTable.month_label(@params.month)}
          widest_value={widest_month_label(@params.month)}
          phx-update="ignore"
          class="max-md:h-12 max-md:flex-1 md:[&>svg]:size-5!"
        />

        <%!-- The picker scrolls to the month, and the filters sit beside it. --%>
        <FirmowidWeb.Invoicing.Components.FilterBar.inbox_filters params={@params} />
      </div>

      <div
        phx-drop-target={can_write_invoicing?(@current_user) && @uploads.file.ref}
        class="flex flex-row gap-2 max-md:contents @min-[66.5rem]:gap-3"
      >
        <%!-- The download reads the month itself, so it shows while the rows load and
             goes only when the list turns out empty. --%>
        <%= if @invoicing_entries != [] do %>
          <.live_component
            id="download-component"
            module={FirmowidWeb.Invoicing.Components.DownloadModal}
            month={@visible_month || @params.month}
            icon_only
          />
        <% end %>
        <%!-- The bar's actions sit closer together than page actions elsewhere. --%>
        <.page_actions
          :if={can_write_invoicing?(@current_user)}
          label={gettext("Add invoice")}
          class="md:gap-2! md:*:gap-2! @min-[66.5rem]:gap-3! @min-[66.5rem]:*:gap-3!"
        >
          <:action>
            <form id="upload-form" phx-change="upload" phx-submit="upload">
              <div class="hidden">
                <.live_file_input upload={@uploads.file} />
              </div>
              <FirmowidUI.Components.Button.button
                as="label"
                for={@uploads.file.ref}
                variant="tertiary"
                accent="rust"
                class="relative md:[&>svg]:size-5!"
                data-fab
              >
                <%= if @currently_uploading_count > 0 or @processing_blobs_count > 0 do %>
                  <CostInvoiceUpload.processing_badge
                    id="upload-count-indicator"
                    uploading={@currently_uploading_count}
                    processing={@processing_blobs_count}
                  />
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
                <Lucideicons.file />
                <span class="block sm:grow sm:text-center md:@max-[62.5rem]:sr-only">
                  {gettext("Invoice from outside KSeF")}
                </span>
              </FirmowidUI.Components.Button.button>
            </form>
          </:action>
          <:action>
            <.link
              navigate={Navigation.sales_invoice_creator_path()}
              kind="button"
              variant="tertiary"
              accent="teal"
              id="sales-invoice-link"
              data-fab
            >
              <Lucideicons.square_pen class="size-6 md:size-5!" />
              <span class="md:@max-[51.5rem]:sr-only">
                {gettext("Issue invoice")}
              </span>
            </.link>
          </:action>
        </.page_actions>
      </div>
    </div>
    <div class="relative mt-2 flex flex-col gap-4">
      <EntriesTable.table
        mode={@params.filter}
        by_month
        invoicing_entries={
          listed_entries(@invoicing_entries, @newest_entries) &&
            window_entries(listed_entries(@invoicing_entries, @newest_entries), @entries_window)
        }
        more_loading={is_nil(@invoicing_entries) and @newest_entries != nil}
        load_newer={newer_entries?(@entries_window) && "load-newer-entries"}
        load_more={
          listed_entries(@invoicing_entries, @newest_entries) &&
            older_entries?(listed_entries(@invoicing_entries, @newest_entries), @entries_window) &&
            "load-older-entries"
        }
        return_to={Navigation.invoicing_index_path(@params)}
        can_write_invoicing={can_write_invoicing?(@current_user)}
        projects={@projects_column}
        projects_loaded_at={@projects_loaded_at}
      />

      <div
        :if={can_write_invoicing?(@current_user)}
        id="file-drop-overlay"
        class="absolute -inset-3 z-20 hidden rounded-lg border-2 border-teal-200 bg-[#EDF5F599] opacity-60 transition-opacity"
        phx-hook="FileUploadDragNDrop"
        phx-drop-target={can_write_invoicing?(@current_user) && @uploads.file.ref}
      >
        <div class="sticky top-0 flex size-full max-h-dvh items-center justify-center">
          <div class="flex w-fit flex-col items-center gap-6 rounded-sm bg-teal-200 px-10 pt-6 pb-8 text-teal-700">
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

    # Without a list asked for, the page leads to the inbox; only the lists of invoices
    # and transactions stay here.
    if is_nil(parsed.filter) do
      {:noreply, push_navigate(socket, to: InboxNavigation.inbox_path(:company), replace: true)}
    else
      socket =
        socket
        |> assign(:params, parsed)
        |> assign(:entries_window, {0, @window_rows})
        # Kept across patches, like the hook's own record of the month it last reported.
        |> assign_new(:visible_month, fn -> nil end)
        # Other params show other entries, so the old ones give way to placeholders.
        |> assign(:invoicing_entries, nil)
        |> assign(:newest_entries, nil)
        |> read_newest_entries()
        |> refetch_invoicing_entries()

      {:noreply, socket}
    end
  end

  # The picker is live before the entries arrive; until then there is nothing to scroll to.
  @impl true
  def handle_event("change-month", _params, %{assigns: %{invoicing_entries: nil}} = socket), do: {:noreply, socket}

  # The list already holds the chosen month, so the picker only scrolls to it, first
  # moving the window to its heading when the heading is not shown.
  def handle_event("change-month", %{"month" => month}, socket) do
    target = Date.from_iso8601!(month)
    # Months run newest first; a month without entries opens the next older one,
    # and a month older than every entry has nothing to show, so the hook only puts
    # the picker back on the month on screen.
    heading_index =
      Enum.find_index(socket.assigns.invoicing_entries, fn
        {:month, heading} -> Date.compare(heading, target) != :gt
        _entry -> false
      end)

    case heading_index do
      nil ->
        {:noreply, push_event(socket, "scroll-to-month", %{month: month})}

      index ->
        {first, count} = socket.assigns.entries_window

        window =
          if index in first..(first + count - 1)//1,
            do: {first, count},
            else: {index, @window_rows}

        {:noreply,
         socket
         |> assign(:entries_window, window)
         |> push_event("scroll-to-month", %{month: month})}
    end
  end

  # The list downloads the month on screen, which the picker names.
  def handle_event("visible-month", %{"month" => month}, socket) do
    {:noreply, assign(socket, :visible_month, Date.from_iso8601!(month))}
  end

  def handle_event("load-older-entries", _params, socket) do
    {:noreply, update(socket, :entries_window, fn {first, count} -> {first, count + @window_rows} end)}
  end

  def handle_event("load-newer-entries", _params, socket) do
    {:noreply,
     update(socket, :entries_window, fn {first, count} ->
       newer = min(first, @window_rows)
       {first - newer, count + newer}
     end)}
  end

  @impl true
  def handle_event("upload", _, socket) do
    socket = CostInvoiceUpload.assign_counts(socket)

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

  @impl true
  def handle_info(%Broadcast{payload: %Notification{resource: Transaction}}, socket) do
    {:noreply, debounce_refetch(socket, :invoicing_entries, 10_000)}
  end

  def handle_info(%Broadcast{payload: %Notification{resource: ExpectedTransaction}}, socket) do
    active_months =
      get_active_months(socket.assigns.ash_scope, flag_enabled?(:taxes, socket.assigns)) ++
        [Date.beginning_of_month(Date.utc_today())]

    {:noreply, socket |> assign(:active_months, active_months) |> refetch_invoicing_entries()}
  end

  # A project assigned in one row also shows on the transaction paying that invoice, and a
  # new project needs its colour. The rows read their projects themselves, so the list is
  # not read again.
  @impl true
  def handle_info(:projects_changed, socket) do
    %{params: %{month: month}, ash_scope: scope} = socket.assigns

    {:noreply,
     socket
     |> assign(:projects_column, projects_column(socket.assigns, month, scope))
     |> assign(:projects_loaded_at, System.monotonic_time())}
  end

  def handle_info({:debounced_refetch, :invoicing_entries}, socket) do
    {:noreply, refetch_invoicing_entries(socket)}
  end

  def handle_info(:gathered_refetch, socket) do
    {:noreply, socket |> assign(:refetch_gathering?, false) |> refetch_invoicing_entries()}
  end

  # Blob created — file is being processed, refresh list
  @impl true
  def handle_info(
        %Broadcast{
          payload: %Notification{resource: Blob, data: %{processing_target: :cost_invoice}, action: %{type: :create}}
        },
        socket
      ) do
    {:noreply, gather_refetch(socket)}
  end

  # Blob updated — processing state transitions
  @impl true
  def handle_info(
        %Broadcast{
          payload:
            %Notification{resource: Blob, action: %{type: :update}, data: %{processing_target: :cost_invoice}} =
              notification
        },
        socket
      ) do
    CostInvoiceUpload.toast_failure(notification)

    {:noreply, gather_refetch(socket)}
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
    CostInvoiceUpload.toast_failure(notification)

    {:noreply, socket}
  end

  # Blob destroyed — processing failed, or normal cleanup (delete invoice, etc.)
  @impl true
  def handle_info(
        %Broadcast{
          payload:
            %Notification{resource: Blob, data: %{processing_target: :cost_invoice}, action: %{type: :destroy}} =
              notification
        },
        socket
      ) do
    CostInvoiceUpload.toast_failure(notification)

    {:noreply, gather_refetch(socket)}
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
    socket = gather_refetch(socket)
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
    socket = gather_refetch(socket)
    cost_invoice = ci

    LiveToast.send_toast(
      :success,
      "#{cost_invoice.issue_date} / #{cost_invoice.seller_display_name}",
      title: gettext("Invoice matched with a transaction"),
      action: fn assigns ->
        ~H"""
        <.link
          kind="unstyled"
          class="text-sm font-bold underline"
          navigate={Navigation.invoices_list_path()}
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
    {:noreply, gather_refetch(socket)}
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

    {:noreply, socket}
  end

  defp handle_progress(:file, _, socket) do
    socket =
      case uploaded_entries(socket, :file) do
        {[_ | _] = entries, []} ->
          CostInvoiceUpload.consume(socket, entries)
          CostInvoiceUpload.assign_counts(socket)

        _ ->
          socket
      end

    {:noreply, socket}
  end

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

  # Until every entry arrives, the newest months show the change; the read in flight may have
  # missed it, so it starts again.
  defp update_entry(%{assigns: %{invoicing_entries: nil, newest_entries: [_ | _] = newest}} = socket, id, changes) do
    socket
    |> assign(:newest_entries, update_entries(newest, id, changes))
    |> refetch_invoicing_entries()
  end

  # A click that arrives just after the params changed finds no rows; the new read shows the change.
  defp update_entry(%{assigns: %{invoicing_entries: nil}} = socket, _id, _changes), do: socket

  defp update_entry(socket, id, changes) do
    assign(
      socket,
      :invoicing_entries,
      update_entries(socket.assigns.invoicing_entries, id, changes)
    )
  end

  # A row may also sit inside a group of one party's transactions.
  defp update_entries(entries, id, changes) do
    update = fn
      %{id: ^id} = entry -> Map.merge(entry, changes)
      other -> other
    end

    Enum.map(entries, fn
      %TransactionGroup{} = group ->
        %{group | transactions: Enum.map(group.transactions, update)}

      entry ->
        update.(entry)
    end)
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

  # Reloads once, shortly after the first change of a burst.
  defp gather_refetch(%{assigns: %{refetch_gathering?: true}} = socket), do: socket

  defp gather_refetch(socket) do
    Process.send_after(self(), :gathered_refetch, @gather_ms)
    assign(socket, :refetch_gathering?, true)
  end

  # The entries are read in a task, so the page shows at once and its rows follow. A task
  # starts only once connected, so the static render leaves them to the connected one
  # instead of reading them twice. A later read replaces the result of an earlier one.
  # The lists show every month, newest first.
  defp refetch_invoicing_entries(socket) do
    %{params: %{filter: filter, subfilter: subfilter}} = socket.assigns
    scope = socket.assigns.ash_scope
    expected? = flag_enabled?(:taxes, socket.assigns)

    socket
    |> CostInvoiceUpload.assign_counts()
    |> start_async(:invoicing_entries, fn ->
      nil |> fetch_entries(nil, filter, subfilter, scope, expected?) |> with_month_separators()
    end)
  end

  @impl true
  def handle_async(:invoicing_entries, {:ok, entries}, socket) do
    %{params: %{month: month}, ash_scope: scope} = socket.assigns

    {:noreply,
     socket
     |> assign(:invoicing_entries, entries)
     |> assign(:newest_entries, nil)
     |> assign_projects_column(month, scope)}
  end

  def handle_async(:invoicing_entries, {:exit, reason}, _socket), do: exit(reason)

  # The newest months show until every entry arrives, unless the params changed meanwhile or
  # every entry is already there. Without newest entries, the placeholders stay rather than
  # telling that the list is empty.
  def handle_async(:newest_entries, {:ok, {params, entries}}, socket) do
    %{params: current_params, invoicing_entries: all_entries, ash_scope: scope} = socket.assigns

    if params == current_params and is_nil(all_entries) and entries != [] do
      {:noreply,
       socket
       |> assign(:newest_entries, entries)
       |> assign_projects_column(params.month, scope)}
    else
      {:noreply, socket}
    end
  end

  def handle_async(:newest_entries, {:exit, reason}, _socket), do: exit(reason)

  # Projects change without the entries changing (another session, the assistant, tracked
  # time), so every reload makes the rows on screen read theirs again.
  defp assign_projects_column(socket, month, scope) do
    socket
    |> assign(:projects_column, projects_column(socket.assigns, month, scope))
    |> assign(:projects_loaded_at, System.monotonic_time())
  end

  # The list reads all of a company's entries, which takes a while for a busy one, so the
  # current and previous months are read alongside to show first. A company whose entries
  # all fall within them has nothing to show sooner.
  defp read_newest_entries(socket) do
    %{params: params, active_months: active_months, ash_scope: scope} = socket.assigns
    from = Date.utc_today() |> Date.beginning_of_month() |> Date.shift(month: -1)
    expected? = flag_enabled?(:taxes, socket.assigns)

    if Date.before?(Enum.min(active_months, Date), from) do
      start_async(socket, :newest_entries, fn ->
        entries =
          from
          |> fetch_entries(nil, params.filter, params.subfilter, scope, expected?)
          |> with_month_separators()

        {params, entries}
      end)
    else
      socket
    end
  end

  # `count` entries from the `first` one. Starting within a month, they come under its
  # heading, which names the month on top; a list without headings has none to add.
  defp window_entries(entries, {first, count}) do
    case Enum.slice(entries, first, count) do
      [{:month, _month} | _rest] = window ->
        window

      window ->
        heading =
          entries
          |> Enum.take(first)
          |> Enum.reverse()
          |> Enum.find(&match?({:month, _month}, &1))

        if heading, do: [heading | window], else: window
    end
  end

  defp newer_entries?({first, _count}), do: first > 0

  # Every entry once read; until then the newest months, when they came first.
  defp listed_entries(nil, newest_entries), do: newest_entries
  defp listed_entries(entries, _newest_entries), do: entries

  defp older_entries?(entries, {first, count}), do: length(entries) > first + count

  # The picker names the month on screen; sized for the longest name, it keeps its width,
  # and the filters their place, while scrolling.
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

    id =
      transaction_group_id(kind, party, Date.beginning_of_month(latest_transaction.booking_date))

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

  # A party's transactions are grouped within each month, and the list shows the same
  # party's group in many months, each needing its own id.
  defp transaction_group_id(kind, party, month) do
    "group-#{kind}-#{:erlang.phash2({kind, party, month})}"
  end

  # Unordered: the list orders its entries once they are grouped by party. Expected
  # transactions are read only when `expected?` (the `:taxes` flag) is on.
  defp fetch_entries(from, to, filter, subfilter, scope, expected?) do
    filter
    |> entry_reads(subfilter)
    |> Enum.filter(&(expected? or &1 != :expected_transactions))
    |> Enum.flat_map(fn
      {:cost_invoices, args} ->
        list_cost_invoices(from, to, args, scope)

      {:sales_invoices, args} ->
        list_sales_invoices(from, to, args, scope)

      {:transactions, args} ->
        list_transactions(from, to, args, scope)

      {:transactions, args, direction} ->
        from |> list_transactions(to, args, scope) |> Enum.filter(&(&1.direction == direction))

      :expected_transactions ->
        list_expected_transactions(from, to, scope)
    end)
  end

  @issued %{date_field: :issue_date}

  # The side filters of the lists: sales or purchase invoices, incoming or outgoing transactions.
  defp entry_reads(:invoices, :sprzedazowe), do: [{:sales_invoices, @issued}]
  defp entry_reads(:invoices, :zakupowe), do: [{:cost_invoices, @issued}]
  defp entry_reads(:transactions, :wplywy), do: [{:transactions, %{}, :income}]
  defp entry_reads(:transactions, :wydatki), do: [{:transactions, %{}, :expense}]

  defp entry_reads(:invoices, _subfilter), do: [{:cost_invoices, @issued}, {:sales_invoices, @issued}]

  defp entry_reads(:transactions, _subfilter), do: [{:transactions, %{}}, :expected_transactions]

  defp list_cost_invoices(from, to, extra_args, scope) do
    args = Map.merge(%{date_from: from, date_to: to, merge_corrections: true}, extra_args)

    Invoicing.list_cost_invoices!(args,
      load: @cost_invoice_loads,
      scope: scope,
      query: dated_only(from)
    )
  end

  defp list_sales_invoices(from, to, extra_args, scope) do
    args = Map.merge(%{date_from: from, date_to: to, merge_corrections: true}, extra_args)

    Invoicing.list_sales_invoices!(args,
      load: @sales_invoice_loads,
      scope: scope,
      query: dated_only(from)
    )
  end

  # The whole list asks for no date range, which would include invoices without an issue
  # date; they belong to no month, as a month's range never held them either.
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

  defp list_expected_transactions(from, to, scope) do
    Finances.list_expected_transactions!(%{date_from: from, date_to: to, fulfilled: false},
      scope: scope
    )
  end

  defp get_active_months(scope, expected?) do
    sales_dates = Invoicing.list_sales_invoices!(query: [select: [:issue_date]], scope: scope)
    cost_dates = Invoicing.list_cost_invoices!(query: [select: [:issue_date]], scope: scope)

    transaction_dates =
      Finances.list_transactions!(query: [select: [:booking_date]], scope: scope)

    expected_dates =
      if expected?,
        do:
          Finances.list_expected_transactions!(%{fulfilled: false},
            query: [select: [:date]],
            scope: scope
          ),
        else: []

    (Enum.map(sales_dates ++ cost_dates, & &1.issue_date) ++
       Enum.map(transaction_dates, & &1.booking_date) ++ Enum.map(expected_dates, & &1.date))
    |> Enum.map(&Date.beginning_of_month/1)
    |> Enum.uniq()
    |> Enum.sort(Date)
  end

  defp order_entries_for_display(entries) do
    Enum.sort(entries, fn a, b ->
      cond do
        # Draft invoices and expected transactions first.
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
  defp entry_date(%ExpectedTransaction{date: date}), do: date
  defp entry_date(%TransactionGroup{date: date}), do: date

  defp entry_matched?(%struct{} = inv) when struct in [SalesInvoice, CostInvoice],
    do: inv.transactions != [] or inv.skip_invoicing

  defp entry_matched?(%Transaction{} = tx), do: tx.reconciliation_status in [:matched, :skipped]

  # Groups only contain unmatched transactions by design
  defp entry_matched?(%TransactionGroup{}), do: false

  # Only unfulfilled expectations are listed.
  defp entry_matched?(%ExpectedTransaction{}), do: false

  # Expectations remain drafts until their linked transaction replaces them in the list.
  defp entry_draft?(%SalesInvoice{invoice_number: num}), do: is_nil(num)
  defp entry_draft?(%ExpectedTransaction{}), do: true
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
