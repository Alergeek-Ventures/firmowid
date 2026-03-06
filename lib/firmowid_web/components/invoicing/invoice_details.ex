defmodule FirmowidWeb.Components.Invoicing.InvoiceDetails do
  @moduledoc """
  Stateless function components for invoice detail views.

  Contains shared components (headers, transaction matches, skip invoicing)
  used by both Cost and Sales invoice details, as well as sales-specific
  components like `sales_invoice_metadata/1`.
  """

  use FirmowidWeb, :html

  alias Firmowid.SalesInvoices
  alias Firmowid.SalesInvoices.SalesInvoice

  attr :is_cost_invoice, :boolean
  attr :issue_date, Date, required: true
  attr :party_display_name, :string, required: true
  attr :description, :string
  attr :return_to, :string, default: nil

  def invoice_header(assigns) do
    ~H"""
    <header class={[
      "flex flex-row px-4 py-7 lg:px-8 items-center gap-4 lg:gap-8",
      @is_cost_invoice && "bg-orange-200",
      !@is_cost_invoice && "bg-turquoise-200"
    ]}>
      <.link navigate={@return_to || ~p"/fakturowanie?month=#{@issue_date |> Date.to_iso8601()}"}>
        <.icon name="hero-arrow-left-circle-solid" class="w-7 h-7" />
      </.link>
      <div class="flex flex-col gap-2">
        <h1 class="text-lg lg:text-2xl leading-tight font-medium">{@party_display_name}</h1>
        <h2 class="text-darkGrey">{@description}</h2>
      </div>
    </header>
    """
  end

  slot :inner_block, required: false

  def aside(assigns) do
    ~H"""
    <aside class={[
      "w-full lg:max-w-lg xl:max-w-[659px] shrink-0",
      "flex flex-col order-last lg:order-0 p-8",
      "lg:overflow-y-auto lg:h-[calc(100vh-var(--navbar-height)-128px)]"
    ]}>
      {render_slot(@inner_block)}
    </aside>
    """
  end

  slot :inner_block, required: false

  def main(assigns) do
    ~H"""
    <main class="px-8 pb-8 mt-8 border-b-2 lg:border-b-0 lg:border-l-2 border-grey-100 w-full">
      {render_slot(@inner_block)}
    </main>
    """
  end

  slot :inner_block, required: false

  def invoice_preview(assigns) do
    ~H"""
    <div class="mt-8 flex flex-col gap-4 w-full max-w-max mx-auto">
      <h3 class="self-start text-sm leading/snug text-grey-700 ml-1">Podgląd faktury</h3>
      {render_slot(@inner_block)}
    </div>
    """
  end

  slot :inner_block, required: false

  def invoice_preview_border(assigns) do
    ~H"""
    <div class="border-grey-200 border-2 rounded overflow-hidden transition-opacity transition-duration-300 hover:opacity-50 w-full">
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :label, :string, required: true
  slot :inner_block, required: false

  def invoice_subpreview(assigns) do
    ~H"""
    <div class="flex flex-col gap-2 w-full min-w-0">
      <p class="text-sm/tight text-grey-700 font-medium ml-1">
        {@label}
      </p>
      <.invoice_preview_border>
        {render_slot(@inner_block)}
      </.invoice_preview_border>
    </div>
    """
  end

  attr :is_cost_invoice, :boolean
  attr :total_amount, :any, required: true
  attr :lang, :atom, default: :pl

  def invoice_amount(assigns) do
    ~H"""
    <div class="flex flex-row gap-2 items-start justify-between pl-1">
      <label class="text-grey-700 text-sm/snug" for="total-amount">
        {if @lang == :en, do: "Total to pay", else: "Razem do zapłaty"}
      </label>
      <p
        id="total-amount"
        class={[
          "text-lg/tight bg-[#DEDEDE4C] px-4 py-2 rounded",
          @is_cost_invoice && "text-orange-700",
          !@is_cost_invoice && "text-turquoise-700"
        ]}
      >
        {@total_amount}
      </p>
    </div>
    """
  end

  slot :inner_block, required: false

  def invoice_metadata(assigns) do
    ~H"""
    <div class="grid grid-cols-[min-content_1fr] items-center gap-y-1 gap-x-2 py-6">
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
          value={SalesInvoices.buyer_display_name(@invoice)}
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
        total_amount={Money.new(@invoice.currency, SalesInvoice.get_gross_value(@invoice))}
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
    <div class="grid grid-cols-subgrid col-span-2 rounded odd:bg-greyButtonBg/[0.3] py-0.5 px-1">
      <label
        for={@piece_id}
        class={[
          "text-sm/snug text-darkGrey text-nowrap",
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

  def prediction_score_indicator(%{predicition_level: :high} = assigns) do
    ~H"""
    <div
      id={"match-prediction-score-#{@transaction_id}"}
      phx-hook="Tippy"
      data-tippy-content={"Ocena AI: #{Float.round(100 *@prediction_score, 2)}% pewności"}
      class="flex flex-col justify-between p-2 size-8 shrink-0 rounded-md bg-green-200"
    >
      <div class="w-full rounded-md h-0.5 bg-green-700" />
      <div class="w-[70%] rounded-md h-0.5 bg-green-700" />
      <div class="w-[40%] rounded-md h-0.5 bg-green-700" />
    </div>
    """
  end

  def prediction_score_indicator(%{predicition_level: :mid} = assigns) do
    ~H"""
    <div
      id={"match-prediction-score-#{@transaction_id}"}
      phx-hook="Tippy"
      data-tippy-content={"Ocena AI: #{Float.round(100 *@prediction_score, 2)}% pewności"}
      class="flex flex-col justify-between p-2 size-8 shrink-0 rounded-md bg-orange-200"
    >
      <div class="w-full rounded-md h-0.5 bg-white" />
      <div class="w-[70%] rounded-md h-0.5 bg-orange-700" />
      <div class="w-[40%] rounded-md h-0.5 bg-orange-700" />
    </div>
    """
  end

  def prediction_score_indicator(%{predicition_level: :low} = assigns) do
    ~H"""
    <div
      id={"match-prediction-score-#{@transaction_id}"}
      phx-hook="Tippy"
      data-tippy-content={"Ocena AI: #{Float.round(100 *@prediction_score, 2)}% pewności"}
      class="flex flex-col justify-between p-2 size-8 shrink-0 rounded-md bg-red-200"
    >
      <div class="w-full rounded-md h-0.5 bg-white" />
      <div class="w-[70%] rounded-md h-0.5 bg-white" />
      <div class="w-[40%] rounded-md h-0.5 bg-red-700" />
    </div>
    """
  end

  def prediction_score_indicator(assigns) do
    # consult
    # lib/firmowid/invoicing/matching/training/logisitic-regression.livemd
    # to retrain and recalculate the thresholds

    predicition_level =
      cond do
        assigns.prediction_score >= 0.92 and assigns.is_highest_green -> :high
        assigns.prediction_score >= 0.87 -> :mid
        true -> :low
      end

    assigns = assign(assigns, predicition_level: predicition_level)

    prediction_score_indicator(assigns)
  end

  attr :is_cost_invoice, :boolean, required: true
  attr :transactions, :list, required: true

  def transaction_match(assigns) do
    transactions = assigns.transactions
    single_transaction? = length(assigns.transactions) == 1

    assigns = assign(assigns, :single_transaction?, single_transaction?)

    assigns =
      if single_transaction? do
        assigns
      else
        assigns
        |> assign(:total, Enum.reduce(transactions, Decimal.new(0), &Decimal.add(&1.transaction_amount, &2)))
        |> assign(:currency, hd(transactions).transaction_currency)
      end

    ~H"""
    <div class="flex flex-col gap-4">
      <div class="flex flex-row justify-between items-center">
        <p class="text-lg/tight font-medium">Dopasowanie</p>

        <div class="flex flex-row gap-2">
          <div class="self-stretch px-[14.5px] flex flex-row items-center rounded-md bg-green-200">
            <p class="text-sm/tight font-medium text-green-700">Komplet</p>
          </div>
          <.button
            color="light_grey"
            size="small"
            new={true}
            phx-click="disconnect"
          >
            <.icon name="hero-arrow-uturn-left-micro" class="h-4 w-4" />
          </.button>
        </div>
      </div>

      <div
        :for={transaction <- @transactions}
        class="grid grid-flow-col grid-cols-[2fr_1fr_1fr] grid-rows-2 gap-x-4 gap-y-6 p-4 rounded-md bg-[#D0E6CE66]"
      >
        <%= for {label, val} <- [
            {"Kontrahent", if(@is_cost_invoice, do: transaction.creditor_name, else: transaction.debtor_name)},
            {"Wierzyciel", if(not @is_cost_invoice, do: transaction.creditor_name, else: transaction.debtor_name)},
            {"Zaksięgowano", transaction.booking_date},
            transaction.value_date && {"Przewalutowano", transaction.value_date},
          ] do %>
          <div class="space-y-1">
            <p class="text-sm/snug text-grey-700">{label}</p>
            <p class="leading-snug">{val}</p>
          </div>
        <% end %>

        <div class="flex items-end justify-end text-right row-span-2">
          <p class={["leading-snug text-green-700", @single_transaction? && "text-lg"]}>
            {Money.new(transaction.transaction_amount, transaction.transaction_currency)}
          </p>
        </div>
      </div>

      <div
        :if={not @single_transaction?}
        class="flex flex-row justify-between items-center p-4 rounded-md bg-[#D0E6CE66]"
      >
        <p class="text-sm text-grey-700">Suma</p>

        <p class="text-lg/tight text-green-700">
          {if @is_cost_invoice, do: "-", else: ""}{Money.new(@total, @currency)}
        </p>
      </div>
    </div>
    """
  end

  attr :is_cost_invoice, :boolean, required: true

  def invoice_skipped_view(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="flex flex-row justify-between items-center">
        <p class="text-lg/tight font-medium">Transakcja pominięta</p>
        <div class="flex flex-row gap-2 w-32">
          <div class="flex-1 h-8 flex justify-center items-center p-2 rounded-md bg-green-200 text-green-700">
            <.icon name="hero-document-text-micro" class="size-4" />
          </div>
          <.button
            phx-click="toggle-invoicing"
            color="light_grey"
            size="small"
            new={true}
            class="flex-1"
          >
            <.icon name="hero-arrow-uturn-left-micro" class="size-4" />
          </.button>
        </div>
      </div>
      <div class="flex flex-col gap-6 p-6 rounded bg-grey-100">
        <p class="text-base/snug">Transakcja została pominięta dla dokumentu</p>
        <div :if={false} class="space-y-2">
          <label class="text-sm/snug text-grey-700" for="temp">Powód pominięcia</label>

          <div class="flex flex-row gap-2 items-center">
            <.input id="temp" name="test" value="" class="flex-1" new={true} />
            <.button
              color={if(@is_cost_invoice, do: "orange", else: "turquoise")}
              size="small"
              new={true}
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

  def skip_invoicing(assigns) do
    ~H"""
    <div class="gap-y-6 gap-x-6 lg:gap-x-10 grid grid-cols-[1fr_8rem]">
      <%= if @show_bank_transfer_modal do %>
        <div class="grid grid-cols-subgrid col-span-full">
          <p class="text-sm/snug text-grey-700 text-balance">
            Wykonaj przelew teraz - kliknij przycisk, aby skopiować potrzebne dane.
          </p>
          <.live_component
            id="bank-transfer-modal"
            module={FirmowidWeb.Components.Invoicing.BankTransferModal}
            invoice={@invoice}
          />
        </div>
      <% end %>
      <div :if={@show_assistant} class="grid grid-cols-subgrid col-span-full">
        <p class="text-sm/snug text-grey-700 text-balance self-center">
          Poproś Firmowida o pomoc w znalezieniu transakcji.
        </p>

        <.button
          phx-click="show_chat"
          phx-target="#invoice-show"
          class="w-full"
          color="turquoise"
          size="small"
          new={true}
        >
          Zapytaj
        </.button>
      </div>

      <div class="grid grid-cols-subgrid col-span-full">
        <p class="text-sm/snug text-grey-700 text-balance">
          A może żadna transakcja nie pasuje, bo zapłacono gotówką, lub na inne konto?
          Pomiń jej szukanie. Firmowid oznaczy ją jako rozliczoną poza systemem.
        </p>
        <div class="w-full flex flex-row gap-2 items-start">
          <div class="flex justify-center items-center p-2 rounded-md text-grey-700 bg-grey-200">
            <.icon name="hero-document-text-solid" class="size-4" />
          </div>
          <.button
            phx-click="toggle-invoicing"
            class="w-full"
            color="light_grey"
            size="small"
            new={true}
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

  def potential_transactions(assigns) do
    assigns = assign(assigns, :not_found, Enum.empty?(assigns.potential_transactions))

    ~H"""
    <div class="flex flex-col gap-18">
      <%= if @not_found do %>
        <div class="gap-4 flex flex-col items-center pt-8 pb-6 px-4">
          <Lucideicons.file_question_mark class="size-12" />

          <div class="space-y-2 text-center">
            <h3 class="text-lg/tight font-medium">Brak rekomendacji</h3>
            <p class="max-w-96 text-balance">
              Firmowid nie znalazl zadnych transakcji, ktore potencjalnie pasowałyby do tej faktury.
            </p>
          </div>

          <.button
            phx-click="show_chat"
            phx-target="#invoice-show"
            class="mt-2"
            color={if(@is_cost_invoice, do: "orange", else: "turquoise")}
            size="small"
            new={true}
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
        <h3 :if={@not_found} class="leading-tight font-medium">Co jeszcze mozesz zrobic?</h3>
        <.skip_invoicing
          show_assistant={not @not_found}
          show_bank_transfer_modal={@is_cost_invoice}
          invoice={@invoice}
        />
      </div>
    </div>
    """
  end

  attr :potential_transactions, :list, required: true
  attr :name_field, :atom, required: true

  def potential_transactions_list(assigns) do
    potential_transactions = assigns.potential_transactions
    green_threshold = 0.69
    # Find the first index of the highest score >= green_threshold
    {green_idx, _} =
      potential_transactions
      |> Enum.with_index()
      |> Enum.filter(fn {{_tx, score}, _idx} -> score >= green_threshold end)
      |> Enum.sort_by(fn {{_tx, score}, _idx} -> -score end)
      |> Enum.split(1)
      |> then(fn {first, _rest} ->
        case first do
          [{{_tx, _score}, idx}] -> {idx, true}
          _ -> {-1, false}
        end
      end)

    assigns = assign(assigns, :green_idx, green_idx)

    ~H"""
    <div class="flex flex-col gap-16 @container">
      <div class="flex flex-col gap-4">
        <h2 class="text-lg/tight font-medium">Potencjalne transakcje dla dokumentu</h2>

        <div class="grid grid-cols-[1fr_repeat(3,min-content)] @3xl:grid-cols-[1fr_120px_120px_min-content] gap-y-4 gap-x-6 @2xl:gap-x-8">
          <div class="grid grid-cols-subgrid col-span-full text-sm/snug text-grey-700">
            <span>Informacje</span>
            <span class="text-right">Data</span>
            <span class="text-right">Kwota</span>
          </div>

          <%= for {{tx, score}, idx} <- Enum.with_index(@potential_transactions) do %>
            <div
              id={"potential-transaction-#{tx.id}"}
              class="grid grid-cols-subgrid col-span-full items-center"
            >
              <div class="space-y-1">
                <p class="font-semibold text-truncate line-clamp-1">{Map.get(tx, @name_field)}</p>
                <p class="text-sm/snug text-grey-600 text-truncate line-clamp-2">
                  {tx.remittance_information_unstructured}
                </p>
              </div>
              <div class="text-right text-nowrap">{tx.booking_date}</div>
              <div class="text-right text-nowrap">
                {Money.new(tx.transaction_currency, tx.transaction_amount)}
              </div>
              <div class="flex items-center gap-2">
                <.prediction_score_indicator
                  transaction_id={tx.id}
                  prediction_score={score}
                  is_highest_green={@green_idx == idx}
                />

                <.button
                  phx-click="connect"
                  phx-value-transaction_id={tx.id}
                  color={if(@green_idx == idx, do: "grey", else: "light_grey")}
                  size="small"
                  new={true}
                >
                  Zatwierdź
                </.button>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  attr :id, :string, default: "invoice-preview-scaler"
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def scalable_invoice_preview(assigns) do
    ~H"""
    <div
      id={@id}
      class={classes(["origin-top-left w-full", @class])}
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
end
