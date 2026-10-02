defmodule FirmowidWeb.Delegations.Components.SettlementPage do
  @moduledoc "Page layout and local browser behavior for delegation settlement."

  use FirmowidWeb, :html

  import FirmowidWeb.Delegations.Components.Delegation
  import FirmowidWeb.Delegations.Components.Settlement.Expense
  import FirmowidWeb.DesignSystem.Components.Button
  import FirmowidWeb.DesignSystem.Components.CoreComponents, except: [button: 1]
  import Phoenix.Component, except: [link: 1]

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
        phx-change={if @editable?, do: "validate"}
        phx-submit={if @editable?, do: "submit"}
        class="group relative mt-10 grid w-full gap-10 pb-12 font-[340] lg:grid-cols-[minmax(0,1fr)_22.5rem]"
      >
        <.nested_hidden_inputs :if={@editable?} form={@complete_form} />
        <section aria-labelledby="delegation-settlement-title" class="min-w-0">
          <small class="text-grey-500 text-sm">Cel:
          <span class="text-grey-700">{@delegation.purpose}</span></small>
          <dl class="text-grey-500 mt-2 flex gap-4 lg:hidden">
            <small>
              <dt class="inline">Termin:</dt>
              <dd class="text-grey-700 inline tabular-nums">
                <.date_range start_date={@delegation.start_date} end_date={@delegation.end_date} />
              </dd>
            </small>
          </dl>
          <.saved_notice :if={@editable?} class="mt-2 lg:hidden" />
          <h1 id="delegation-settlement-title" class="mt-1 text-2xl font-medium">
            Rozliczenie delegacji
          </h1>
          <p class="text-grey-700 mt-3 max-w-2xl text-balance">
            Załącz bilety i rachunki. Uzupełnij potrzebne dane. Kwoty i numery faktur uzupełnimy automatycznie.
          </p>

          <.expense_section
            title="Przejazdy"
            expenses={SettlementPresentation.expenses_for(@delegation.expenses, :transport)}
            upload={Map.get(assigns[:uploads] || %{}, :transport)}
            kind="transport"
            editable?={@editable?}
            sort_active?={@sort_active?}
            description_visible?={@description_visible?}
            expense_forms={@expense_forms}
            trip_forms={@trip_forms}
            timezone={@timezone}
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
            title="Nocleg"
            expenses={SettlementPresentation.expenses_for(@delegation.expenses, :accommodation)}
            upload={Map.get(assigns[:uploads] || %{}, :accommodation)}
            kind="accommodation"
            editable?={@editable?}
            sort_active?={false}
            description_visible?={@description_visible?}
            expense_forms={@expense_forms}
            trip_forms={@trip_forms}
            timezone={@timezone}
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
            title="Inne wydatki"
            expenses={SettlementPresentation.expenses_for(@delegation.expenses, :other)}
            upload={Map.get(assigns[:uploads] || %{}, :other)}
            kind="other"
            editable?={@editable?}
            sort_active?={false}
            description_visible?={@description_visible?}
            expense_forms={@expense_forms}
            trip_forms={@trip_forms}
            timezone={@timezone}
            related_upload={Map.get(assigns[:uploads] || %{}, :related_document)}
            expense_currencies={@expense_currencies}
            foreign_currency_modes={@foreign_currency_modes}
            nbp_settlements={@nbp_settlements}
            statement_upload={Map.get(assigns[:uploads] || %{}, :statement_document)}
            statement_expense_id={@statement_expense_id}
          >
            <:icon><Lucideicons.wallet class="size-5" /></:icon>
          </.expense_section>
          <.date_change_notice
            :if={@date_change}
            delegation={@delegation}
            date_change={@date_change}
            form={@complete_form}
            editable?={@editable?}
          />
        </section>
        <aside class="min-w-0 lg:pt-1">
          <dl class="text-grey-500 hidden justify-end gap-4 lg:flex">
            <small>
              <dt class="inline">Termin:</dt>
              <dd class="text-grey-700 inline tabular-nums">
                <.date_range start_date={@delegation.start_date} end_date={@delegation.end_date} />
              </dd>
            </small>
            <small>
              <dt class="inline">Zaliczka:</dt>
              <dd class="text-grey-700 inline">
                {Money.to_string!(@delegation.advance_payment_amount)}
              </dd>
            </small>
          </dl>
          <div :if={@editable?} class="relative mt-6 lg:mt-47">
            <.saved_notice class="absolute -top-12 right-0 hidden h-6 items-center justify-end lg:flex" />
            <.summary
              delegation={@delegation}
              total={@total}
              balance={@balance}
              balance_label={@balance_label}
            />
            <.error :if={@submission_failed? and is_nil(@date_change)}>
              Nie udało się wysłać ewidencji. Uzupełnij wymagane pola.
            </.error>
            <.button
              type="submit"
              variant="primary"
              accent="turquoise"
              size="big"
              class="mt-6 w-full"
              disabled={@uploading?}
            >Wyślij</.button>
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

  attr :class, :string, default: nil

  defp saved_notice(assigns) do
    ~H"""
    <div class={@class}>
      <span class="font-lexend text-grey-500 inline-flex items-center gap-1 text-[11px] font-medium uppercase group-[.phx-change-loading]:hidden">Zmiany zostały zapisane
      <.save_check_icon class="size-3" /></span>
      <span class="font-lexend text-grey-500 hidden items-center gap-1 text-[11px] font-medium uppercase group-[.phx-change-loading]:inline-flex">Zapisywanie zmian
      <Lucideicons.refresh_ccw class="size-3 animate-spin [animation-direction:reverse]" /></span>
    </div>
    """
  end

  attr :delegation, :map, required: true
  attr :total, :any, required: true
  attr :balance, :any, required: true
  attr :balance_label, :string, required: true
  attr :class, :string, default: nil

  defp summary(assigns) do
    ~H"""
    <div class={["rounded-lg bg-white px-6 py-4 shadow-sm", @class]}>
      <h2 class="text-grey-500 font-normal">Podsumowanie</h2>
      <dl class="mt-6 space-y-3 text-sm">
        <.summary_row
          label="Przejazdy"
          value={
            SettlementPresentation.sum(
              SettlementPresentation.expenses_for(@delegation.expenses, :transport)
            )
          }
        />
        <.summary_row
          label="Nocleg"
          value={
            SettlementPresentation.sum(
              SettlementPresentation.expenses_for(@delegation.expenses, :accommodation)
            )
          }
        />
        <.summary_row
          label="Inne"
          value={
            SettlementPresentation.sum(
              SettlementPresentation.expenses_for(@delegation.expenses, :other)
            )
          }
        />
        <div class="border-grey-100 my-5 space-y-3 border-y py-5">
          <.summary_row label="Razem koszty" value={@total} class="font-medium" />
          <.summary_row label="Pobrana zaliczka" value={@delegation.advance_payment_amount} />
        </div>
        <.summary_row label={@balance_label} value={@balance} />
      </dl>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, Money, required: true
  attr :class, :string, default: ""

  defp summary_row(assigns) do
    ~H"""
    <div class={["flex justify-between gap-4", @class]}>
      <dt>{@label}</dt><dd class={[Money.zero?(@value) && "text-grey-500"]}>
        {Money.to_string!(@value)}
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
      class="bg-turquoise-100 border-grey-200 text-turquoise-700 mt-6 w-full rounded-lg border p-6"
    >
      <div class="flex flex-wrap items-center justify-between gap-3">
        <h2 class="flex items-center gap-2 font-medium">
          <Lucideicons.calendar_1 class="size-5" /> Zmiana terminu delegacji
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
        Terminy różnią się od tych podanych w zgłoszeniu. Jeśli jest to zmiana celowa, podaj jej powód. Jeśli nie, sprawdź poprawność powyższych danych.
      </p>
      <.input
        id={@form[:date_change_reason].id}
        name={@form[:date_change_reason].name}
        type="textarea"
        value={@form[:date_change_reason].value}
        errors={if blank?(@form[:date_change_reason].value), do: ["To pole jest wymagane"], else: []}
        new
        placeholder="Podaj powód zmiany terminu delegacji..."
        disabled={!@editable?}
        class="mt-4"
      />
    </section>
    """
  end

  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(nil), do: true
  defp blank?(_value), do: false

  attr :class, :string, default: nil

  defp save_check_icon(assigns) do
    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
      class={@class}
      aria-hidden="true"
    >
      <path d="M12.5 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h10.2a2 2 0 0 1 1.4.6l3.8 3.8a2 2 0 0 1 .6 1.4v4.35" />
      <path d="m16 19 2 2 4-4" />
      <path d="M17 15.13V14a1 1 0 0 0-1-1H8a1 1 0 0 0-1 1v7" />
      <path d="M7 3v4a1 1 0 0 1 1 1h7" />
    </svg>
    """
  end
end
