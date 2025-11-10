defmodule FirmowidWeb.Components.Invoicing.InvoiceDetails do
  @moduledoc """
  Stateless function components used by both Cost and Sales invoice detail
  views. Extracted from the original (now deprecated) InvoiceDetails module
  to avoid duplication.
  """

  use FirmowidWeb, :html

  attr :is_cost_invoice, :boolean
  attr :issue_date, Date, required: true
  attr :party_display_name, :string, required: true
  attr :description, :string

  def invoice_header(assigns) do
    ~H"""
    <header class={[
      "flex flex-row py-8",
      @is_cost_invoice && "bg-orangeBg",
      !@is_cost_invoice && "bg-blueBg"
    ]}>
      <div class="flex items-center justify-center w-24">
        <.link navigate={~p"/?month=#{@issue_date |> Date.to_iso8601()}"}>
          <.icon name="hero-arrow-left-circle-solid" class="w-7 h-7" />
        </.link>
      </div>
      <div class="flex flex-col">
        <h1 class="text-2xl">{@party_display_name}</h1>
        <h2 class="text-darkGrey">{@description}</h2>
      </div>
    </header>
    """
  end

  attr :is_cost_invoice, :boolean
  attr :total_amount, :any, required: true

  def invoice_amount(assigns) do
    ~H"""
    <div class="flex flex-col gap-2 items-end justify-end">
      <label class="text-darkGrey" for="total-amount">Razem do zapłaty</label>
      <p
        id="total-amount"
        class={[
          "text-xl bg-greyButtonBg/[0.3] px-4 py-2 rounded",
          @is_cost_invoice && "text-orangeText",
          !@is_cost_invoice && "text-blueText"
        ]}
      >
        {@total_amount}
      </p>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :piece_id, :string, required: true

  def invoice_metadata_piece(assigns) do
    ~H"""
    <div class={["grid grid-cols-subgrid col-span-2", "rounded odd:bg-greyButtonBg/[0.3] px-1"]}>
      <label
        for={@piece_id}
        class={[@label not in ["Sprzedawca", "Kupujący"] && "self-center", "text-sm text-darkGrey"]}
      >
        {@label}
      </label>
      <p id={@piece_id} class={["text-left", @label in ["Sprzedawca", "Kupujący"] && "mb-8"]}>
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
      class="flex flex-col justify-center items-start gap-1 pl-[4px] w-7 h-7 rounded-md bg-greenBg"
    >
      <div class="w-[75%] rounded-md h-[2px] bg-greenText" />
      <div class="w-[55%] rounded-md h-[2px] bg-greenText" />
      <div class="w-[35%] rounded-md h-[2px] bg-greenText" />
    </div>
    """
  end

  def prediction_score_indicator(%{predicition_level: :mid} = assigns) do
    ~H"""
    <div
      id={"match-prediction-score-#{@transaction_id}"}
      phx-hook="Tippy"
      data-tippy-content={"Ocena AI: #{Float.round(100 *@prediction_score, 2)}% pewności"}
      class="flex flex-col justify-center items-start gap-1 pl-[4px] w-7 h-7 rounded-md bg-orangeBg"
    >
      <div class="w-[75%] rounded-md h-[2px] bg-white" />
      <div class="w-[55%] rounded-md h-[2px] bg-orangeText" />
      <div class="w-[35%] rounded-md h-[2px] bg-orangeText" />
    </div>
    """
  end

  def prediction_score_indicator(%{predicition_level: :low} = assigns) do
    ~H"""
    <div
      id={"match-prediction-score-#{@transaction_id}"}
      phx-hook="Tippy"
      data-tippy-content={"Ocena AI: #{Float.round(100 *@prediction_score, 2)}% pewności"}
      class="flex flex-col justify-center items-start gap-1 pl-[4px] w-7 h-7 rounded-md bg-redBg"
    >
      <div class="w-[75%] rounded-md h-[2px] bg-white" />
      <div class="w-[55%] rounded-md h-[2px] bg-white" />
      <div class="w-[35%] rounded-md h-[2px] bg-redText" />
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
  attr :transaction, :map, required: true

  def single_transaction_match(assigns) do
    ~H"""
    <div class="flex flex-col gap-8">
      <div class="flex flex-row justify-between items-center">
        <p class="uppercase w-auto">Dopasowanie</p>
        <div class="flex flex-row gap-2 items-center">
          <div class="text-xs h-6 w-24 shrink-0 flex flex-row items-center p-2 rounded-md gap-2 justify-between bg-greenBg text-greenText">
            <div class="text-xs uppercase">Komplet</div>
            <.icon name="hero-check-micro" class="w-4 h-4" />
          </div>
          <button
            class="h-6 text-darkGrey rounded-md p-2 bg-greyButtonBg shrink-0 flex flex-row justify-between items-center gap-2 hover:border-darkGrey border border-transparent transition-all transition-duration-300"
            phx-click="disconnect"
          >
            <.icon name="hero-arrow-uturn-left-micro" class="h-4 w-4" />
          </button>
        </div>
      </div>
      <div class="grid grid-flow-col grid-cols-[2fr_1fr_1fr] grid-rows-2 gap-4 p-4 rounded bg-greenBg/[0.3]">
        <%= for {label, val} <- [
            {"Kontrahent", if(@is_cost_invoice, do: @transaction.creditor_name, else: @transaction.debtor_name)},
            {"Informacje", @transaction.remittance_information_unstructured},
            {"Zaksięgowano", @transaction.booking_date},
            {"Przewalutowano", @transaction.value_date},
            {"Kwota", Money.new(@transaction.transaction_amount, @transaction.transaction_currency)}
          ] do %>
          <div class={["flex flex-col gap-2", label == "Kwota" && "row-span-2 justify-end items-end"]}>
            <p class="text-sm text-darkGrey">{label}</p>
            <p class={[label == "Kwota" && "text-xl"]}>{val}</p>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  attr :is_cost_invoice, :boolean, required: true
  attr :transactions, :list, required: true

  def multiple_transactions_match(assigns) do
    [head | tail] = assigns.transactions
    transaction_count = length(tail) + 1

    merged_tx =
      Map.merge(head, %{
        creditor_name: "#{transaction_count} transakcji od #{head.creditor_name}",
        debtor_name: "#{transaction_count} transakcji od #{head.debtor_name}",
        transaction_amount: Enum.reduce(tail, head.transaction_amount, &Decimal.add(&1.transaction_amount, &2))
      })

    assigns = assign(assigns, :transaction, merged_tx)
    single_transaction_match(assigns)
  end

  def invoice_skipped_view(assigns) do
    ~H"""
    <div class="flex flex-col gap-8">
      <div class="flex flex-row justify-between items-center">
        <p class="uppercase">Transakcja pominięta</p>
        <div class="flex flex-row gap-2 w-32 overflow-hidden">
          <div class="text-xs h-8 flex flex-row justify-center items-center py-2 px-2 rounded-md transition-all duration-500 w-20 bg-greenBg text-greenText">
            <.icon name="hero-document-text-solid" class="h-4 w-4" />
          </div>
          <button
            phx-click="toggle-invoicing"
            class="w-20 h-8 uppercase text-xs text-darkGrey bg-greyButtonBg rounded-md"
          >
            <.icon name="hero-arrow-uturn-left-micro" class="h-4 w-4" />
          </button>
        </div>
      </div>
      <div class="grid grid-flow-col grid-cols-[2fr_1fr_1fr] gap-4 p-4 rounded bg-greyButtonBg/[0.3]">
        <div class="flex flex-col gap-2">
          <p class="text-sm text-darkGrey">Informacja</p>
          <p>Transakcja została pominięta dla dokumentu</p>
        </div>
      </div>
    </div>
    """
  end

  attr :invoice, :map, required: true
  attr :show_bank_transfer_modal, :boolean, default: true
  attr :hide_ask_assistant, :boolean, default: false

  def skip_invoicing(assigns) do
    ~H"""
    <div class="text-darkGrey flex flex-col gap-8">
      <div :if={not @hide_ask_assistant} class="flex flex-row justify-between gap-16">
        <p>Poproś Firmowida o pomoc w znalezieniu transakcji.</p>
        <button
          phx-click="show_chat"
          phx-target="#invoice-show"
          class="cursor-pointer w-32 h-8 uppercase text-xs bg-orangeText rounded-md text-white max-w-full"
        >
          Zapytaj
        </button>
      </div>
      <%= if @show_bank_transfer_modal do %>
        <div class="flex flex-row justify-between gap-16">
          <p>
            Wykonaj przelew teraz - kliknij przycisk, aby skopiować potrzebne dane.
          </p>
          <.live_component
            id="bank-transfer-modal"
            module={FirmowidWeb.Components.Invoicing.BankTransferModal}
            invoice={@invoice}
          />
        </div>
      <% end %>
      <div class="flex flex-row justify-between gap-16">
        <p>
          A może żadna transakcja nie pasuje, bo zapłacono gotówką, lub na inne konto?
          Pomiń jej szukanie. Firmowid oznaczy ją jako rozliczoną poza systemem.
        </p>
        <div class="flex shrink-0 flex-row gap-2 w-32 overflow-hidden">
          <div class="text-xs h-8 flex flex-row justify-center items-center py-2 px-2 rounded-md transition-all duration-500 w-10 text-darkGrey bg-greyButtonBg">
            <.icon name="hero-document-text-solid" class="h-4 w-4" />
          </div>
          <button
            phx-click="toggle-invoicing"
            class="transition-all duration-500 cursor-pointer w-20 h-8 uppercase text-xs text-darkGrey bg-greyButtonBg rounded-md"
          >
            Pomiń
          </button>
        </div>
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
    <div class="flex flex-col gap-16">
      <div class="flex flex-col gap-5">
        <div class="flex flex-row justify-between items-center">
          <h2 class="text-lg font-semibold">Potencjalne transakcje dla dokumentu</h2>
        </div>
        <div class="grid grid-cols-[1fr_120px_120px_220px]">
          <span class="text-xs uppercase text-darkGrey text-left">Informacje</span>
          <span class="text-xs uppercase text-darkGrey text-right">Data</span>
          <span class="text-xs uppercase text-darkGrey text-right">Kwota</span>
        </div>
        <%= for {{tx, score}, idx} <- Enum.with_index(@potential_transactions) do %>
          <div id={"potential-transaction-#{tx.id}"} class="grid grid-cols-[1fr_120px_120px_220px]">
            <div class="text-left">
              <p class="font-semibold">{Map.get(tx, @name_field)}</p>
              <p class="text-sm text-darkGrey">
                {tx.remittance_information_unstructured}
              </p>
            </div>
            <div class="flex items-center justify-end">{tx.booking_date}</div>
            <div class="text-right flex items-center justify-end">
              {Money.new(tx.transaction_currency, tx.transaction_amount)}
            </div>
            <div class="flex items-center justify-end gap-4">
              <.prediction_score_indicator
                transaction_id={tx.id}
                prediction_score={score}
                is_highest_green={@green_idx == idx}
              />
              <button
                phx-click="connect"
                phx-value-transaction_id={tx.id}
                class="uppercase text-sm bg-darkGrey text-white h-7 px-2 rounded"
              >
                Zatwierdź
              </button>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
