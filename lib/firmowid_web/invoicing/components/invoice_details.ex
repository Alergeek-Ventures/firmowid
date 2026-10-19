defmodule FirmowidWeb.Invoicing.Components.InvoiceDetails do
  @moduledoc """
  Stateless function components for invoice detail views.

  Contains shared components (headers, transaction matches, skip invoicing)
  used by both Cost and Sales invoice details, as well as sales-specific
  components like `sales_invoice_metadata/1`.
  """

  use FirmowidWeb, :html

  import FirmowidUI.Components.Button
  import FirmowidWeb.DesignSystem.Components.CoreComponents, except: [button: 1]
  import FirmowidWeb.DesignSystem.Components.InvoicingBadges
  import FirmowidWeb.Invoicing.Components.StatusButton
  import Phoenix.Component, except: [link: 1]

  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Invoicing.RecommendationThresholds
  alias FirmowidWeb.Invoicing.Components.MatchingComponents
  alias FirmowidWeb.Invoicing.Utilities.Navigation

  attr :is_cost_invoice, :boolean
  attr :variant, :string, required: true
  attr :issue_date, Date, required: true
  attr :party_display_name, :string, required: true
  attr :description, :string
  attr :return_to, :string, default: nil

  def invoice_header(assigns) do
    ~H"""
    <header class={[
      "flex flex-row items-center gap-4 px-4 py-7 lg:gap-8 lg:px-8",
      @is_cost_invoice && "bg-orange-200",
      !@is_cost_invoice && "bg-turquoise-200"
    ]}>
      <.back
        navigate={@return_to || default_return_path(@issue_date)}
        icon_only
      />
      <div class="flex flex-col gap-2">
        <h1 class="text-lg/tight font-medium lg:text-2xl">{@party_display_name}</h1>
        <h2 class="text-darkGrey">{@description}</h2>
      </div>
      <div class="ml-auto flex flex-row items-center gap-4">
        <h2 class="text-darkGrey">{invoice_source_badge_label(@variant)}</h2>
        <.invoice_source_badge variant={@variant} size="big" />
      </div>
    </header>
    """
  end

  slot :inner_block, required: false

  def aside(assigns) do
    ~H"""
    <aside class="order-last flex w-full shrink-0 flex-col p-8 lg:order-0 lg:h-[calc(100vh-var(--navbar-height)-128px)] lg:max-w-lg lg:overflow-y-auto xl:max-w-[659px]">
      {render_slot(@inner_block)}
    </aside>
    """
  end

  slot :inner_block, required: false

  def main(assigns) do
    ~H"""
    <main class="mt-8 w-full border-b-2 border-grey-100 px-8 pb-8 lg:border-b-0 lg:border-l-2">
      {render_slot(@inner_block)}
    </main>
    """
  end

  slot :subpreview do
    attr :invoice_number_label, :string, required: true
  end

  def invoice_preview(assigns) do
    ~H"""
    <div class="mx-auto mt-8 flex w-full max-w-max flex-col gap-4">
      <h3 class="leading/snug ml-1 self-start text-sm text-grey-700">Podgląd faktury</h3>
      <%= case @subpreview do %>
        <% [main] -> %>
          <.invoice_preview_border>
            {render_slot(main)}
          </.invoice_preview_border>
        <% [main | subpreviews] -> %>
          <div class="flex w-full flex-col-reverse gap-4 xl:flex-row">
            <div class="flex w-full min-w-0 shrink-2 flex-col gap-4">
              <.invoice_subpreview
                :for={subpreview <- subpreviews}
                label={subpreview.invoice_number_label}
              >
                {render_slot(subpreview)}
              </.invoice_subpreview>
            </div>

            <.invoice_subpreview label={main.invoice_number_label}>
              {render_slot(main)}
            </.invoice_subpreview>
          </div>
      <% end %>
    </div>
    """
  end

  slot :inner_block, required: false

  defp invoice_preview_border(assigns) do
    ~H"""
    <div class="transition-duration-300 w-full overflow-hidden rounded border-2 border-grey-200 transition-opacity hover:opacity-50">
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :label, :string, required: true
  slot :inner_block, required: false

  defp invoice_subpreview(assigns) do
    ~H"""
    <div class="flex w-full min-w-0 flex-col gap-2">
      <p class="ml-1 text-sm/tight font-medium text-grey-700">
        {@label}
      </p>
      <.invoice_preview_border>
        {render_slot(@inner_block)}
      </.invoice_preview_border>
    </div>
    """
  end

  attr :is_cost_invoice, :boolean
  attr :amount, :any, required: true
  attr :lang, :atom, default: :pl

  def invoice_amount(assigns) do
    assigns = assign(assigns, :is_refund, refund?(assigns))

    ~H"""
    <div class="flex flex-col items-end justify-between gap-2 pl-1">
      <label class="text-sm/snug text-grey-700" for="total-amount">
        {invoice_amount_label(@lang, @is_refund)}
      </label>
      <p
        id="total-amount"
        class={[
          "rounded bg-[#DEDEDE4C] px-4 py-2 text-lg/tight",
          @is_cost_invoice && "text-orange-700",
          !@is_cost_invoice && "text-turquoise-700"
        ]}
      >
        {@amount}
      </p>
    </div>
    """
  end

  defp invoice_amount_label(lang, is_refund) do
    case {lang, is_refund} do
      {:en, true} -> "Total to refund"
      {:en, false} -> "Total to pay"
      {:pl, true} -> "Razem do zwrotu"
      {:pl, false} -> "Razem do zapłaty"
    end
  end

  defp refund?(%{is_cost_invoice: true, amount: amount}) do
    Decimal.gt?(Money.to_decimal(amount), 0)
  end

  defp refund?(_assigns), do: false

  attr :internal_notes, :list, required: true

  def invoice_notes(assigns) do
    ~H"""
    <div class="flex flex-col gap-2 py-2 pl-1">
      <label class="pb-1 text-sm/snug text-nowrap text-darkGrey">
        Komentarze
      </label>
      <ol class="list-inside list-disc">
        <%= for note <- @internal_notes do %>
          <li
            id={"internal_note-#{note}"}
            class="leading-snug"
          >
            {note}
          </li>
        <% end %>
      </ol>
    </div>
    """
  end

  slot :inner_block, required: false

  def invoice_metadata(assigns) do
    ~H"""
    <div class="grid grid-cols-[min-content_1fr] items-center gap-x-2 gap-y-1 py-6">
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :invoice, SalesInvoice, required: true
  attr :lang, :atom, default: :pl

  def sales_invoice_metadata(assigns) do
    labels =
      if assigns.lang == :en do
        %{
          invoice_number: "Invoice number",
          ksef_id: "KSeF ID",
          buyer: "Buyer",
          issue_date: "Issue date",
          sale_date: "Sale date",
          due_date: "Payment deadline"
        }
      else
        %{
          invoice_number: "Numer faktury",
          ksef_id: "Identyfikator KSeF",
          buyer: "Kupujący",
          issue_date: "Data wystawienia",
          sale_date: "Data sprzedaży",
          due_date: "Termin płatności"
        }
      end

    assigns = assign(assigns, :labels, labels)

    ~H"""
    <div class="flex flex-col gap-4">
      <div class="grid grid-cols-[145px_1fr] gap-2">
        <.invoice_metadata_piece
          label={@labels.invoice_number}
          value={@invoice.invoice_number}
          piece_id="inv-id"
        />
        <.invoice_metadata_piece
          :if={@invoice.ksef_number != nil}
          label={@labels.ksef_id}
          value={@invoice.ksef_number}
          piece_id="ksef-id"
        />
        <.invoice_metadata_piece
          label={@labels.buyer}
          value={@invoice.buyer_display_name_label}
          piece_id="buyer"
          multiline
        />
        <.invoice_metadata_piece
          label={@labels.issue_date}
          value={@invoice.issue_date}
          piece_id="issue-date"
        />
        <.invoice_metadata_piece
          label={@labels.sale_date}
          value={@invoice.sale_date}
          piece_id="sale-date"
        />
        <.invoice_metadata_piece
          label={@labels.due_date}
          value={@invoice.due_date}
          piece_id="due-date"
        />
      </div>

      <.invoice_amount
        is_cost_invoice={false}
        lang={@lang}
        amount={@invoice.amount}
      />
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :piece_id, :string, default: nil
  attr :multiline, :boolean, default: false

  def invoice_metadata_piece(assigns) do
    ~H"""
    <div class="col-span-2 grid grid-cols-subgrid rounded px-1 py-0.5 odd:bg-greyButtonBg/30">
      <label
        for={@piece_id}
        class={[
          "text-sm/snug text-nowrap text-darkGrey",
          !@multiline && "self-center"
        ]}
      >
        {@label}
      </label>
      <p
        id={@piece_id}
        class={["leading-snug", @multiline && "mb-8"]}
      >
        {@value}
      </p>
    </div>
    """
  end

  attr :transaction_id, :string, required: true
  attr :prediction_score, :float, required: true
  attr :is_highest_green, :boolean, default: false

  def prediction_score_indicator(assigns) do
    # consult
    # lib/firmowid/invoicing/matching/training/logisitic-regression.livemd
    # to retrain and recalculate the thresholds

    prediction_level =
      RecommendationThresholds.prediction_level(
        assigns.prediction_score,
        assigns.is_highest_green
      )

    assigns = assign(assigns, :prediction_level, prediction_level)

    ~H"""
    <MatchingComponents.score_indicator
      id={"match-prediction-score-#{@transaction_id}"}
      level={@prediction_level}
      tooltip={"Ocena AI: #{Float.round(100 * @prediction_score, 2)}% pewności"}
    />
    """
  end

  attr :is_cost_invoice, :boolean, required: true
  attr :transactions, :list, required: true
  slot :status_action, required: true

  def transaction_match(assigns) do
    transactions = assigns.transactions
    single_transaction? = length(transactions) == 1

    currencies =
      transactions
      |> Enum.map(&(&1.amount |> Money.to_currency_code() |> Atom.to_string()))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    show_total? = not single_transaction? and length(currencies) == 1

    assigns =
      assigns
      |> assign(:single_transaction?, single_transaction?)
      |> assign(:show_total?, show_total?)

    assigns =
      if show_total? do
        assigns
        |> assign(
          :total,
          Enum.reduce(transactions, Decimal.new(0), fn transaction, acc ->
            Decimal.add(Money.to_decimal(transaction.amount), acc)
          end)
        )
        |> assign(:currency, List.first(currencies))
      else
        assigns
      end

    ~H"""
    <section class="space-y-8">
      <MatchingComponents.confirmed_header>
        <:action>
          {render_slot(@status_action)}
        </:action>
      </MatchingComponents.confirmed_header>

      <div class="flex flex-col gap-4">
        <MatchingComponents.confirmed_card
          :for={transaction <- @transactions}
          amount={transaction.amount}
          large_amount?={@single_transaction?}
        >
          <:detail
            :for={
              {label, val} <- [
                {"Kontrahent",
                 if(@is_cost_invoice, do: transaction.creditor_name, else: transaction.debtor_name)},
                {"Wierzyciel",
                 if(not @is_cost_invoice,
                   do: transaction.creditor_name,
                   else: transaction.debtor_name
                 )},
                {"Zaksięgowano", transaction.booking_date},
                transaction.value_date && {"Przewalutowano", transaction.value_date}
              ]
            }
            label={label}
          >
            {val}
          </:detail>
        </MatchingComponents.confirmed_card>

        <div
          :if={@show_total?}
          class="flex flex-row items-center justify-between rounded-md bg-[#D0E6CE66] p-4"
        >
          <p class="text-sm text-grey-700">Suma</p>

          <p class="text-lg/tight text-green-700">
            {if @is_cost_invoice, do: "-", else: ""}{Money.new(@currency, @total)}
          </p>
        </div>
      </div>

      <div class="space-y-6">
        <h3 class="leading-tight font-medium">Co jeszcze możesz zrobić?</h3>

        <div class="grid grid-cols-[1fr_8rem] gap-6 lg:gap-x-10">
          <div
            :for={transaction <- @transactions}
            class="col-span-full grid grid-cols-subgrid items-center"
          >
            <p class="text-sm/snug text-balance text-grey-700">
              <%= if @single_transaction? do %>
                Poproś Firmowida o pomoc w znalezieniu kolejnych faktur dla tej transakcji.
              <% else %>
                Poproś Firmowida o pomoc w znalezieniu kolejnych faktur dla transakcji zaksięgowanej {transaction.booking_date}.
              <% end %>
            </p>

            <.button
              disabled
              class="w-full"
              variant="primary"
              accent={if(@is_cost_invoice, do: "orange", else: "turquoise")}
              size="small"
            >
              Zapytaj
            </.button>
          </div>
        </div>
      </div>
    </section>
    """
  end

  attr :is_cost_invoice, :boolean, required: true
  attr :can_write, :boolean, default: true

  def invoice_skipped_view(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="flex flex-row items-center justify-between">
        <p class="text-lg/tight font-medium">Transakcja pominięta</p>
        <div :if={@can_write} class="flex w-32 flex-row gap-1">
          <div class="flex flex-1 items-center justify-center rounded-md bg-green-200 px-2 text-green-700">
            <.icon name="hero-document-text-micro" class="size-4" />
          </div>
          <.status_button
            phx-click="toggle-invoicing"
            class="flex-1"
            icon="hero-arrow-uturn-left-micro"
          />
        </div>
      </div>
      <div class="flex flex-col gap-6 rounded bg-grey-100 p-6">
        <p class="text-base/snug">Transakcja została pominięta dla dokumentu</p>
        <div :if={false} class="space-y-2">
          <label class="text-sm/snug text-grey-700" for="temp">Powód pominięcia</label>

          <div class="flex flex-row items-center gap-2">
            <.input id="temp" name="test" value="" class="flex-1" new={true} />
            <.button
              variant="primary"
              accent={if(@is_cost_invoice, do: "orange", else: "turquoise")}
              size="small"
            >
              Zatwierdź
            </.button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :invoice, :map, required: true
  attr :show_bank_transfer_modal, :boolean, default: true
  attr :show_assistant, :boolean, default: false
  attr :can_write, :boolean, default: true

  def skip_invoicing(assigns) do
    ~H"""
    <div class="grid grid-cols-[1fr_8rem] gap-6 lg:gap-x-10">
      <%= if @show_bank_transfer_modal do %>
        <div class="col-span-full grid grid-cols-subgrid">
          <p class="text-sm/snug text-balance text-grey-700">
            Wykonaj przelew teraz - kliknij przycisk, aby skopiować potrzebne dane.
          </p>
          <.live_component
            id="bank-transfer-modal"
            module={FirmowidWeb.Invoicing.Components.BankTransferModal}
            invoice={@invoice}
          />
        </div>
      <% end %>
      <div :if={@show_assistant} class="col-span-full grid grid-cols-subgrid">
        <p class="self-center text-sm/snug text-balance text-grey-700">
          Poproś Firmowida o pomoc w znalezieniu transakcji.
        </p>

        <.button
          disabled
          class="w-full"
          variant="primary"
          accent="turquoise"
          size="small"
        >
          Zapytaj
        </.button>
      </div>

      <div :if={@can_write} class="col-span-full grid grid-cols-subgrid items-center">
        <p class="text-sm/snug text-balance text-grey-700">
          A może żadna transakcja nie pasuje, bo zapłacono gotówką, lub na inne konto?
          Pomiń jej szukanie. Firmowid oznaczy ją jako rozliczoną poza systemem.
        </p>
        <div class="flex h-8 w-full flex-row items-start gap-2">
          <div class="flex items-center justify-center rounded-md bg-grey-200 p-2 text-grey-700">
            <.icon name="hero-document-text-solid" class="size-4" />
          </div>
          <.button
            phx-click="toggle-invoicing"
            class="size-full"
            variant="secondary"
            size="small"
          >
            Pomiń
          </.button>
        </div>
      </div>
    </div>
    """
  end

  attr :invoice, :map, required: true
  attr :is_cost_invoice, :boolean, required: true
  attr :potential_transactions, :list, required: true
  attr :can_write, :boolean, default: true

  def potential_transactions(assigns) do
    assigns = assign(assigns, :not_found, Enum.empty?(assigns.potential_transactions))

    ~H"""
    <div class="flex flex-col gap-18">
      <%= if @not_found do %>
        <div class="flex flex-col items-center gap-4 px-4 pt-8 pb-6">
          <Lucideicons.file_question_mark class="size-12" />

          <div class="space-y-2 text-center">
            <h3 class="text-lg/tight font-medium">Brak rekomendacji</h3>
            <p class="max-w-96 text-balance">
              Firmowid nie znalazl zadnych transakcji, ktore potencjalnie pasowałyby do tej faktury.
            </p>
          </div>

          <.button
            disabled
            class="mt-2"
            variant="primary"
            accent={if(@is_cost_invoice, do: "orange", else: "turquoise")}
            size="small"
          >
            Poproś Firmowida o pomoc
          </.button>
        </div>
      <% else %>
        <.potential_transactions_list
          potential_transactions={@potential_transactions}
          name_field={if(@is_cost_invoice, do: :creditor_name, else: :debtor_name)}
        />
      <% end %>

      <div class="space-y-6">
        <h3 :if={@not_found and (@can_write or @is_cost_invoice)} class="leading-tight font-medium">
          Co jeszcze mozesz zrobic?
        </h3>
        <.skip_invoicing
          show_assistant={not @not_found}
          show_bank_transfer_modal={@is_cost_invoice}
          invoice={@invoice}
          can_write={@can_write}
        />
      </div>
    </div>
    """
  end

  attr :potential_transactions, :list, required: true
  attr :name_field, :atom, required: true

  def potential_transactions_list(assigns) do
    potential_transactions = assigns.potential_transactions
    green_idx = RecommendationThresholds.highest_green_index(potential_transactions)

    assigns = assign(assigns, :green_idx, green_idx)

    ~H"""
    <MatchingComponents.candidates
      title="Potencjalne transakcje dla dokumentu"
      date_label="Data"
      amount_label="Kwota"
    >
      <:candidate
        :for={{{tx, score}, idx} <- Enum.with_index(@potential_transactions)}
        id={"potential-transaction-#{tx.id}"}
        name={Map.get(tx, @name_field)}
        description={tx.remittance_information_unstructured}
        date={tx.booking_date}
        amount={tx.amount}
      >
        <.prediction_score_indicator
          transaction_id={tx.id}
          prediction_score={score}
          is_highest_green={@green_idx == idx}
        />
        <.button
          phx-click="connect"
          phx-value-transaction_id={tx.id}
          variant={if(@green_idx == idx, do: "tertiary", else: "secondary")}
          size="small"
        >
          Zatwierdź
        </.button>
      </:candidate>
    </MatchingComponents.candidates>
    """
  end

  attr :id, :string, default: "invoice-preview-scaler"
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def scalable_invoice_preview(assigns) do
    ~H"""
    <div
      id={@id}
      class={["w-full origin-top-left", @class]}
      phx-hook=".AutoHeightScaler"
    >
      <div class="origin-top-left" data-scaler-inner>
        {render_slot(@inner_block)}
      </div>
    </div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".AutoHeightScaler">
      export default {
        mounted() {
          this.inner = this.el.querySelector("[data-scaler-inner]");

          this.recompute = () => {
            const containerWidth = this.el.getBoundingClientRect().width;
            const contentWidth = this.inner.scrollWidth;

            const scale = containerWidth / contentWidth;

            this.inner.style.transform = `scale(${scale})`;
            this.el.style.height = `${this.inner.scrollHeight * scale}px`;
          };

          this.containerObserver = new ResizeObserver(this.recompute);
          this.contentObserver = new ResizeObserver(this.recompute);
          this.containerObserver.observe(this.el);
          this.contentObserver.observe(this.inner);

          this.recompute();
        },
        destroyed() {
          this.containerObserver?.disconnect();
          this.contentObserver?.disconnect();
        }
      };
    </script>
    """
  end

  defp default_return_path(issue_date) do
    Navigation.default_invoicing_path(issue_date)
  end
end
