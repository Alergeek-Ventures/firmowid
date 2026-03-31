defmodule FirmowidWeb.Invoicing.Components.InvoiceDetails do
  @moduledoc """
  Stateless function components for invoice detail views.

  Contains shared components (headers, transaction matches, skip invoicing)
  used by both Cost and Sales invoice details, as well as sales-specific
  components like `sales_invoice_metadata/1`.
  """

  use FirmowidWeb, :html

  alias Firmowid.Ash.Invoicing.SalesInvoice

  attr :is_cost_invoice, :boolean
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
      <.link navigate={@return_to || ~p"/fakturowanie?month=#{@issue_date |> Date.to_iso8601()}"}>
        <.icon name="hero-arrow-left-circle-solid" class="size-7" />
      </.link>
      <div class="flex flex-col gap-2">
        <h1 class="text-lg/tight font-medium lg:text-2xl">{@party_display_name}</h1>
        <h2 class="text-darkGrey">{@description}</h2>
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
    <main class="border-grey-100 mt-8 w-full border-b-2 px-8 pb-8 lg:border-b-0 lg:border-l-2">
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
      <h3 class="leading/snug text-grey-700 ml-1 self-start text-sm">Podgląd faktury</h3>
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
    <div class="border-grey-200 transition-duration-300 w-full overflow-hidden rounded border-2 transition-opacity hover:opacity-50">
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :label, :string, required: true
  slot :inner_block, required: false

  defp invoice_subpreview(assigns) do
    ~H"""
    <div class="flex w-full min-w-0 flex-col gap-2">
      <p class="text-grey-700 ml-1 text-sm/tight font-medium">
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
    <div class="flex flex-row items-start justify-between gap-2 pl-1">
      <label class="text-grey-700 text-sm/snug" for="total-amount">
        {if @lang == :en, do: "Total to pay", else: "Razem do zapłaty"}
      </label>
      <p
        id="total-amount"
        class={[
          "rounded bg-[#DEDEDE4C] px-4 py-2 text-lg/tight",
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
          value={SalesInvoice.buyer_display_name(@invoice)}
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
    <div class="odd:bg-greyButtonBg/[0.3] col-span-2 grid grid-cols-subgrid rounded px-1 py-0.5">
      <label
        for={@piece_id}
        class={[
          "text-darkGrey text-sm/snug text-nowrap",
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
      class="flex size-8 shrink-0 flex-col justify-between rounded-md bg-green-200 p-2"
    >
      <div class="h-0.5 w-full rounded-md bg-green-700" />
      <div class="h-0.5 w-[70%] rounded-md bg-green-700" />
      <div class="h-0.5 w-[40%] rounded-md bg-green-700" />
    </div>
    """
  end

  def prediction_score_indicator(%{predicition_level: :mid} = assigns) do
    ~H"""
    <div
      id={"match-prediction-score-#{@transaction_id}"}
      phx-hook="Tippy"
      data-tippy-content={"Ocena AI: #{Float.round(100 *@prediction_score, 2)}% pewności"}
      class="flex size-8 shrink-0 flex-col justify-between rounded-md bg-orange-200 p-2"
    >
      <div class="h-0.5 w-full rounded-md bg-white" />
      <div class="h-0.5 w-[70%] rounded-md bg-orange-700" />
      <div class="h-0.5 w-[40%] rounded-md bg-orange-700" />
    </div>
    """
  end

  def prediction_score_indicator(%{predicition_level: :low} = assigns) do
    ~H"""
    <div
      id={"match-prediction-score-#{@transaction_id}"}
      phx-hook="Tippy"
      data-tippy-content={"Ocena AI: #{Float.round(100 *@prediction_score, 2)}% pewności"}
      class="flex size-8 shrink-0 flex-col justify-between rounded-md bg-red-200 p-2"
    >
      <div class="h-0.5 w-full rounded-md bg-white" />
      <div class="h-0.5 w-[70%] rounded-md bg-white" />
      <div class="h-0.5 w-[40%] rounded-md bg-red-700" />
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
      <div class="flex flex-row items-center justify-between">
        <p class="text-lg/tight font-medium">Dopasowanie</p>

        <div class="flex flex-row gap-2">
          <div class="flex flex-row items-center self-stretch rounded-md bg-green-200 px-[14.5px]">
            <p class="text-sm/tight font-medium text-green-700">Komplet</p>
          </div>
          <.button
            color="light_grey"
            size="small"
            new={true}
            phx-click="disconnect"
          >
            <.icon name="hero-arrow-uturn-left-micro" class="size-4" />
          </.button>
        </div>
      </div>

      <div
        :for={transaction <- @transactions}
        class="grid grid-flow-col grid-cols-[2fr_1fr_1fr] grid-rows-2 gap-x-4 gap-y-6 rounded-md bg-[#D0E6CE66] p-4"
      >
        <%= for {label, val} <- [
            {"Kontrahent", if(@is_cost_invoice, do: transaction.creditor_name, else: transaction.debtor_name)},
            {"Wierzyciel", if(not @is_cost_invoice, do: transaction.creditor_name, else: transaction.debtor_name)},
            {"Zaksięgowano", transaction.booking_date},
            transaction.value_date && {"Przewalutowano", transaction.value_date},
          ] do %>
          <div class="space-y-1">
            <p class="text-grey-700 text-sm/snug">{label}</p>
            <p class="leading-snug">{val}</p>
          </div>
        <% end %>

        <div class="row-span-2 flex items-end justify-end text-right">
          <p class={["leading-snug text-green-700", @single_transaction? && "text-lg"]}>
            {Money.new(transaction.transaction_amount, transaction.transaction_currency)}
          </p>
        </div>
      </div>

      <div
        :if={not @single_transaction?}
        class="flex flex-row items-center justify-between rounded-md bg-[#D0E6CE66] p-4"
      >
        <p class="text-grey-700 text-sm">Suma</p>

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
      <div class="flex flex-row items-center justify-between">
        <p class="text-lg/tight font-medium">Transakcja pominięta</p>
        <div class="flex w-32 flex-row gap-2">
          <div class="flex h-8 flex-1 items-center justify-center rounded-md bg-green-200 p-2 text-green-700">
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
      <div class="bg-grey-100 flex flex-col gap-6 rounded p-6">
        <p class="text-base/snug">Transakcja została pominięta dla dokumentu</p>
        <div :if={false} class="space-y-2">
          <label class="text-grey-700 text-sm/snug" for="temp">Powód pominięcia</label>

          <div class="flex flex-row items-center gap-2">
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
    <div class="grid grid-cols-[1fr_8rem] gap-6 lg:gap-x-10">
      <%= if @show_bank_transfer_modal do %>
        <div class="col-span-full grid grid-cols-subgrid">
          <p class="text-grey-700 text-sm/snug text-balance">
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
        <p class="text-grey-700 self-center text-sm/snug text-balance">
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

      <div class="col-span-full grid grid-cols-subgrid">
        <p class="text-grey-700 text-sm/snug text-balance">
          A może żadna transakcja nie pasuje, bo zapłacono gotówką, lub na inne konto?
          Pomiń jej szukanie. Firmowid oznaczy ją jako rozliczoną poza systemem.
        </p>
        <div class="flex w-full flex-row items-start gap-2">
          <div class="bg-grey-200 text-grey-700 flex items-center justify-center rounded-md p-2">
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
        <div class="flex flex-col items-center gap-4 px-4 pt-8 pb-6">
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
    <div class="@container flex flex-col gap-16">
      <div class="flex flex-col gap-4">
        <h2 class="text-lg/tight font-medium">Potencjalne transakcje dla dokumentu</h2>

        <div class="grid grid-cols-[1fr_repeat(3,min-content)] gap-x-6 gap-y-4 @2xl:gap-x-8 @3xl:grid-cols-[1fr_120px_120px_min-content]">
          <div class="text-grey-700 col-span-full grid grid-cols-subgrid text-sm/snug">
            <span>Informacje</span>
            <span class="text-right">Data</span>
            <span class="text-right">Kwota</span>
          </div>

          <%= for {{tx, score}, idx} <- Enum.with_index(@potential_transactions) do %>
            <div
              id={"potential-transaction-#{tx.id}"}
              class="col-span-full grid grid-cols-subgrid items-center"
            >
              <div class="space-y-1">
                <p class="text-truncate line-clamp-1 font-semibold">{Map.get(tx, @name_field)}</p>
                <p class="text-grey-600 text-truncate line-clamp-2 text-sm/snug">
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
end
