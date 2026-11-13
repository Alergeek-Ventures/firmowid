defmodule FirmowidWeb.Invoicing.Components.EntriesTable do
  @moduledoc false
  use FirmowidWeb, :html

  import FirmowidUI.Components.Link
  import FirmowidWeb.DesignSystem.Components.InvoicingBadges
  import FirmowidWeb.Invoicing.Components.StatusButton
  import Phoenix.Component, except: [link: 1]

  alias Firmowid.Finances.Transaction
  alias Firmowid.Invoicing.CostInvoice
  alias Firmowid.Invoicing.SalesInvoice
  alias Firmowid.Invoicing.TransactionGroup
  alias Firmowid.Ksef.SubmissionInfo
  alias FirmowidWeb.Analysis.Components.ProjectCell
  alias FirmowidWeb.Invoicing.Utilities.BankBadges
  alias FirmowidWeb.Invoicing.Utilities.Navigation

  attr :invoicing_entries, :list, required: true
  attr :mode, :atom, required: true

  attr :load_newer, :string,
    default: nil,
    doc: "event loading newer rows when the table's start comes into view"

  attr :load_more, :string,
    default: nil,
    doc: "event loading more rows when the table's end comes into view"

  attr :return_to, :string, default: nil
  attr :can_write_invoicing, :boolean, default: true

  attr :projects, :map,
    default: nil,
    doc: "project column settings (`projects`, `colors`, `scope`, `can_write`), or nil to hide it"

  attr :projects_loaded_at, :integer,
    default: nil,
    doc: "changes with every reload of the list, so the rows on screen read their projects again"

  @default_columns ["party", "issue_or_value_date", "due_or_booking_date", "status", "amount"]

  @invoice_columns ["party", "issue_date", "due_date", "status", "amount"]
  @transaction_columns ["party", "value_date", "booking_date", "status", "amount"]

  @column_labels [
    party: pgettext_noop("Counterparty", "entries table column"),
    issue_date: pgettext_noop("Issued", "entries table column"),
    value_date: pgettext_noop("Performed", "entries table column"),
    issue_or_value_date: pgettext_noop("Issued / Performed", "entries table column"),
    due_date: pgettext_noop("Payment due date", "entries table column"),
    booking_date: pgettext_noop("Booked", "entries table column"),
    due_or_booking_date: pgettext_noop("Payment due date / Booked", "entries table column"),
    status: pgettext_noop("Status", "entries table column"),
    amount: pgettext_noop("Amount", "entries table column")
  ]

  # Using map pattern match to avoid Dialyzer false positive about
  # LiveView internal assign fields (:__given__, etc.)
  defp get_sales_invoice_buyer_name(%{__struct__: SalesInvoice} = invoice) do
    invoice.buyer_display_name_label || ""
  end

  def table(%{invoicing_entries: []} = assigns) do
    ~H"""
    <div class="flex min-h-[300px] flex-col items-center justify-center gap-4">
      <.icon name="hero-cloud-arrow-up" class="size-16 text-moss-700" />
      <p class="text-center text-black">
        {gettext("No transactions or documents for the selected date")}
      </p>
      <p class="text-center text-grey-700">
        {gettext("Drag files here to upload them")}
      </p>
    </div>
    """
  end

  def table(assigns) do
    columns =
      case assigns.mode do
        :invoices -> @invoice_columns
        :transactions -> @transaction_columns
        _ -> @default_columns
      end

    # Rows are assigned to analysis projects before the dates, where the table is wide enough.
    columns =
      if assigns[:projects],
        do: List.insert_at(columns, 1, "project"),
        else: columns

    assigns =
      assigns
      |> assign_new(:return_to, fn -> nil end)
      |> assign_new(:can_write_invoicing, fn -> true end)
      |> assign_new(:projects, fn -> nil end)
      |> assign_new(:projects_loaded_at, fn -> nil end)
      |> assign_new(:load_newer, fn -> nil end)
      |> assign_new(:load_more, fn -> nil end)
      |> assign(
        :columns,
        columns
      )
      # A list of every month separates the months with a line naming each.
      |> assign(:by_month?, Enum.any?(assigns.invoicing_entries, &match?({:month, _}, &1)))

    ~H"""
    <%!-- The hook keeps rows in place itself when months load above, so the browser must not as well.
         A flex column stretches the table across the page, as its parent did before this wrapper. --%>
    <div
      id="invoicing-entries-list"
      phx-hook=".MonthScroll"
      class={["flex flex-col", @by_month? && "[overflow-anchor:none]"]}
    >
      <%!-- Coming into view (with a margin), each indicator loads the months on its side. --%>
      <.load_indicator :if={@load_newer} event={@load_newer} />
      <table
        id="invoicing-entries"
        class={
          [
            # rows span the page at every width; from xl the fixed layout lets the party take
            # only what the fixed columns leave, so a long description cannot push the amount
            # off the screen; narrower tables size their columns to the content, which keeps
            # the party readable
            "w-full border-separate border-spacing-y-3 max-md:mt-0 max-md:block xl:table-fixed",
            # the headings start where they stick, so nothing moves as scrolling begins
            if(@by_month?, do: "-mt-6", else: "-mt-8")
          ]
        }
      >
        <col
          :for={column <- @columns}
          class={[
            case column do
              "project" -> "w-48 in-data-[layout=sidebar]:max-[90rem]:hidden max-xl:hidden"
              "issue_date" -> "w-36"
              "booking_date" -> "w-44"
              "issue_or_value_date" -> "w-36"
              "due_date" -> "w-44"
              "value_date" -> "w-36"
              "due_or_booking_date" -> "w-44"
              "status" -> "w-40"
              "amount" -> "w-44"
              _ -> ""
            end
          ]}
        />
        <thead class={
          [
            "sticky z-1 bg-grey-100 max-md:hidden",
            # the list of every month (`Index`) has a taller bar, 1.25rem more than the plain page header
            if(@by_month?,
              do: "top-[calc(var(--spacing-navbar)+var(--page-header-height)+1.25rem)]",
              else: "top-[calc(var(--spacing-navbar)+var(--page-header-height))]"
            )
          ]
        }>
          <tr>
            <th
              :for={column <- @columns}
              id={"header-#{column}"}
              phx-hook="ScrollStyle"
              data-classes="border-b-4 border-solid border-grey-700/40"
              data-scroll-offset="90"
              class={[
                "h-[60px] py-2 text-left align-bottom text-xs font-normal text-grey-700 uppercase",
                column == "party" && "pl-5",
                column == "project" &&
                  "pr-6 text-right in-data-[layout=sidebar]:max-[90rem]:hidden max-xl:hidden"
              ]}
            >
              <.column_label column={column} />
            </th>
          </tr>
        </thead>
        <tbody class="max-md:flex max-md:flex-col max-md:gap-3">
          <%= for entry <- @invoicing_entries do %>
            <%= case entry do %>
              <% {:month, month} -> %>
                <.month_row month={month} />
              <% %TransactionGroup{} = group -> %>
                <.group_row
                  group={group}
                  projects={@projects}
                  projects_loaded_at={@projects_loaded_at}
                  columns={@columns}
                  return_to={@return_to}
                  can_write_invoicing={@can_write_invoicing}
                />
              <% invoicing_entry -> %>
                <.table_row
                  projects={@projects}
                  projects_loaded_at={@projects_loaded_at}
                  columns={@columns}
                  invoicing_entry={invoicing_entry}
                  return_to={@return_to}
                  can_write_invoicing={@can_write_invoicing}
                />
            <% end %>
          <% end %>
        </tbody>
      </table>
      <.load_indicator :if={@load_more} event={@load_more} />
      <script :type={Phoenix.LiveView.ColocatedHook} name=".MonthScroll">
        export default {
          // Rows pass out of sight here: under the column headings, which stick from md, or on
          // phones, where the headings are hidden, under the navbar, which the separators' scroll
          // margin matches.
          topEdge(separator) {
            const head = this.el.querySelector("thead");
            return head.offsetHeight
              ? parseFloat(getComputedStyle(head).top) + head.offsetHeight
              : parseFloat(getComputedStyle(separator).scrollMarginTop) || 0;
          },
          mounted() {
            this.sync = () => {
              const rows = Array.from(this.el.querySelectorAll("tr[data-month]"));
              // The month on top is the last whose separator passed out of sight. The first month
              // has none to pass from md, the column headings above it in its stead.
              const edge = rows[0] && this.topEdge(rows[0]) + 0.5;
              const current = rows.filter((row, index) =>
                index === 0 || row.getBoundingClientRect().top <= edge
              ).pop();
              const picker = document.getElementById("month");
              if (current && picker) picker.value = current.dataset.label;
              // The server downloads the month on screen, so it hears of each new one.
              if (current && current.dataset.month !== this.month) {
                this.month = current.dataset.month;
                this.pushEvent("visible-month", {month: this.month});
              }
            };
            this.onScroll = () => {
              if (this.frame) return;
              this.frame = requestAnimationFrame(() => {
                this.frame = null;
                this.sync();
              });
            };
            window.addEventListener("scroll", this.onScroll, {passive: true});
            // Months load ahead of the reader, before an indicator scrolls into view.
            this.observer = new IntersectionObserver(entries => {
              const entry = entries.find(entry => entry.isIntersecting);
              if (entry) this.load(entry.target.dataset.load);
            }, {rootMargin: "1200px 0px"});
            this.observe();
            this.sync();
            this.handleEvent("scroll-to-month", ({month}) => this.scrollToMonth(month));
          },
          scrollToMonth(month) {
            // Months run newest first; a month without entries scrolls to the next older one.
            const row = Array.from(this.el.querySelectorAll("tr[data-month]"))
              .find(row => row.dataset.month <= month);
            // No month to scroll to: the picker names the chosen one, so name the one on screen.
            // A jump still waiting for newer months is dropped, or it would override this choice.
            if (!row) {
              this.pending = null;
              return this.sync();
            }
            // A separator comes to rest just under the column headings, which makes its month
            // the one on top. The hidden one of the first month has no box, so its first row
            // comes to rest a row gap (12px) below them.
            const top = row.offsetHeight
              ? row.getBoundingClientRect().top + window.scrollY - this.topEdge(row)
              : row.nextElementSibling.getBoundingClientRect().top + window.scrollY - this.topEdge(row) - 12;
            // Newer months loading above show the first month's separator below the headings,
            // where the page cannot scroll it yet, so the scroll is repeated once they are in.
            this.pending = !row.offsetHeight && this.el.firstElementChild.dataset.load ? month : null;
            // Gliding across many months takes seconds, so a far month is shown at once.
            const far = Math.abs(top - window.scrollY) > 3 * window.innerHeight;
            window.scrollTo({top, behavior: far ? "instant" : "smooth"});
          },
          observe() {
            this.observer.disconnect();
            this.el.querySelectorAll("[data-load]").forEach(indicator => this.observer.observe(indicator));
          },
          load(event) {
            if (this.loading) return;
            this.loading = true;
            // Months added above move the rows down the page; scrolling by as much keeps the
            // first row on screen in place, whatever the reader scrolled meanwhile.
            const anchor = Array.from(this.el.querySelectorAll("tbody tr"))
              .find(row => row.getBoundingClientRect().bottom > 0);
            const pageTop = row => row.getBoundingClientRect().top + window.scrollY;
            const before = anchor && pageTop(anchor);
            this.pushEvent(event, {}, () => {
              if (anchor?.isConnected) window.scrollBy({top: pageTop(anchor) - before, behavior: "instant"});
              // `updated` ran before the scroll above, so the month on top is found again.
              this.sync();
              this.loading = false;
              if (this.pending) this.scrollToMonth(this.pending);
              // Observing again reports an indicator still in range, which loads the next months.
              this.observe();
            });
          },
          // A patch may add months or replace the indicators.
          updated() {
            this.sync();
            this.observe();
          },
          // A reply lost with the connection would leave loading stuck.
          reconnected() {
            this.loading = false;
            this.observe();
          },
          destroyed() {
            window.removeEventListener("scroll", this.onScroll);
            cancelAnimationFrame(this.frame);
            this.observer.disconnect();
          }
        }
      </script>
    </div>
    """
  end

  attr :event, :string, required: true

  defp load_indicator(assigns) do
    ~H"""
    <div data-load={@event} role="status" class="flex justify-center py-6 text-grey-700">
      <Lucideicons.loader_circle class="size-6 motion-safe:animate-spin" aria-hidden="true" />
      <span class="sr-only">{gettext("Loading more months")}</span>
    </div>
    """
  end

  defp column_label(assigns) do
    assigns =
      assign(
        assigns,
        :label,
        if(assigns.column == "project",
          do: gettext("Project"),
          else:
            Gettext.pgettext(
              Firmowid.Gettext,
              "entries table column",
              Keyword.fetch!(@column_labels, String.to_existing_atom(assigns.column))
            )
        )
      )

    is_special_column =
      case assigns.column do
        "issue_or_value_date" -> true
        "due_or_booking_date" -> true
        _ -> false
      end

    if is_special_column do
      ~H"""
      <span
        id={"header-#{@column}-label"}
        class="inline-block"
        phx-hook="Tippy"
        data-tippy-content={
          case @column do
            "issue_or_value_date" ->
              gettext("For invoices this is the issue date, for transactions the execution date")

            "due_or_booking_date" ->
              gettext(
                "For invoices this is the payment due date, for transactions the payment booking date"
              )
          end
        }
      >
        {@label}
      </span>
      """
    else
      ~H"""
      {@label}
      """
    end
  end

  # Separates the months of a list that spans all of them with a line naming the month.
  # From md the first month needs none: the column headings start it, and the month
  # picker above names the month on top. On phones the picker scrolls away, so there
  # every month is named.
  #
  # The line takes one cell and spans the row from it: a cell spanning every column would
  # make a column of its own while the project column is hidden, which takes room from
  # the others.
  defp month_row(assigns) do
    assigns = assign(assigns, :label, month_label(assigns.month))

    ~H"""
    <tr
      id={"month-#{Date.to_iso8601(@month)}"}
      data-month={Date.to_iso8601(@month)}
      data-label={@label}
      class="relative max-md:block max-md:scroll-mt-navbar md:first:hidden"
    >
      <th scope="colgroup" class="h-[30px] p-0 font-medium max-md:block">
        <div class="absolute inset-0 flex items-center gap-4 pt-3 pb-1">
          <span class="h-px min-w-px flex-1 bg-grey-200"></span>
          <span class="text-caps-sm leading-[normal] whitespace-nowrap text-grey-500 uppercase">{@label}</span>
          <span class="h-px min-w-px flex-1 bg-grey-200"></span>
        </div>
      </th>
    </tr>
    """
  end

  @doc "The month as a capitalized name and year, e.g. \"Listopad 2026\", as the month headings name it."
  @spec month_label(Date.t()) :: String.t()
  def month_label(month), do: month |> Firmowid.Cldr.Date.to_string!(format: "LLLL y") |> String.capitalize()

  defp table_row(assigns) do
    assigns =
      assigns
      |> assign(
        :amount,
        case assigns.invoicing_entry do
          %Transaction{} -> Money.to_decimal(assigns.invoicing_entry.amount)
          %CostInvoice{} -> Money.to_decimal(assigns.invoicing_entry.effective_amount)
          %SalesInvoice{} -> Money.to_decimal(assigns.invoicing_entry.effective_amount)
        end
      )
      |> assign(
        :is_draft,
        case assigns.invoicing_entry do
          %SalesInvoice{} = invoice -> is_nil(invoice.invoice_number)
          _ -> false
        end
      )
      |> assign(:is_income, income_for_entry(assigns.invoicing_entry))

    ~H"""
    <tr id={"#{@invoicing_entry.id}-row"} class={mobile_row_styles(@is_draft)}>
      <td
        :for={column <- @columns}
        class={
          [
            "py-2 transition-all duration-500",
            mobile_cell_styles(column),
            column == "project" && "pr-6 in-data-[layout=sidebar]:max-[90rem]:hidden max-xl:hidden",
            column == "party" && "rounded-l-md px-5 text-ellipsis max-xl:max-w-72",
            String.ends_with?(column, "date") && "font-light",
            column == "amount" && "rounded-r-md",
            # A draft is not issued yet: from md it lies on the page, outlined with a dashed
            # line, its amount on a faint grey. On phones it stays a white tile like the others.
            # Issued entries are white, with the amount filled.
            if(@is_draft,
              do: [
                "border-y border-dashed border-grey-300 max-md:bg-white",
                column == "party" && "border-l",
                column == "amount" && "border-r bg-grey-200/25 text-teal-600"
              ],
              else: [
                "bg-white",
                column == "amount" && @is_income && "bg-teal-200! text-teal-800",
                column == "amount" && !@is_income && "bg-rust-200! text-rust-700"
              ]
            )
          ]
        }
      >
        <div class={
          [
            # this column has no defined width, so we limit the worst offenders "manually"
            column == "party" && party_width_styles(@projects),
            # required to display the "dot freshness" indicator that is rendered outside of the cell
            column != "amount" && "w-full truncate"
          ]
        }>
          <.render_cell
            projects={@projects}
            projects_loaded_at={@projects_loaded_at}
            column={column}
            invoicing_entry={@invoicing_entry}
            return_to={@return_to}
            can_write_invoicing={@can_write_invoicing}
          />
        </div>
      </td>
    </tr>
    """
  end

  # The project column takes part of the room the party may use on wide screens.
  defp party_width_styles(nil), do: "max-w-[50vw] max-md:max-w-none"
  defp party_width_styles(_projects), do: "max-w-[50vw] max-md:max-w-none xl:max-w-[30vw]"

  # Below md each row becomes a tile: the party on the left, its description under it,
  # and on the right the amount beside the party and the first date beside the
  # description. Statuses and skip actions are left to the detail pages.
  defp mobile_row_styles(draft?) do
    [
      "max-md:grid max-md:grid-cols-[minmax(0,1fr)_auto] max-md:overflow-hidden max-md:rounded-lg max-md:bg-white",
      draft? && "max-md:border max-md:border-dashed max-md:border-grey-300"
    ]
  end

  defp mobile_cell_styles("party"),
    do:
      "max-md:col-start-1 max-md:row-span-2 max-md:row-start-1 max-md:max-w-none max-md:rounded-none max-md:border-0 max-md:pt-4 max-md:pb-4"

  defp mobile_cell_styles(column) when column in ["issue_date", "value_date", "issue_or_value_date"],
    do:
      "max-md:col-start-2 max-md:row-start-2 max-md:border-0 max-md:pt-0 max-md:pr-5 max-md:pb-4 max-md:pl-3 max-md:text-right max-md:text-sm max-md:text-grey-700"

  defp mobile_cell_styles("amount"),
    do:
      "max-md:col-start-2 max-md:row-start-1 max-md:-mb-2 max-md:rounded-none max-md:border-0 max-md:bg-transparent! max-md:pt-2 max-md:pb-0 max-md:pl-3 max-md:font-semibold"

  defp mobile_cell_styles(_status_or_second_date), do: "max-md:hidden"

  defp render_cell(%{column: "project"} = assigns) do
    ~H"""
    <.live_component
      module={ProjectCell}
      id={"project-#{@invoicing_entry.__struct__ |> Module.split() |> List.last()}-#{@invoicing_entry.id}"}
      entry={@invoicing_entry}
      projects={@projects.projects}
      colors={@projects.colors}
      scope={@projects.scope}
      can_write={@projects.can_write}
      loaded_at={@projects_loaded_at}
    />
    """
  end

  # amount is differently rendered (has a background color that fills the cell)
  defp render_cell(%{column: "amount", invoicing_entry: %Transaction{} = transaction} = assigns) do
    amount = transaction.signed_amount

    assigns = assign(assigns, :amount, amount)

    ~H"""
    <div class="relative py-2 pr-5 text-right">
      {@amount}
    </div>
    """
  end

  defp render_cell(%{column: "amount", invoicing_entry: %SalesInvoice{} = invoice} = assigns) do
    amount = invoice.effective_amount

    assigns = assign(assigns, :amount, amount)

    ~H"""
    <div class="relative py-2 pr-5 text-right">
      {@amount}
    </div>
    """
  end

  defp render_cell(%{column: "amount", invoicing_entry: %CostInvoice{} = invoice} = assigns) do
    is_fresh =
      invoice.transactions == [] &&
        DateTime.after?(
          invoice.inserted_at,
          DateTime.shift(DateTime.utc_now(), minute: -2)
        )

    amount = invoice.effective_amount

    assigns =
      assigns
      |> assign(:is_fresh, is_fresh)
      |> assign(:amount, amount)

    ~H"""
    <div class="relative py-2 pr-5 text-right">
      {@amount}

      <%= if @is_fresh do %>
        <span
          id={"amount-fresh-#{@invoicing_entry.id}"}
          phx-hook="Tippy"
          data-tippy-delay="10"
          data-tippy-content={gettext("This document has just been added!")}
          class="absolute top-[-10px] right-[-4px] flex size-3"
        >
          <span class="absolute inline-flex size-full animate-ping rounded-full bg-teal-800 opacity-75"></span>
          <span class="relative inline-flex size-3 rounded-full bg-teal-800"></span>
        </span>
      <% end %>
    </div>
    """
  end

  # status cell is rendered differently (has a button)
  defp render_cell(%{column: "status", status: "skipped"} = assigns) do
    ~H"""
    <div
      id={"#{@invoicing_entry.id}-container"}
      phx-hook="Tippy"
      data-tippy-delay="1000"
      data-tippy-content={
        case @invoicing_entry do
          %Transaction{} ->
            gettext("The transaction has been skipped. Invoices will not be assigned to it")

          _ ->
            gettext("The document has been skipped. Transactions will not be assigned to it")
        end
      }
      class="flex w-32 flex-row gap-2 overflow-hidden"
    >
      <%!-- The label and the undo button share the status width evenly. --%>
      <div
        id={"#{@invoicing_entry.id}-label"}
        class="flex h-6 flex-1 flex-row items-center justify-center rounded-md bg-moss-200 p-2 text-moss-700 transition-all duration-500"
      >
        <.icon
          name={
            case @invoicing_entry do
              %Transaction{} ->
                "hero-credit-card-mini"

              _ ->
                "hero-document-text-solid"
            end
          }
          class="size-4"
        />
      </div>
      <.status_button
        :if={@can_write_invoicing}
        id={"#{@invoicing_entry.id}-button"}
        phx-click="toggle-skip-invoicing"
        phx-value-id={@invoicing_entry.id}
        phx-value-type={
          case @invoicing_entry do
            %Transaction{} -> "transaction"
            %CostInvoice{} -> "cost_invoice"
            %SalesInvoice{} -> "sales_invoice"
          end
        }
        icon="hero-arrow-uturn-left-micro"
        class="flex-1 transition-all duration-500"
      />
    </div>
    """
  end

  defp render_cell(%{column: "status", status: "ksef_sending"} = assigns) do
    ~H"""
    <div
      id={"status-#{@invoicing_entry.id}"}
      phx-hook="Tippy"
      data-tippy-delay="1000"
      data-tippy-content={gettext("The invoice is being sent to KSeF. Please wait for confirmation.")}
      class="flex w-32 flex-row gap-2 overflow-hidden"
    >
      <div class="flex h-6 w-full items-center justify-center px-2 text-caps-sm font-medium whitespace-nowrap text-grey-700 uppercase">
        {gettext("Sending...")}
      </div>
    </div>
    """
  end

  defp render_cell(%{column: "status", status: "ksef_failed"} = assigns) do
    ~H"""
    <div
      id={"status-#{@invoicing_entry.id}"}
      phx-hook="Tippy"
      data-tippy-delay="1000"
      data-tippy-content={
        gettext(
          "Sending the invoice to KSeF failed. Our team has been notified and is working on a fix."
        )
      }
      class="flex w-32 flex-row gap-2 overflow-hidden"
    >
      <div class="flex h-6 w-full items-center justify-center rounded-md bg-brick-700 px-2 text-caps-sm font-medium whitespace-nowrap text-brick-100 uppercase">
        {gettext("Sending error")}
      </div>
    </div>
    """
  end

  defp render_cell(%{column: "status", status: "matched"} = assigns) do
    match_tooltip =
      case assigns.invoicing_entry do
        %Transaction{cost_invoices: [], sales_invoices: []} ->
          nil

        _ ->
          gettext(
            "The transaction and the document were matched - this means the invoice is paid and ready to be booked."
          )
      end

    assigns = assign(assigns, :match_tooltip, match_tooltip)

    ~H"""
    <div
      id={"status-#{@invoicing_entry.id}"}
      phx-hook={if @match_tooltip, do: "Tippy"}
      data-tippy-delay={if @match_tooltip, do: "1000"}
      data-tippy-content={@match_tooltip}
      class="flex w-32 flex-row gap-2 overflow-hidden"
    >
      <div class="flex h-6 w-full items-center justify-between rounded-md bg-moss-200 px-2 text-caps-sm font-medium text-moss-700 uppercase transition-all duration-500">
        {gettext("Complete")}
        <.icon name="hero-check-micro" class="size-4" />
      </div>
    </div>
    """
  end

  defp render_cell(%{column: "status", status: "draft"} = assigns) do
    ~H"""
    <div
      id={"status-#{@invoicing_entry.id}"}
      phx-hook="Tippy"
      data-tippy-delay="1000"
      data-tippy-content={gettext("This is a draft invoice — the document has not been issued yet.")}
      class="flex w-32 flex-row gap-2 overflow-hidden"
    >
      <%!-- A neutral pill: a draft is on no side of the books yet. --%>
      <div class="flex h-6 w-full items-center justify-center rounded-md bg-grey-200 px-2 text-caps-sm font-medium whitespace-nowrap text-grey-700 uppercase">
        {gettext("Draft version")}
      </div>
    </div>
    """
  end

  defp render_cell(%{column: "status", status: "unmatched"} = assigns) do
    ~H"""
    <div
      id={"#{@invoicing_entry.id}-container"}
      phx-hook="Tippy"
      data-tippy-delay="1000"
      data-tippy-content={
        case @invoicing_entry do
          %Transaction{} ->
            gettext(
              "We synchronized transactions from your account - this means a document should be assigned to the expense. "
            )

          _ ->
            gettext(
              "You added a file containing a cost invoice. To confirm it has been paid, we will assign the matching transaction from your account - or click 'skip' to indicate it was paid another way (e.g. in cash)"
            )
        end
      }
      class="flex w-32 flex-row gap-2 overflow-hidden"
    >
      <div
        id={"#{@invoicing_entry.id}-label"}
        class={[
          "flex h-6 flex-row items-center justify-center rounded-md p-2 transition-all duration-500",
          @can_write_invoicing && "w-10",
          !@can_write_invoicing && "w-full",
          case @invoicing_entry do
            %Transaction{} -> "bg-brick-200 text-brick-700"
            _ -> "bg-grey-200 text-grey-700"
          end
        ]}
      >
        <.icon
          name={
            case @invoicing_entry do
              %Transaction{} ->
                "hero-credit-card-mini"

              _ ->
                "hero-document-text-solid"
            end
          }
          class="size-4"
        />
      </div>
      <.status_button
        :if={@can_write_invoicing}
        id={"#{@invoicing_entry.id}-button"}
        phx-click="toggle-skip-invoicing"
        phx-value-id={@invoicing_entry.id}
        phx-value-type={
          case @invoicing_entry do
            %Transaction{} -> "transaction"
            %CostInvoice{} -> "cost_invoice"
            %SalesInvoice{} -> "sales_invoice"
          end
        }
        label={gettext("Skip")}
        class="text-caps-sm! font-semibold transition-all duration-500"
      />
    </div>
    """

    # rest of the cells are rendered more or less in the same way
  end

  defp render_cell(%{column: "status"} = assigns) do
    assigns = assign(assigns, :status, status_for_entry(assigns.invoicing_entry))

    ~H"""
    <.render_cell
      column={@column}
      status={@status}
      invoicing_entry={@invoicing_entry}
      can_write_invoicing={@can_write_invoicing}
    />
    """
  end

  defp render_cell(%{column: "SKIPPED"} = assigns) do
    ~H"""
    <span class="text-grey-700 opacity-50">
      &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;-
    </span>
    """
  end

  defp render_cell(%{invoicing_entry: %Transaction{}, column: "issue_date"} = assigns),
    do: assigns |> assign(:column, "booking_date") |> render_cell()

  defp render_cell(%{invoicing_entry: %Transaction{}, column: "due_date"} = assigns),
    do: assigns |> assign(:column, "SKIPPED") |> render_cell()

  defp render_cell(%{invoicing_entry: %Transaction{}, column: "issue_or_value_date"} = assigns),
    do: assigns |> assign(:column, "booking_date") |> render_cell()

  defp render_cell(%{invoicing_entry: %Transaction{}, column: "due_or_booking_date"} = assigns),
    do: assigns |> assign(:column, "booking_date") |> render_cell()

  defp render_cell(%{invoicing_entry: %CostInvoice{}, column: "due_or_booking_date"} = assigns),
    do: assigns |> assign(:column, "due_date") |> render_cell()

  defp render_cell(%{invoicing_entry: %SalesInvoice{}, column: "due_or_booking_date"} = assigns),
    do: assigns |> assign(:column, "due_date") |> render_cell()

  defp render_cell(%{invoicing_entry: %CostInvoice{} = invoice, column: "due_date"} = assigns) do
    assigns = assign(assigns, :value, invoice.effective_due_date)

    ~H"""
    <.date_value :if={@value} date={@value} />
    """
  end

  defp render_cell(%{invoicing_entry: %SalesInvoice{is_paid_on_issue: true}, column: "due_date"} = assigns) do
    ~H"""
    {gettext("Paid")}
    """
  end

  defp render_cell(%{invoicing_entry: %SalesInvoice{} = invoice, column: "due_date"} = assigns) do
    assigns = assign(assigns, :value, invoice.effective_due_date)

    ~H"""
    <.date_value :if={@value} date={@value} />
    """
  end

  defp render_cell(%{invoicing_entry: %CostInvoice{}, column: "issue_or_value_date"} = assigns),
    do: assigns |> assign(:column, "issue_date") |> render_cell()

  defp render_cell(%{invoicing_entry: %SalesInvoice{}, column: "issue_or_value_date"} = assigns),
    do: assigns |> assign(:column, "issue_date") |> render_cell()

  defp render_cell(%{invoicing_entry: %Transaction{} = transaction, column: "party"} = assigns) do
    party = transaction.counterparty_display_name

    assigns =
      assigns
      |> assign(:party, party)
      |> assign(:bank_badge, Map.get(transaction, :bank_account))
      |> assign(:invoice_source_badge_variant, nil)
      |> assign(:description, transaction.remittance_information_unstructured)
      |> assign(
        :navigate,
        Navigation.transaction_show_path(transaction, Map.get(assigns, :return_to))
      )

    ~H"<.render_cell
  party={@party}
  navigate={@navigate}
  description={@description}
  bank_badge={@bank_badge}
  invoice_source_badge_variant={@invoice_source_badge_variant}
  column={@column}
/>"
  end

  defp render_cell(%{invoicing_entry: %CostInvoice{} = invoice, column: "party"} = assigns) do
    assigns =
      assigns
      |> assign(:party, invoice.effective_seller_display_name || invoice.seller)
      |> assign(:bank_badge, nil)
      |> assign(:invoice_source_badge_variant, invoice_source_badge_variant(invoice))
      |> assign(:description, invoice.description)
      |> assign(
        :navigate,
        Navigation.cost_invoice_show_path(invoice, Map.get(assigns, :return_to))
      )

    ~H"<.render_cell
  party={@party}
  navigate={@navigate}
  description={@description}
  bank_badge={@bank_badge}
  invoice_source_badge_variant={@invoice_source_badge_variant}
  column={@column}
/>"
  end

  defp render_cell(%{invoicing_entry: %SalesInvoice{} = invoice, column: "party"} = assigns) do
    party = get_sales_invoice_buyer_name(invoice)

    assigns =
      assigns
      |> assign(:party, party)
      |> assign(:bank_badge, nil)
      |> assign(:invoice_source_badge_variant, invoice_source_badge_variant(invoice))
      |> assign(
        :description,
        case {
          party,
          Enum.map_join(invoice.sales_invoice_items, ", ", & &1.name)
        } do
          {"", ""} -> gettext("draft sales invoice")
          {_party, ""} -> ""
          {_party, description} -> description
        end
      )
      |> assign(
        :navigate,
        Navigation.sales_invoice_show_path(invoice, Map.get(assigns, :return_to))
      )

    ~H"<.render_cell
  party={@party}
  navigate={@navigate}
  description={@description}
  bank_badge={@bank_badge}
  invoice_source_badge_variant={@invoice_source_badge_variant}
  column={@column}
/>"
  end

  defp render_cell(
         %{navigate: nil, party: _, description: _, bank_badge: _, invoice_source_badge_variant: _, column: "party"} =
           assigns
       ) do
    ~H"""
    <.party_cell_content
      party={@party}
      description={@description}
      bank_badge={@bank_badge}
      invoice_source_badge_variant={@invoice_source_badge_variant}
    />
    """
  end

  defp render_cell(
         %{navigate: _, party: _, description: _, bank_badge: _, invoice_source_badge_variant: _, column: "party"} =
           assigns
       ) do
    ~H"""
    <.link kind="unstyled" navigate={@navigate} class="hover:underline">
      <.party_cell_content
        party={@party}
        description={@description}
        bank_badge={@bank_badge}
        invoice_source_badge_variant={@invoice_source_badge_variant}
      />
    </.link>
    """
  end

  # plain render (fallback)
  defp render_cell(%{invoicing_entry: invoicing_entry, column: column} = assigns) do
    # Use existing atoms to avoid atom exhaustion
    value = get_in(invoicing_entry, [Access.key!(String.to_existing_atom(column))])

    assigns = assign(assigns, :value, value)

    ~H"""
    <%= if match?(%Date{}, @value) do %>
      <.date_value date={@value} />
    <% else %>
      {@value}
    <% end %>
    """
  end

  attr :date, Date, required: true

  # From md to xl the date columns are narrow and the month separators name the month and
  # year, so a date shows only its day and short month, e.g. "9 lis". Wider, and on phones,
  # where the date sits alone under the amount, it is written out whole.
  defp date_value(assigns) do
    ~H"""
    <span class="max-md:hidden xl:hidden">{Firmowid.Cldr.Date.to_string!(@date, format: "d MMM")}</span>
    <span class="md:max-xl:hidden">{@date}</span>
    """
  end

  defp status_for_entry(%Transaction{reconciliation_status: :pending}), do: "unmatched"

  defp status_for_entry(%Transaction{reconciliation_status: status}) when status in [:matched, :skipped],
    do: Atom.to_string(status)

  # Paid when issued: complete once issued, with no skip to undo.
  defp status_for_entry(%SalesInvoice{is_paid_on_issue: true} = invoice), do: sales_invoice_status(invoice, "matched")

  defp status_for_entry(%{skip_invoicing: true}), do: "skipped"

  defp status_for_entry(%CostInvoice{transactions: []}), do: "unmatched"
  defp status_for_entry(%CostInvoice{}), do: "matched"

  defp status_for_entry(%SalesInvoice{} = invoice),
    do: sales_invoice_status(invoice, if(invoice.transactions == [], do: "unmatched", else: "matched"))

  defp status_for_entry(_), do: "unmatched"

  defp sales_invoice_status(invoice, issued_status) do
    submission_info = SubmissionInfo.for_invoice(invoice)

    cond do
      is_nil(invoice.invoice_number) -> "draft"
      SubmissionInfo.submitting?(submission_info) -> "ksef_sending"
      SubmissionInfo.failed?(submission_info) -> "ksef_failed"
      true -> issued_status
    end
  end

  attr :group, TransactionGroup, required: true
  attr :columns, :list, required: true
  attr :return_to, :string, default: nil
  attr :can_write_invoicing, :boolean, default: true

  attr :projects, :map,
    default: nil,
    doc: "project column settings (`projects`, `colors`, `scope`, `can_write`), or nil to hide it"

  attr :projects_loaded_at, :integer,
    default: nil,
    doc: "changes with every reload of the list, so the rows on screen read their projects again"

  defp group_row(assigns) do
    assigns = assign(assigns, :bank_badge, bank_badge_for_group(assigns.group))

    ~H"""
    <tr
      id={"#{@group.id}-row"}
      class={["cursor-pointer duration-200", mobile_row_styles(false)]}
      phx-click={
        JS.toggle_class("rotate-90", to: "#chevron-#{@group.id}")
        |> JS.toggle_class("opacity-50", to: "##{@group.id}-row")
        |> JS.toggle(
          to: "[data-group-transactions='#{@group.id}']",
          in: {"ease-out duration-300", "opacity-0", "opacity-100"},
          out: {"ease-in duration-200", "opacity-100", "opacity-0"}
        )
      }
    >
      <td
        :for={column <- @columns}
        class={[
          "bg-white py-2 transition-all duration-500",
          mobile_cell_styles(column),
          column == "project" && "pr-6 in-data-[layout=sidebar]:max-[90rem]:hidden max-xl:hidden",
          column == "party" && "rounded-l-md px-5 text-ellipsis max-xl:max-w-72",
          String.ends_with?(column, "date") && "font-light",
          column == "amount" && "rounded-r-md",
          column == "amount" && Decimal.gte?(@group.total, 0) && "bg-teal-200! text-teal-800",
          column == "amount" && Decimal.lt?(@group.total, 0) && "bg-rust-200! text-rust-700"
        ]}
      >
        <div class={[
          column == "party" && party_width_styles(@projects),
          column != "amount" && "w-full truncate"
        ]}>
          <%= if column == "party" do %>
            <div class="flex min-w-0 items-center gap-2.5">
              <.bank_badge bank={@bank_badge} size="mini" class="shrink-0" />
              <span class="min-w-0 truncate">
                <span>{@group.party}</span>
                <span
                  id={"chevron-#{@group.id}"}
                  class="mx-1 inline-flex size-4 items-center justify-center transition-transform"
                >
                  <.icon name="hero-chevron-right" class="size-3" />
                </span>
                <span class="text-sm text-grey-700 opacity-50">
                  {pluralize_transaction_count(@group.count)}
                </span>
              </span>
            </div>
          <% else %>
            <.render_group_cell
              column={column}
              group={@group}
              columns={@columns}
              can_write_invoicing={@can_write_invoicing}
            />
          <% end %>
        </div>
      </td>
    </tr>
    <!-- Group transaction rows (hidden by default) -->
    <%= for transaction <- @group.transactions do %>
      <tr
        data-group-transactions={@group.id}
        class={["hidden max-md:[[style*='block']]:grid!", mobile_row_styles(false)]}
      >
        <td
          :for={column <- @columns}
          class={[
            "bg-white py-2 transition-all duration-500",
            mobile_cell_styles(column),
            column == "project" && "pr-6 in-data-[layout=sidebar]:max-[90rem]:hidden max-xl:hidden",
            column == "party" && "rounded-l-md px-5 text-ellipsis max-xl:max-w-72",
            String.ends_with?(column, "date") && "font-light",
            column == "amount" && "rounded-r-md",
            column == "amount" && transaction.direction == :income &&
              "bg-teal-200! text-teal-800",
            column == "amount" && transaction.direction != :income &&
              "bg-rust-200! text-rust-700"
          ]}
        >
          <div class={[
            column == "party" && party_width_styles(@projects),
            column != "amount" && "w-full truncate"
          ]}>
            <%= if column == "party" do %>
              <div class="flex items-center gap-2">
                <.icon name="hero-arrow-turn-down-right" class="size-3 text-grey-700 opacity-50" />
                <.render_cell
                  projects={@projects}
                  projects_loaded_at={@projects_loaded_at}
                  column={column}
                  invoicing_entry={transaction}
                  return_to={@return_to}
                  can_write_invoicing={@can_write_invoicing}
                />
              </div>
            <% else %>
              <.render_cell
                projects={@projects}
                projects_loaded_at={@projects_loaded_at}
                column={column}
                invoicing_entry={transaction}
                return_to={@return_to}
                can_write_invoicing={@can_write_invoicing}
              />
            <% end %>
          </div>
        </td>
      </tr>
    <% end %>
    """
  end

  defp render_group_cell(%{column: "amount"} = assigns) do
    ~H"""
    <div class="relative py-2 pr-5 text-right">
      {Money.new(@group.currency, @group.total)}
    </div>
    """
  end

  defp render_group_cell(%{column: column, group: _group} = assigns)
       when column in ["issue_or_value_date", "value_date", "due_or_booking_date", "booking_date"] do
    ~H"""
    <.date_value date={@group.date} />
    """
  end

  defp render_group_cell(%{column: column, group: _group} = assigns)
       when column in ["issue_date", "due_date", "project"] do
    ~H"""
    """
  end

  defp render_group_cell(%{column: "status"} = assigns) do
    # Check if we're in unmatched filter by checking columns
    assigns =
      assigns
      |> assign(:is_unmatched, "status" in assigns.columns)
      |> assign(:all_skipped, Enum.all?(assigns.group.transactions, & &1.skip_invoicing))

    ~H"""
    <%= cond do %>
      <% not @is_unmatched -> %>
      <% @all_skipped -> %>
        <div class="flex w-32 flex-row gap-2 overflow-hidden">
          <div
            id={"#{@group.id}-label"}
            class={[
              "flex h-6 flex-row items-center justify-center rounded-md bg-moss-200 p-2 text-xs text-moss-700 transition-all duration-500",
              @can_write_invoicing && "w-20",
              !@can_write_invoicing && "w-full"
            ]}
          >
            <.icon name="hero-credit-card-mini" class="size-4" />
          </div>
          <.status_button
            :if={@can_write_invoicing}
            id={"#{@group.id}-button"}
            phx-click={
              JS.push("toggle-skip-invoicing-group",
                value: %{transaction_ids: Enum.map(@group.transactions, & &1.id)}
              )
            }
            icon="hero-arrow-uturn-left-micro"
            class="transition-all duration-500"
          />
        </div>
      <% true -> %>
        <div class="flex w-32 flex-row gap-2 overflow-hidden">
          <div class="flex h-6 w-10 flex-row items-center justify-center rounded-md bg-brick-200 p-2 text-xs text-brick-700 transition-all duration-500">
            <.icon name="hero-credit-card-mini" class="size-4" />
          </div>
          <.status_button
            :if={@can_write_invoicing}
            id={"#{@group.id}-button"}
            phx-click={
              JS.push("toggle-skip-invoicing-group",
                value: %{transaction_ids: Enum.map(@group.transactions, & &1.id)}
              )
            }
            label={gettext("Skip")}
            class="transition-all duration-500"
          />
        </div>
    <% end %>
    """
  end

  defp render_group_cell(assigns) do
    ~H"""
    """
  end

  attr :party, :string, default: nil
  attr :description, :string, default: nil
  attr :bank_badge, :any, default: nil
  attr :invoice_source_badge_variant, :string, default: nil

  defp party_cell_content(assigns) do
    ~H"""
    <div class="flex min-w-0 items-center gap-2.5">
      <.bank_badge :if={@bank_badge} institution={@bank_badge} size="mini" class="shrink-0" />
      <.invoice_source_badge
        :if={@invoice_source_badge_variant}
        variant={@invoice_source_badge_variant}
        size="small"
        class="shrink-0"
      />
      <%!-- From xl one line, cut as a whole, which lets the column size to its full text, and
           the ellipsis takes the line's colour: the description's when there is one, as the
           line is cut within it, with the party kept black. Narrower, the description goes
           under the party instead of being cut to a few letters, each line cut on its own. --%>
      <span class={[
        "min-w-0 truncate",
        @description not in [nil, ""] && "text-grey-700/50"
      ]}>
        <span class="text-black max-xl:block max-xl:truncate">{@party}</span>
        <span :if={@description not in [nil, ""]} class="text-sm max-xl:block max-xl:truncate">
          {@description}
        </span>
      </span>
    </div>
    """
  end

  defp pluralize_transaction_count(count) do
    ngettext("%{count} transaction", "%{count} transactions", count)
  end

  defp bank_badge_for_group(%TransactionGroup{transactions: transactions}) do
    case transactions |> Enum.map(&BankBadges.badge_for_transaction/1) |> Enum.uniq() do
      [bank_badge] -> bank_badge
      _ -> "Default"
    end
  end

  defp income_for_entry(%Transaction{} = transaction), do: transaction.direction == :income

  defp income_for_entry(%CostInvoice{effective_amount: %Money{} = amount}), do: Money.positive?(amount)

  defp income_for_entry(%CostInvoice{amount: amount}), do: Money.positive?(amount)

  defp income_for_entry(%SalesInvoice{effective_amount: %Money{} = amount}), do: Money.positive?(amount)

  defp income_for_entry(%SalesInvoice{amount: amount}), do: Money.positive?(amount)

  defp income_for_entry(%{amount: amount}), do: Money.positive?(amount)
end
