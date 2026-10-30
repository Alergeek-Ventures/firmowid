defmodule FirmowidWeb.Delegations.Components.SettlementPage do
  @moduledoc "Page layout and local browser behavior for delegation settlement."

  use FirmowidWeb, :html

  import FirmowidUI.Components.Button
  import FirmowidUI.Components.Link
  import FirmowidWeb.Delegations.Components.Delegation
  import FirmowidWeb.Delegations.Components.Settlement.Expense
  import FirmowidWeb.DesignSystem.Components.CoreComponents
  import Phoenix.Component, except: [link: 1]

  alias Firmowid.Delegations.PerDiem
  alias FirmowidWeb.Delegations.Utilities.DelegationPresentation
  alias FirmowidWeb.Delegations.Utilities.Navigation
  alias FirmowidWeb.Delegations.Utilities.SettlementPresentation
  alias Phoenix.LiveView.Rendered

  @doc "Renders the complete delegation settlement page."
  @spec settlement_page(map()) :: Rendered.t()
  def settlement_page(assigns) do
    ~H"""
    <main
      id="delegation-settlement"
      phx-hook=".DelegationDateChange"
      class="mx-auto w-full px-4 py-10 sm:px-6"
    >
      <.back navigate={~p"/ustawienia/profil"} />
      <.form
        for={@complete_form}
        id="delegation-complete-form"
        phx-hook=".SettlementDraft"
        data-draft-key={"delegation:#{@ash_scope.actor.id}:#{@ash_scope.tenant}:#{@delegation.id}"}
        data-editable={to_string(@editable?)}
        data-save-status={@save_status}
        phx-change={if @editable?, do: "validate"}
        phx-submit={if @editable?, do: "submit"}
        class="group relative mt-10 grid w-full gap-10 pb-12 font-[340] lg:grid-cols-[minmax(0,1fr)_22.5rem]"
      >
        <.nested_hidden_inputs :if={@editable?} form={@complete_form} />
        <input
          :if={@editable?}
          type="hidden"
          name="draft_revision"
          id="settlement-draft-revision"
          value="0"
        />
        <section aria-labelledby="delegation-settlement-title" class="min-w-0">
          <small class="text-sm text-grey-500">{gettext("Purpose:")}
          <span class="text-grey-700">{@delegation.purpose}</span></small>
          <dl class="mt-2 flex gap-4 text-grey-500 lg:hidden">
            <small>
              <dt class="inline">{gettext("Dates:")}</dt>
              <dd class="inline text-grey-700 tabular-nums">
                <.date_range start_date={@delegation.start_date} end_date={@delegation.end_date} />
              </dd>
            </small>
          </dl>
          <.saved_notice :if={@editable?} status={@save_status} />
          <h1 id="delegation-settlement-title" class="mt-1 text-2xl font-medium">
            {gettext("Business trip settlement")}
          </h1>
          <p :if={@editable?} class="mt-3 max-w-2xl text-balance text-grey-700">
            {gettext(
              "Attach tickets and receipts. Fill in the required details. We will fill in amounts and invoice numbers automatically."
            )}
          </p>
          <div
            :if={@editable? && @delegation.settlement_return_reason}
            id="settlement-return-reason"
            class="mt-4 max-w-2xl rounded-lg bg-rust-100 px-4 py-3 text-sm text-rust-700"
          >
            <p class="font-medium">Pracodawca zwrócił rozliczenie do poprawy</p>
            <p class="mt-1 whitespace-pre-line">{@delegation.settlement_return_reason}</p>
          </div>
          <.settlement_status :if={!@editable?} delegation={@delegation} />

          <.expense_section
            title={gettext("Journeys")}
            expenses={SettlementPresentation.expenses_for(@delegation.expenses, :transport)}
            upload={Map.get(assigns[:uploads] || %{}, :transport)}
            kind="transport"
            editable?={@editable?}
            sort_active?={@sort_active?}
            description_visible?={@description_visible?}
            expense_forms={@expense_forms}
            trip_forms={@trip_forms}
            related_upload={Map.get(assigns[:uploads] || %{}, :related_document)}
            expense_currencies={@expense_currencies}
            foreign_currency_modes={@foreign_currency_modes}
            nbp_settlements={@nbp_settlements}
            statement_upload={Map.get(assigns[:uploads] || %{}, :statement_document)}
            statement_expense_id={@statement_expense_id}
          >
            <:icon><Lucideicons.plane class="size-5" /></:icon>
          </.expense_section>
          <.expense_section
            title={gettext("Accommodation")}
            expenses={SettlementPresentation.expenses_for(@delegation.expenses, :accommodation)}
            upload={Map.get(assigns[:uploads] || %{}, :accommodation)}
            kind="accommodation"
            editable?={@editable?}
            sort_active?={false}
            description_visible?={@description_visible?}
            expense_forms={@expense_forms}
            trip_forms={@trip_forms}
            related_upload={Map.get(assigns[:uploads] || %{}, :related_document)}
            expense_currencies={@expense_currencies}
            foreign_currency_modes={@foreign_currency_modes}
            nbp_settlements={@nbp_settlements}
            statement_upload={Map.get(assigns[:uploads] || %{}, :statement_document)}
            statement_expense_id={@statement_expense_id}
          >
            <:icon><Lucideicons.bed_double class="size-5" /></:icon>
          </.expense_section>
          <.expense_section
            title={gettext("Other expenses")}
            expenses={SettlementPresentation.expenses_for(@delegation.expenses, :other)}
            upload={Map.get(assigns[:uploads] || %{}, :other)}
            kind="other"
            editable?={@editable?}
            sort_active?={false}
            description_visible?={@description_visible?}
            expense_forms={@expense_forms}
            trip_forms={@trip_forms}
            related_upload={Map.get(assigns[:uploads] || %{}, :related_document)}
            expense_currencies={@expense_currencies}
            foreign_currency_modes={@foreign_currency_modes}
            nbp_settlements={@nbp_settlements}
            statement_upload={Map.get(assigns[:uploads] || %{}, :statement_document)}
            statement_expense_id={@statement_expense_id}
          >
            <:icon><Lucideicons.wallet class="size-5" /></:icon>
          </.expense_section>
          <.per_diem_fields
            form={@complete_form}
            delegation={@delegation}
            editable?={@editable?}
            per_diem={@per_diem}
          />
          <.date_change_notice
            :if={@date_change}
            delegation={@delegation}
            date_change={@date_change}
            form={@complete_form}
            editable?={@editable?}
          />
        </section>
        <aside class="min-w-0 lg:pt-1">
          <dl class="hidden justify-end gap-4 text-grey-500 lg:flex">
            <small>
              <dt class="inline">{gettext("Dates:")}</dt>
              <dd class="inline text-grey-700 tabular-nums">
                <.date_range start_date={@delegation.start_date} end_date={@delegation.end_date} />
              </dd>
            </small>
            <small>
              <dt class="inline">{gettext("Advance:")}</dt>
              <dd class="inline text-grey-700">
                {Money.to_string!(@delegation.advance_amount)}
              </dd>
            </small>
          </dl>
          <div :if={@editable?} class="relative mt-6 lg:mt-47">
            <.summary
              delegation={@delegation}
              total={@total}
              balance={@balance}
              balance_label={@balance_label}
            />
            <.error :if={@submission_failed? and is_nil(@date_change)}>
              {gettext("Could not submit the record. Fill in the required fields.")}
            </.error>
            <.button
              type="submit"
              variant="primary"
              accent="teal"
              size="big"
              class="mt-6 w-full"
              disabled={@uploading?}
            >{gettext("Go to signature")}</.button>
          </div>
          <.summary
            :if={!@editable?}
            delegation={@delegation}
            total={@total}
            balance={@balance}
            balance_label={@balance_label}
            class="mt-6 lg:mt-47"
          />
        </aside>
        <div :if={@editable?} id="related-document-upload-form">
          <.live_file_input
            upload={@uploads.related_document}
            class="pointer-events-none fixed -top-full -left-full size-px opacity-0"
            phx-change="upload-related-document"
          />
        </div>
        <div :if={@editable?} id="statement-document-upload-form">
          <.live_file_input
            upload={@uploads.statement_document}
            class="pointer-events-none fixed -top-full -left-full size-px opacity-0"
            phx-change="upload-statement-document"
          />
        </div>
      </.form>
    </main>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".SettlementDraft">
      export default {
        mounted() {
          this.key = this.el.dataset.draftKey;
          this.revision = 0;
          this.capture = (event) => {
            if (this.el.dataset.editable !== "true" || !event.target.name || event.target.type === "file") return;
            const fields = [...this.el.querySelectorAll("input:not([type=hidden]):not([type=file]), select, textarea")]
              .filter((field) => field.id && field.name)
              .map((field) => [field.id, field.type === "checkbox" ? field.checked : field.value]);
            const signature = JSON.stringify(fields);
            if (signature === this.lastFields) return;
            this.lastFields = signature;
            this.revision += 1;
            this.el.querySelector("#settlement-draft-revision").value = String(this.revision);
            sessionStorage.setItem(this.key, JSON.stringify({ revision: this.revision, fields }));
            this.el.dataset.dirty = "true";
          };
          this.el.addEventListener("input", this.capture, true);
          this.el.addEventListener("change", this.capture, true);
          this.handleEvent("settlement-saved", ({ revision }) => {
            if (String(this.revision) !== revision) return;
            sessionStorage.removeItem(this.key);
            delete this.el.dataset.dirty;
          });
          if (this.el.dataset.editable === "true") {
            const draft = JSON.parse(sessionStorage.getItem(this.key) || "null");
            if (draft) {
              this.revision = draft.revision;
              let changed;
              for (const [id, value] of draft.fields) {
                const field = document.getElementById(id);
                if (!field || !this.el.contains(field)) continue;
                if (field.type === "checkbox") field.checked = value; else field.value = value;
                changed = field;
              }
              changed?.dispatchEvent(new Event("input", { bubbles: true }));
            }
          } else {
            sessionStorage.removeItem(this.key);
          }
        },
        updated() {
          const revision = this.el.querySelector("#settlement-draft-revision");
          if (revision) revision.value = String(this.revision);
          if (sessionStorage.getItem(this.key)) this.el.dataset.dirty = "true";
          if (this.el.dataset.editable !== "true") {
            sessionStorage.removeItem(this.key);
            delete this.el.dataset.dirty;
          }
        },
        disconnected() { this.el.dataset.offline = "true"; },
        reconnected() { delete this.el.dataset.offline; },
        destroyed() {
          this.el.removeEventListener("input", this.capture, true);
          this.el.removeEventListener("change", this.capture, true);
        },
      };
    </script>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".DelegationDateChange">
      export default {
        mounted() {
          this.handleEvent("scroll-to-date-change", () => {
            document.getElementById("delegation-date-change")?.scrollIntoView({
              behavior: window.matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth",
              block: "center",
            });
          });

          this.handleEvent("preserve-statement-upload-scroll", () => {
            this.statementUploadScrollY = window.scrollY;
          });
        },
        updated() {
          if (this.statementUploadScrollY !== undefined) {
            window.scrollTo({ top: this.statementUploadScrollY });
            this.statementUploadScrollY = undefined;
          }
        },
      };
    </script>
    """
  end

  attr :form, :map, required: true

  defp nested_hidden_inputs(assigns) do
    children =
      assigns.form.source.forms
      |> Map.values()
      |> Enum.flat_map(&List.wrap/1)
      |> Enum.map(&to_form/1)

    assigns = assign(assigns, :children, children)

    ~H"""
    <%= for {name, values} <- @form.hidden, value <- List.wrap(values) do %>
      <input type="hidden" name={"#{@form.name}[#{name}]"} value={value} />
    <% end %>
    <.nested_hidden_inputs :for={child <- @children} form={child} />
    """
  end

  attr :status, :atom, required: true

  defp saved_notice(assigns) do
    ~H"""
    <div
      id="delegation-save-status"
      role="status"
      aria-live="polite"
      class="sticky inset-bs-16.5 z-10 mbs-3 grid min-h-[3lh] items-start bg-grey-100 py-2 text-sm text-grey-700"
    >
      <span class="hidden items-center gap-2 group-[.phx-change-loading]:inline-flex group-[.phx-submit-loading]:inline-flex">
        <Lucideicons.refresh_ccw class="size-4 shrink-0 motion-safe:animate-spin" />
        {gettext("Saving changes…")}
      </span>
      <span class="hidden group-data-[offline=true]:inline">
        {gettext("No connection. Changes remain in this tab until saving is confirmed.")}
      </span>
      <span
        :if={@status in [:idle, :saved]}
        class="hidden group-data-[dirty=true]:inline group-data-[offline=true]:hidden group-[.phx-change-loading]:hidden group-[.phx-submit-loading]:hidden"
      >
        {gettext("Waiting for save confirmation…")}
      </span>
      <span class={[
        "group-data-[offline=true]:hidden group-[.phx-change-loading]:hidden group-[.phx-submit-loading]:hidden",
        @status in [:idle, :saved] && "group-data-[dirty=true]:hidden"
      ]}>
        <%= case @status do %>
          <% :saved -> %>
            <span class="inline-flex items-center gap-2"><Lucideicons.check class="size-4" />{gettext(
              "Changes saved"
            )}</span>
          <% :idle -> %>
            {gettext("Changes are saved automatically.")}
          <% :invalid -> %>
            <span class="text-brick-700">{gettext(
              "Not saved. Check the highlighted fields. Your draft remains in this tab."
            )}</span>
          <% :error -> %>
            <span class="text-brick-700">{gettext(
              "Saving failed. Your draft remains in this tab. Edit a field to try again."
            )}</span>
        <% end %>
      </span>
    </div>
    """
  end

  attr :form, :map, required: true
  attr :delegation, :map, required: true
  attr :editable?, :boolean, required: true
  attr :per_diem, :map, default: nil

  defp per_diem_fields(assigns) do
    ~H"""
    <section
      id="delegation-per-diem"
      aria-labelledby="per-diem-title"
      class="mbs-8 space-y-5 border-b border-grey-200 pbe-8"
    >
      <h2 id="per-diem-title" class="text-h5 font-medium">{gettext("Per diem")}</h2>
      <p class="max-w-prose text-sm text-grey-700">
        {gettext("Check the trip times suggested from your tickets. Enter local times in Poland.")}
      </p>
      <fieldset disabled={!@editable?} class="space-y-5">
        <legend class="sr-only">{gettext("Trip times")}</legend>
        <div class="grid grid-cols-[repeat(auto-fit,minmax(min(100%,15rem),1fr))] gap-4">
          <.input
            field={@form[:trip_started_at]}
            type="datetime-local"
            label={gettext("Departure")}
            input_class="w-full min-w-0"
          />
          <.input
            field={@form[:trip_ended_at]}
            type="datetime-local"
            label={gettext("Return")}
            input_class="w-full min-w-0"
          />
        </div>
        <div :if={@delegation.destination_country != "PL"} class="space-y-3">
          <p class="text-sm text-grey-700">
            {gettext(
              "For flights, use take-off from Poland and landing back in Poland. Otherwise, use the border crossing times."
            )}
          </p>
          <div class="grid grid-cols-[repeat(auto-fit,minmax(min(100%,15rem),1fr))] gap-4">
            <.input
              field={@form[:abroad_started_at]}
              type="datetime-local"
              label={gettext("Start of time abroad")}
              input_class="w-full min-w-0"
            />
            <.input
              field={@form[:abroad_ended_at]}
              type="datetime-local"
              label={gettext("End of time abroad")}
              input_class="w-full min-w-0"
            />
          </div>
        </div>
        <div class="space-y-3">
          <p class="text-sm text-grey-700">
            {gettext("Meals provided free of charge, including hotel breakfast")}
          </p>
          <div class="grid grid-cols-[repeat(auto-fit,minmax(min(100%,9rem),1fr))] gap-4">
            <.input
              field={@form[:provided_breakfasts]}
              type="number"
              min="0"
              step="1"
              label={gettext("Breakfasts")}
              input_class="w-full"
            />
            <.input
              field={@form[:provided_lunches]}
              type="number"
              min="0"
              step="1"
              label={gettext("Lunches")}
              input_class="w-full"
            />
            <.input
              field={@form[:provided_dinners]}
              type="number"
              min="0"
              step="1"
              label={gettext("Dinners")}
              input_class="w-full"
            />
          </div>
        </div>
        <div class="space-y-3">
          <p class="text-sm text-grey-700">
            {gettext("Lump sums you can claim instead of receipts")}
          </p>
          <div class="grid grid-cols-[repeat(auto-fit,minmax(min(100%,15rem),1fr))] gap-4">
            <.input
              field={@form[:lump_sum_nights]}
              type="number"
              min="0"
              step="1"
              label={gettext("Nights without a receipt")}
              input_class="w-full"
            />
            <.input
              :if={@delegation.destination_country != "PL"}
              field={@form[:station_transfers]}
              type="number"
              min="0"
              step="1"
              label={gettext("One-way transfers to a station or airport abroad")}
              input_class="w-full"
            />
          </div>
          <.input
            field={@form[:local_transport_lump_sum]}
            type="checkbox"
            label={gettext("I paid for local public transport myself")}
          />
        </div>
      </fieldset>
      <dl :if={@per_diem} class="space-y-1 text-sm text-grey-700">
        <div :for={line <- @per_diem.lines} class="flex flex-wrap justify-between gap-3">
          <dt>{DelegationPresentation.per_diem_line_label(line, @delegation)}</dt>
          <dd class="tabular-nums">{Money.to_string!(line.amount)}</dd>
        </div>
        <div class="flex flex-wrap justify-between gap-3 pbs-2 text-base text-grey-900">
          <dt>{gettext("Per diem and lump sums")}</dt>
          <dd class="font-medium tabular-nums">{Money.to_string!(@per_diem.total)}</dd>
        </div>
      </dl>
      <p :if={!@per_diem} class="text-sm text-grey-700">
        {gettext("Complete the trip times to calculate the per diem.")}
      </p>
    </section>
    """
  end

  attr :delegation, :map, required: true
  attr :total, :any, required: true
  attr :balance, :any, required: true
  attr :balance_label, :string, required: true
  attr :class, :string, default: nil

  defp summary(assigns) do
    assigns =
      assign(assigns, :per_diem, PerDiem.for_delegation(assigns.delegation))

    ~H"""
    <div class={["rounded-lg bg-white px-6 py-4 shadow-sm", @class]}>
      <h2 class="font-normal text-grey-500">{gettext("Summary")}</h2>
      <dl class="mt-6 space-y-3 text-sm">
        <.summary_row
          label={gettext("Journeys")}
          value={
            SettlementPresentation.sum(
              SettlementPresentation.expenses_for(@delegation.expenses, :transport)
            )
          }
        />
        <.summary_row
          label={gettext("Accommodation")}
          value={
            SettlementPresentation.sum(
              SettlementPresentation.expenses_for(@delegation.expenses, :accommodation)
            )
          }
        />
        <.summary_row
          label={pgettext("settlement summary", "Other")}
          value={
            SettlementPresentation.sum(
              SettlementPresentation.expenses_for(@delegation.expenses, :other)
            )
          }
        />
        <.summary_row label={gettext("Per diem")} value={@per_diem && @per_diem.per_diem} />
        <.summary_row
          :if={@per_diem && !Money.zero?(@per_diem.lump_sums)}
          label={gettext("Lump sums")}
          value={@per_diem.lump_sums}
        />
        <div class="my-5 space-y-3 border-y border-grey-100 py-5">
          <.summary_row label={gettext("Total costs")} value={@total} class="font-medium" />
          <.summary_row label={gettext("Advance received")} value={@delegation.advance_amount} />
        </div>
        <.summary_row label={@balance_label} value={@balance} />
      </dl>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :class, :string, default: ""

  defp summary_row(assigns) do
    ~H"""
    <div class={["flex justify-between gap-4", @class]}>
      <dt>{@label}</dt><dd class={[@value && Money.zero?(@value) && "text-grey-500"]}>
        {if @value, do: Money.to_string!(@value), else: "—"}
      </dd>
    </div>
    """
  end

  attr :delegation, :map, required: true
  attr :date_change, :map, required: true
  attr :form, :map, required: true
  attr :editable?, :boolean, required: true

  defp date_change_notice(assigns) do
    detected_start_date = assigns.date_change.detected_start_date || assigns.delegation.start_date
    detected_end_date = assigns.date_change.detected_end_date || assigns.delegation.end_date

    assigns =
      assigns
      |> assign(:detected_start_date, detected_start_date)
      |> assign(:detected_end_date, detected_end_date)

    ~H"""
    <section
      id="delegation-date-change"
      class="mt-6 w-full rounded-lg border border-grey-200 bg-teal-100 p-6 text-teal-700"
    >
      <div class="flex flex-wrap items-center justify-between gap-3">
        <h2 class="flex items-center gap-2 font-medium">
          <Lucideicons.calendar_1 class="size-5" /> {gettext("Business trip date change")}
        </h2>
        <div class="flex items-center gap-2 font-medium tabular-nums">
          <span class="text-grey-500 line-through"><.date_range
            start_date={@delegation.start_date}
            end_date={@delegation.end_date}
          /></span>
          <.date_range start_date={@detected_start_date} end_date={@detected_end_date} />
        </div>
      </div>
      <p class="mt-4">
        {gettext(
          "The dates differ from those given in the request. If the change is intentional, give the reason. If not, check that the details above are correct."
        )}
      </p>
      <.input
        id={@form[:date_change_reason].id}
        name={@form[:date_change_reason].name}
        type="textarea"
        value={@form[:date_change_reason].value}
        errors={
          if blank?(@form[:date_change_reason].value),
            do: [gettext("This field is required")],
            else: []
        }
        placeholder={gettext("Give the reason for changing the business trip dates...")}
        disabled={!@editable?}
        class="mt-4"
      />
    </section>
    """
  end

  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(nil), do: true
  defp blank?(_value), do: false

  attr :delegation, :map, required: true

  defp settlement_status(assigns) do
    ~H"""
    <div class="mt-3 flex max-w-2xl flex-wrap items-center gap-3 text-grey-700">
      <.status_badge status={@delegation.status} />
      <p :if={@delegation.status == :submitted}>
        Rozliczenie nr {@delegation.settlement_sequence}/{@delegation.settlement_year} czeka na rozpatrzenie przez pracodawcę.
      </p>
      <p :if={@delegation.status == :complete && @delegation.settlement_sequence}>
        Rozliczenie nr {@delegation.settlement_sequence}/{@delegation.settlement_year} zostało zatwierdzone.
      </p>
      <.link
        :if={@delegation.settlement_sequence}
        kind="unstyled"
        redirect={Navigation.settlement_download_path(@delegation.reference)}
        download
        class="inline-flex items-center gap-1 font-medium text-teal-700"
      >
        <Lucideicons.file_down class="size-4" /> Pobierz rozliczenie
      </.link>
    </div>
    """
  end
end
