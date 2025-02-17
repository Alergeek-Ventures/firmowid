defmodule FirmowidWeb.Components.Invoicing.InvoiceDetails do
  alias Firmowid.SalesInvoices.SalesInvoice
  use FirmowidWeb, :live_component

  attr :invoice, :map, required: true
  attr :is_cost_invoice, :boolean
  attr :show_vat_for_sales_invoice, :boolean, default: true

  attr :preview_url, :string, required: true
  attr :preview_type, :atom, required: true

  attr :potential_transactions, :list, default: []
  attr :potential_groups, :list, default: []

  def render(assigns) do
    ~H"""
    <div class="flex flex-col">
      <.invoice_header
        is_cost_invoice={@is_cost_invoice}
        issue_date={@invoice.issue_date}
        party_display_name={@invoice.seller_display_name}
        description={@invoice.description}
      />
      <div class={[
        "grid grid-cols-[1fr] xl:grid-cols-[1fr,4fr]",
        "px-8 xl:px-24 py-8 gap-24 xl:gap-10"
      ]}>
        <aside class="min-w-[320px] max-w-none xl:max-w-[450px] flex flex-col gap-4 order-last xl:order-none">
          <.invoice_details
            is_cost_invoice={@is_cost_invoice}
            invoice_id={@invoice.id}
            invoice_identifier={@invoice.invoice_identifier}
            party_full_name={@invoice.seller}
            issue_date={@invoice.issue_date}
            sale_date={@invoice.sale_date}
            due_date={@invoice.issue_date}
          />

          <.invoice_amount
            is_cost_invoice={@is_cost_invoice}
            total_amount={Money.new(@invoice.currency, @invoice.total_amount)}
          />

          <div class="my-8">
            <.invoice_preview
              sales_invoice={@invoice}
              preview_url={@preview_url}
              preview_type={@preview_type}
              show_vat={@show_vat_for_sales_invoice}
            />
          </div>
        </aside>
        <main>
          <.invoice_action_view
            is_cost_invoice={@is_cost_invoice}
            invoice={@invoice}
            potential_transactions={@potential_transactions}
            potential_groups={@potential_groups}
          />
        </main>
      </div>
    </div>
    """
  end

  attr :is_cost_invoice, :boolean
  attr :issue_date, Date, required: true
  attr :party_display_name, :string, required: true
  attr :description, :string

  defp invoice_header(assigns) do
    ~H"""
    <header class={[
      "flex flex-row py-8",
      @is_cost_invoice && "bg-orangeBg",
      !@is_cost_invoice && "bg-blueBg"
    ]}>
      <div class="flex items-center justify-center w-24">
        <.link navigate={~p"/?month=#{@issue_date |> Date.to_iso8601()}"}>
          <.icon name="hero-arrow-left-circle-solid" class="w-6 h-6" />
        </.link>
      </div>
      <div class="flex flex-col">
        <h1 class="text-2xl">
          {@party_display_name}
        </h1>
        <h2 class="text-darkGrey">
          {@description}
        </h2>
      </div>
    </header>
    """
  end

  attr :is_cost_invoice, :boolean
  attr :invoice_id, :string
  attr :invoice_identifier, :string, required: true
  attr :party_full_name, :string, required: true
  attr :issue_date, Date, required: true
  attr :sale_date, Date, required: true
  attr :due_date, Date, required: true

  defp invoice_details(assigns) do
    ~H"""
    <div class="flex flex-row w-full justify-between">
      <h3 class="text-md uppercase text-darkGrey">Dane faktury</h3>
      <div class="flex flex-row gap-4">
        <%= if @is_cost_invoice do %>
          <button class="cursor-not-allowed">
            <.icon name="hero-pencil-square-solid" class="w-4 h-4" />
          </button>
        <% else %>
          <.link navigate={~p"/sprzedazowe/#{@invoice_id}/edycja"}>
            <.icon name="hero-pencil-square-solid" class="w-4 h-4" />
          </.link>
        <% end %>
        <button phx-click="delete">
          <.icon name="hero-trash-solid" class="w-4 h-4" />
        </button>
      </div>
    </div>
    <div class="flex flex-col gap-4 py-8">
      <.invoice_metadata_piece
        label="Numer faktury"
        value={@invoice_identifier}
        piece_id="invoice-identifier"
      />
      <.invoice_metadata_piece
        label={
          if @is_cost_invoice,
            do: "Sprzedawca",
            else: "Kupujący"
        }
        value={@party_full_name}
        piece_id="party"
      />
      <.invoice_metadata_piece label="Data wystawienia" value={@issue_date} piece_id="issue-date" />
      <.invoice_metadata_piece label="Data sprzedaży" value={@sale_date} piece_id="sale-date" />
      <.invoice_metadata_piece label="Termin płatności" value={@due_date} piece_id="due-date" />
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :piece_id, :string, required: true

  defp invoice_metadata_piece(assigns) do
    ~H"""
    <div class="flex flex-row gap-2 items-end">
      <label class="text-darkGrey" for={@piece_id}>{@label}</label>
      <p id={@piece_id} class="font-bold">{@value}</p>
    </div>
    """
  end

  defp invoice_amount(assigns) do
    ~H"""
    <div class="flex flex-col gap-2 items-end justify-end">
      <label class="text-darkGrey" for="total-amount">Razem do zapłaty</label>
      <p
        id="total-amount"
        class={[
          "text-2xl",
          @is_cost_invoice && "text-orangeText",
          !@is_cost_invoice && "text-blueText"
        ]}
      >
        {@total_amount}
      </p>
    </div>
    """
  end

  attr :sales_invoice, SalesInvoice
  attr :preview_url, :string, required: true
  attr :preview_type, :atom, required: true
  attr :show_vat, :boolean, default: true

  defp invoice_preview(%{preview_type: :html} = assigns),
    do: ~H"""
    <div class={[
      "w-full h-full max-h-[80vh] border-black border-2",
      "rounded-lg overflow-hidden"
    ]}>
      <FirmowidWeb.PdfHTML.sales_invoice
        sales_invoice={@sales_invoice}
        currency_rate={
          if @sales_invoice.currency == "PLN",
            do: nil,
            else:
              @sales_invoice.currency
              |> Firmowid.Nbp.ApiClient.get_exchange_rate(
                SalesInvoice.get_currency_conversion_date(@sales_invoice)
              )
        }
        show_vat={@show_vat}
      />
    </div>
    """

  defp invoice_preview(%{preview_type: :pdf} = assigns) do
    ~H"""
    <div
      class="w-full h-full max-h-[80vh] border-black border-2 rounded-lg
      overflow-x-hidden overflow-y-scroll bg-white"
      id="invoice-preview"
      data-pdf-url={@preview_url}
      phx-hook="PDFViewer"
    >
      <div class="min-w-[200px] min-h-[200px] flex items-center justify-center font-bold">
        Ładowanie dokumentu...
      </div>
    </div>
    """
  end

  defp invoice_preview(%{preview_type: :image} = assigns) do
    ~H"""
    <div class="w-full h-full max-h-[80vh] border-black border-2 rounded-lg
    overflow-x-hidden overflow-y-scroll bg-black">
      <img src={@preview_url} class="w-full h-full object-contain" />
    </div>
    """
  end

  attr :is_cost_invoice, :boolean, required: true
  attr :invoice, :map, required: true
  attr :potential_transactions, :list, required: true
  attr :potential_groups, :list, required: true

  defp invoice_action_view(assigns) do
    cond do
      assigns.invoice.skip_invoicing ->
        ~H"""
        <.invoice_skipped_view />
        """

      assigns.invoice.transactions == [] ->
        ~H"""
        <.invoice_potential_transactions
          is_cost_invoice={@is_cost_invoice}
          potential_groups={@potential_groups}
          potential_transactions={@potential_transactions}
        />
        """

      true ->
        case assigns.invoice.transactions do
          [single] ->
            assigns =
              assigns
              |> assign(:single, single)

            ~H"<.single_transaction_match is_cost_invoice={@is_cost_invoice} transaction={@single} />"

          transactions ->
            assigns =
              assigns
              |> assign(:transactions, transactions)

            ~H"<.multiple_transactions_match is_cost_invoice={@is_cost_invoice} transactions={@transactions} />"
        end
    end
  end

  defp invoice_skipped_view(assigns) do
    ~H"""
    <div class="flex flex-col gap-8 items-center">
      <.icon name="hero-forward-solid" class="w-10 h-10" />
      <h3 class="text-lg font-semibold">Szukanie dopasowania pominięte</h3>
      <p class="max-w-[400px]">
        Oznacza to, że Firmowid nie będzie już szukać transakcji, która
        pasowałaby do tej faktury. Możesz to cofnąć w dowolnym momencie.
      </p>
      <button class="bg-darkGrey text-white rounded px-4 py-2" phx-click="toggle-invoicing">
        Cofnij <.icon name="hero-arrow-uturn-left-micro xl:inline-block hidden" class="w-4 h-4" />
      </button>
    </div>
    """
  end

  attr :is_cost_invoice, :boolean, required: true
  attr :transaction, :map, required: true

  defp single_transaction_match(assigns) do
    ~H"""
    <div class="flex flex-col gap-4 lg:pl-8">
      <div class="flex flex-row justify-between items-center">
        <p class="uppercase">
          Dopasowana transakcja
        </p>
        <button class="bg-darkGrey text-white rounded px-2 py-1" phx-click="disconnect">
          Cofnij <.icon name="hero-arrow-uturn-left-micro xl:inline-block hidden" class="w-4 h-4" />
        </button>
      </div>
      <p class="text-sm text-darkGrey">
        Kontrahent
      </p>
      <div>
        <p>
          {if @is_cost_invoice do
            @transaction.creditor_name
          else
            @transaction.debtor_name
          end}
        </p>
      </div>
      <p class="text-sm text-darkGrey">
        Informacje
      </p>
      <p>{@transaction.remittance_information_unstructured}</p>
      <p class="text-sm text-darkGrey">
        Zaksięgowano
      </p>
      <p>{@transaction.booking_date}</p>
      <p class="text-sm text-darkGrey">
        Kwota
      </p>
      <p>
        {Money.new(@transaction.transaction_amount, @transaction.transaction_currency)}
      </p>
    </div>
    """
  end

  attr :is_cost_invoice, :boolean, required: true
  attr :transactions, :list, required: true

  defp multiple_transactions_match(assigns) do
    [head | tail] = assigns.transactions

    assigns =
      assigns
      |> assign(:head, head)
      |> assign(:tail, tail)
      |> assign(:transaction_count, length(tail) + 1)

    ~H"""
    <.single_transaction_match
      is_cost_invoice={@is_cost_invoice}
      transaction={
        Map.merge(@head, %{
          creditor_name: "#{@transaction_count} transakcji od #{@head.creditor_name}",
          debtor_name: "#{@transaction_count} transakcji od #{@head.debtor_name}",
          transaction_amount:
            Enum.reduce(@tail, @head.transaction_amount, &Decimal.add(&1.transaction_amount, &2))
        })
      }
    />
    """
  end

  attr :potential_transactions, :list, required: true
  attr :potential_groups, :list, required: true
  attr :is_cost_invoice, :boolean, required: true

  defp invoice_potential_transactions(%{potential_transactions: []} = assigns) do
    ~H"""
    <div class="flex flex-col gap-6 items-center text-center">
      <div>
        <.icon name="hero-face-frown" class="w-10 h-10" />
      </div>

      <h3 class="text-lg font-semibold">Brak transakcji</h3>

      <p class="max-w-[400px]">
        Firmowid nie znalazł żadnych transakcji, które potencjalnie pasowałyby do tej faktury. Może takie dopiero w przyszłości pojawią się na koncie?
      </p>

      <p class="max-w-[400px] text-darkGrey">
        A może żadna nie pasuje, bo zapłacono gotówką, lub na inne konto?
        W takim razie
        <button class="font-bold underline" phx-click="toggle-invoicing">pomiń szukanie</button>
        i daj znać Firmowidowi, by oznaczył ją jako rozliczoną poza systemem.
      </p>
    </div>
    """
  end

  defp invoice_potential_transactions(assigns) do
    ~H"""
    <div class="flex flex-col gap-16">
      <.invoice_potential_groups
        is_cost_invoice={@is_cost_invoice}
        potential_groups={@potential_groups}
      />

      <div class="flex flex-col gap-5">
        <h2 class="text-lg font-semibold">
          {if @potential_groups == [],
            do: "Potencjalne transakcje dla dokumentu",
            else: "Inne pasujące transakcje"}
        </h2>

        <div class="grid grid-cols-[1fr_150px_200px_220px]">
          <%= for label <- ["Informacje", "Data", "Kwota"] do %>
            <span class={[
              "text-xs uppercase text-darkGrey text-right",
              label == "Informacje" && "!text-left"
            ]}>
              {label}
            </span>
          <% end %>
        </div>

        <div
          :for={transaction <- @potential_transactions}
          id={"potential-transaction-#{transaction.id}"}
          class="grid grid-cols-[1fr_150px_200px_220px]"
        >
          <div class="text-left">
            <p class="font-semibold">
              {if @is_cost_invoice do
                transaction.creditor_name
              else
                transaction.debtor_name
              end}
            </p>
            <p class="text-sm text-darkGrey">
              {transaction.remittance_information_unstructured}
            </p>
          </div>
          <div class="flex items-center justify-end">
            {transaction.booking_date}
          </div>
          <div class="text-right flex items-center justify-end">
            {Money.new(transaction.transaction_currency, transaction.transaction_amount)}
          </div>
          <div class="flex items-center justify-end gap-4">
            <.llm_grade_indicator transaction_id={transaction.id} llm_eval={transaction.llm_eval} />
            <button
              phx-value-transaction_id={transaction.id}
              phx-click="connect"
              class="uppercase text-sm bg-darkGrey text-white h-7 px-2 rounded"
            >
              Zatwierdź
            </button>
          </div>
        </div>
      </div>

      <.skip_invoicing />
    </div>
    """
  end

  defp invoice_potential_groups(%{potential_groups: []} = assigns) do
    ~H"""
    """
  end

  defp invoice_potential_groups(assigns) do
    ~H"""
    <div
      :for={
        %{
          id: id,
          total_amount: total_amount,
          currency: currency,
          transactions: transactions
        } <- @potential_groups
      }
      class="flex flex-col gap-4"
    >
      <h3 class="text-lg font-semibold">Znaleziono dopasowanie do grupy</h3>

      <p class="text-sm text-darkGrey">
        Po zsumowaniu wartości transakcji z grupy (o podobnej nazwie
        kontrahenta), pojawiło się dopasowanie. To częsty przypadek, gdy
        kontrahent wystawia jedną zbiorczą fakturę po wielu transakcjach, np.: w
        jednym miesiącu rozliczeniowym.
      </p>

      <div class="flex flex-row items-center justify-between">
        <p class="text-right">
          Suma grupy:
          <span class="font-bold text-lg">
            {Money.new(
              currency,
              total_amount
            )}
          </span>
        </p>

        <button
          phx-click="connect-group"
          phx-value-group-id={id}
          class={[
            "min-w-[300px] uppercase px-4 py-2 rounded",
            "bg-greenBg text-darkGrey"
          ]}
        >
          Zatwierdź grupę <.icon name="hero-rectangle-group-solid" class="w-4 h-4" />
        </button>
      </div>
      <div class="grid grid-cols-[1fr_150px_200px]">
        <%= for label <- ["Informacje", "Data", "Kwota"] do %>
          <span class={[
            "text-xs uppercase text-darkGrey text-right",
            label == "Informacje" && "!text-left"
          ]}>
            {label}
          </span>
        <% end %>
      </div>

      <div class="flex flex-col gap-1">
        <div
          :for={transaction <- transactions}
          id={"group-potential-transaction-#{transaction.id}"}
          class="grid grid-cols-[1fr_150px_200px]"
        >
          <div class="text-left">
            <p class="font-semibold">
              {if @is_cost_invoice do
                transaction.creditor_name
              else
                transaction.debtor_name
              end}
            </p>
          </div>
          <div class="flex items-center justify-end">
            {transaction.booking_date}
          </div>
          <div class="text-right flex items-center justify-end">
            {Money.new(transaction.transaction_currency, transaction.transaction_amount)}
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp skip_invoicing(assigns) do
    ~H"""
    <div class="text-darkGrey flex flex-col gap-2 py-4">
      <p>Żadna faktura nie pasuje, bo zapłacono gotówką, lub na inne konto?</p>
      <p>
        W takim razie
        <button class="font-bold underline" phx-click="toggle-invoicing">pomiń szukanie</button>
        i daj znać Firmowidowi, by oznaczył ją jako rozliczoną poza systemem.
      </p>
    </div>
    """
  end

  attr :transaction_id, :string, required: true
  attr :llm_eval, :float, required: true

  defp llm_grade_indicator(assigns) do
    ~H"""
    <div
      id={"match-llm-eval-#{@transaction_id}"}
      phx-hook="Tippy"
      data-tippy-content={"Wykorzystując AI, rekomendujemy transakcję
                    z Twojego konta, która pasuje do danej faktury kosztowej. Ocena
                    jest #{
                    cond do
                      @llm_eval >= 0.75 -> "wysoka"
                      @llm_eval >= 0.5 -> "średnia"
                      true -> "niska"
                    end} dla tej transakcji."}
      class={[
        "flex flex-col justify-center items-start gap-1 pl-[4px]",
        "w-7 h-7 rounded-md",
        @llm_eval >= 0.75 && "bg-greenBg",
        (@llm_eval >= 0.5 and
           @llm_eval < 0.75) &&
          "bg-orangeBg",
        @llm_eval < 0.5 && "bg-redBg"
      ]}
    >
      <div class={[
        "w-[75%] rounded-md bg-white h-[2px]",
        @llm_eval >= 0.75 && "!bg-greenText"
      ]} />
      <div class={[
        "w-[55%] rounded-md bg-white h-[2px]",
        @llm_eval >= 0.75 && "!bg-greenText",
        (@llm_eval >= 0.5 and
           @llm_eval < 0.75) &&
          "!bg-orangeText"
      ]} />
      <div class={[
        "w-[35%] rounded-md bg-white h-[2px]",
        @llm_eval >= 0.75 &&
          "!bg-greenText",
        (@llm_eval >= 0.5 and
           @llm_eval < 0.75) &&
          "!bg-orangeText",
        @llm_eval < 0.5 && "!bg-redText"
      ]} />
    </div>
    """
  end
end
