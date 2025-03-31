defmodule FirmowidWeb.Components.Invoicing.InvoiceDetails do
  alias Firmowid.SalesInvoices.SalesInvoice
  use FirmowidWeb, :live_component

  attr :invoice, :map, required: true
  attr :is_cost_invoice, :boolean
  attr :show_vat_for_sales_invoice, :boolean, default: true

  attr :preview_url, :string, required: true
  attr :preview_type, :atom, required: true

  attr :potential_transactions, :list, default: []
  attr :did_suggest_combo, :boolean, required: true

  attr :is_freeform_matching, :boolean, required: true
  attr :search_term, :string, required: true
  attr :search_results, :list, required: true
  attr :selected_transaction_ids, :list, required: true

  def render(assigns) do
    ~H"""
    <div class="flex flex-col">
      <.invoice_header
        is_cost_invoice={@is_cost_invoice}
        issue_date={@invoice.issue_date}
        party_display_name={
          if @is_cost_invoice do
            @invoice.seller_display_name
          else
            @invoice.buyer_display_name
          end
        }
        description={@invoice.description}
      />
      <div class={[
        "flex flex-col justify-between",
        "px-8 gap-4 lg:gap-12 lg:flex-row"
      ]}>
        <aside class={[
          "min-w-[320px] max-w-none lg:w-[600px] flex flex-col",
          "gap-4 order-last lg:order-none py-8"
        ]}>
          <.invoice_details
            is_cost_invoice={@is_cost_invoice}
            invoice_id={@invoice.id}
            invoice_identifier={@invoice.invoice_identifier}
            party_full_name={
              if @is_cost_invoice do
                @invoice.seller
              else
                @invoice.buyer_display_name
              end
            }
            issue_date={@invoice.issue_date}
            sale_date={@invoice.sale_date}
            due_date={@invoice.due_date}
          />

          <.invoice_amount
            is_cost_invoice={@is_cost_invoice}
            total_amount={Money.new(@invoice.currency, @invoice.total_amount)}
          />

          <h3 class="self-start text-sm uppercase text-darkGrey mt-8">Podgląd faktury</h3>

          <div class="mb-8 mt-4 transition-opacity transition-duration-300 hover:opacity-50">
            <.invoice_preview
              sales_invoice={@invoice}
              preview_url={@preview_url}
              preview_type={@preview_type}
              show_vat={@show_vat_for_sales_invoice}
            />
          </div>
        </aside>
        <main class="flex-grow py-8 lg:pl-8 border-b lg:border-b-0 lg:border-l border-darkGrey/[.3]">
          <.invoice_action_view
            is_freeform_matching={@is_freeform_matching}
            search_term={@search_term}
            search_results={@search_results}
            selected_transaction_ids={@selected_transaction_ids}
            is_cost_invoice={@is_cost_invoice}
            invoice={@invoice}
            potential_transactions={@potential_transactions}
            did_suggest_combo={@did_suggest_combo}
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
          <.icon name="hero-arrow-left-circle-solid" class="w-7 h-7" />
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
    <div class="grid grid-cols-[150px_1fr] gap-2">
      <h3 class="self-center text-sm uppercase text-darkGrey">Dane faktury</h3>
      <div class="flex flex-row justify-end gap-2">
        <%= if not @is_cost_invoice do %>
          <.link
            id="copy-invoice-link"
            phx-hook="Tippy"
            data-tippy-content="Skopiuj fakturę"
            data-tippy-delay="1000"
            class={[
              "hover:text-white hover:bg-darkGrey text-darkGrey transition-all transition-duration-300",
              "px-2 py-1 flex items-center justify-center rounded"
            ]}
            navigate={~p"/sprzedazowe?skopiuj=#{@invoice_id}"}
          >
            <.icon name="hero-document-duplicate" class="w-5 h-5" />
          </.link>
          <.link
            id="edit-invoice-link"
            phx-hook="Tippy"
            data-tippy-content="Edytuj fakturę"
            data-tippy-delay="1000"
            class={[
              "hover:text-white hover:bg-darkGrey text-darkGrey transition-all transition-duration-300",
              "px-2 py-1 flex items-center justify-center rounded"
            ]}
            navigate={~p"/sprzedazowe/#{@invoice_id}/edycja"}
          >
            <.icon name="hero-pencil-square-solid" class="w-5 h-5" />
          </.link>
        <% end %>
        <button
          id="delete-invoice-button"
          phx-hook="Tippy"
          data-tippy-content="Usuń fakturę"
          data-tippy-delay="1000"
          class={[
            "hover:text-white hover:bg-darkGrey text-darkGrey transition-all transition-duration-300",
            "px-2 py-1 flex items-center justify-center rounded"
          ]}
          phx-click="delete"
        >
          <.icon name="hero-trash-solid" class="w-5 h-5" />
        </button>
      </div>
    </div>
    <div class="grid grid-cols-[130px_1fr] gap-2 py-4">
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
    <div class={[
      "grid grid-cols-subgrid col-span-2",
      "rounded odd:bg-greyButtonBg/[0.3] px-1"
    ]}>
      <label
        class={[
          (@label != "Sprzedawca" and @label != "Kupujący") && "self-center",
          "text-sm text-darkGrey"
        ]}
        for={@piece_id}
      >
        {@label}
      </label>
      <p
        id={@piece_id}
        class={["text-left", (@label == "Sprzedawca" or @label == "Kupujący") && "mb-8"]}
      >
        {@value}
      </p>
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
      <a href={~p"/sprzedazowe/#{@sales_invoice.id}/pobierz"} target="_blank">
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
      </a>
    </div>
    """

  defp invoice_preview(%{preview_type: :pdf} = assigns) do
    ~H"""
    <a href={@preview_url} target="_blank">
      <div
        class="w-full h-full max-h-[80vh] border-black border-2 rounded-lg
      overflow-x-hidden overflow-y-scroll bg-white"
        id="invoice-preview"
        data-pdf-url={@preview_url}
        phx-update="ignore"
        phx-hook="PDFViewer"
      >
        <div class="min-w-[200px] min-h-[200px] flex items-center justify-center font-bold">
          Ładowanie dokumentu...
        </div>
      </div>
    </a>
    """
  end

  defp invoice_preview(%{preview_type: :image} = assigns) do
    ~H"""
    <a href={@preview_url} target="_blank">
      <div class="w-full h-full max-h-[80vh] border-black border-2 rounded-lg
    overflow-x-hidden overflow-y-scroll bg-black">
        <img src={@preview_url} class="w-full h-full object-contain" />
      </div>
    </a>
    """
  end

  attr :is_cost_invoice, :boolean, required: true
  attr :invoice, :map, required: true
  attr :potential_transactions, :list, required: true
  attr :is_freeform_matching, :boolean, required: true
  attr :search_term, :string, required: true
  attr :search_results, :list, required: true
  attr :selected_transaction_ids, :list, required: true
  attr :did_suggest_combo, :boolean, required: true

  defp invoice_action_view(assigns) do
    cond do
      assigns.invoice.skip_invoicing ->
        ~H"""
        <.invoice_skipped_view />
        """

      assigns.invoice.transactions == [] ->
        ~H"""
        <.invoice_potential_transactions
          invoice={@invoice}
          is_cost_invoice={@is_cost_invoice}
          potential_transactions={@potential_transactions}
          is_freeform_matching={@is_freeform_matching}
          search_term={@search_term}
          search_results={@search_results}
          selected_transaction_ids={@selected_transaction_ids}
          did_suggest_combo={@did_suggest_combo}
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
    <div class="flex flex-col gap-8">
      <div class="flex flex-row justify-between items-center">
        <p class="uppercase">
          Transakcja pominięta
        </p>

        <div class="flex flex-row gap-2 w-32 overflow-hidden">
          <div class={[
            "text-xs h-6",
            "flex flex-row justify-center items-center py-2 px-2 rounded-md",
            "transition-all duration-500",
            "w-20 bg-greenBg text-greenText"
          ]}>
            <.icon name="hero-document-text-solid" class="h-4 w-4" />
          </div>
          <button
            phx-click="toggle-invoicing"
            class={[
              "w-20",
              "h-6 uppercase text-xs text-darkGrey bg-greyButtonBg rounded-md"
            ]}
          >
            <.icon name="hero-arrow-uturn-left-micro" class="h-4 w-4" />
          </button>
        </div>
      </div>

      <div class={[
        "grid grid-flow-col grid-cols-[2fr_1fr_1fr] gap-4",
        "p-4 rounded bg-greyButtonBg/[0.3]"
      ]}>
        <%= for {metadata_label, metadata_value} <- [{
          "Informacja", "Transakcja została pominięta dla dokumentu"
        }] do %>
          <div class={[
            "flex flex-col gap-2",
            metadata_label == "Kwota" && "row-span-2 justify-center items-center"
          ]}>
            <p class={[
              "text-sm text-darkGrey",
              metadata_label == "Kwota" && "hidden"
            ]}>
              {metadata_label}
            </p>
            <p class={[
              metadata_label == "Kwota" && "text-2xl"
            ]}>
              {metadata_value}
            </p>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  attr :is_cost_invoice, :boolean, required: true
  attr :transaction, :map, required: true

  defp single_transaction_match(assigns) do
    ~H"""
    <div class="flex flex-col gap-8">
      <div class="flex flex-row justify-between items-center">
        <p class="uppercase w-auto">
          Dopasowanie
        </p>

        <div class="flex flex-row gap-2 items-center">
          <div class={[
            "text-xs h-6 w-24",
            "shrink-0 flex flex-row justify-center items-center p-2 rounded-md gap-2",
            "justify-between bg-greenBg text-greenText"
          ]}>
            <div class="text-xs uppercase">Komplet</div>
            <.icon name="hero-check-micro" class="w-4 h-4" />
          </div>

          <button
            class={[
              "h-6 text-darkGrey rounded-md p-2",
              "bg-greyButtonBg",
              "shrink-0 flex flex-row justify-between items-center gap-2",
              "hover:border-darkGrey border border-transparent transition-all transition-duration-300"
            ]}
            phx-click="disconnect"
          >
            <.icon name="hero-arrow-uturn-left-micro" class="h-4 w-4" />
          </button>
        </div>
      </div>

      <div class={[
        "grid grid-flow-col grid-cols-[2fr_1fr_1fr] grid-rows-2 gap-4",
        "p-4 rounded bg-greenBg/[0.3]"
      ]}>
        <%= for {metadata_label, metadata_value} <- [{
        "Kontrahent", (if @is_cost_invoice do
        @transaction.creditor_name
        else
            @transaction.debtor_name
            end)}, {
        "Informacje", @transaction.remittance_information_unstructured
        }, {
        "Zaksięgowano", @transaction.booking_date
        }, {
        "Przewalutowano", @transaction.value_date
        }, {
        "Kwota", Money.new(@transaction.transaction_amount, @transaction.transaction_currency)
        }] do %>
          <div class={[
            "flex flex-col gap-2",
            metadata_label == "Kwota" && "row-span-2 justify-end items-end"
          ]}>
            <p class={[
              "text-sm text-darkGrey"
            ]}>
              {metadata_label}
            </p>
            <p class={[
              metadata_label == "Kwota" && "text-xl"
            ]}>
              {metadata_value}
            </p>
          </div>
        <% end %>
      </div>
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

  attr :invoice, :map, required: true
  attr :is_cost_invoice, :boolean, required: true
  attr :potential_transactions, :list, required: true
  attr :is_freeform_matching, :boolean, required: true
  attr :search_term, :string, required: true
  attr :search_results, :list, required: true
  attr :selected_transaction_ids, :list, required: true
  attr :did_suggest_combo, :boolean, required: true

  defp invoice_potential_transactions(%{is_freeform_matching: true} = assigns) do
    ~H"""
    <div class="flex flex-col gap-16">
      <form class="flex flex-col gap-5" phx-submit="connect-selected-transactions">
        <div class="flex flex-row justify-between items-center">
          <h2 class="text-lg font-semibold">
            Wybierz pasujące transakcje
          </h2>

          <button
            type="button"
            phx-click="toggle-freeform"
            class={[
              "flex flex-row justify-center items-center gap-2",
              "px-2 py-1 text-darkGrey"
            ]}
          >
            <.icon name="hero-chevron-left" class="w-4 h-4" /> Wróć do rekomendowanych
          </button>
        </div>

        <%= if @did_suggest_combo do %>
          <div class="flex flex-row items-center gap-4 p-4 bg-greenBg/[0.3] rounded max-w-[800px] text-darkGrey">
            <div class="flex flex-col gap-2 flex-grow">
              <p class="font-bold">
                Dobraliśmy zestaw transakcji, które wydają się pasować do tej faktury.
              </p>
              <p class="text-sm">
                Kryterium doboru to zgadzająca się suma, przedział dat oraz nazwa kontrahenta.
              </p>
            </div>

            <div>
              <.icon name="hero-square-3-stack-3d" class="w-8 h-8" />
            </div>

            <div>
              <.icon name="hero-arrows-right-left" class="w-8 h-8" />
            </div>

            <div>
              <.icon name="hero-document-text" class="w-8 h-8" />
            </div>
          </div>
        <% end %>

        <div class="flex flex-row justify-between items-center my-5">
          <div class="flex flex-row gap-2 items-center">
            <label class="bg-greyButtonBg px-2 py-1 rounded">
              <.icon name="hero-magnifying-glass" class="w-4 h-4" />
              <input
                id="search"
                class={[
                  "bg-transparent",
                  "border-none",
                  "rounded px-2 py-1"
                ]}
                phx-change="search"
                name="search-term"
                value={@search_term}
              />
            </label>
          </div>

          <button
            type="submit"
            disabled={@selected_transaction_ids == []}
            class={[
              @selected_transaction_ids != [] && "bg-darkGrey",
              @selected_transaction_ids == [] && "bg-greyButtonBg",
              "uppercase text-white rounded px-2 py-1",
              "transition-all transition-duration-300"
            ]}
          >
            Zatwierdź
          </button>
        </div>

        <label class="grid grid-cols-[1fr_120px_120px_50px]">
          <%= for label <- ["Informacje", "Data", "Kwota"] do %>
            <span class={[
              "text-xs uppercase text-darkGrey text-right",
              label == "Informacje" && "!text-left"
            ]}>
              {label}
            </span>
          <% end %>
        </label>

        <%= if @search_results == [] and @search_term == "" do %>
          <div>Wyszukaj transakcje wpisując słowa kluczowe w polu powyżej</div>
        <% end %>

        <%= if @search_results == [] and @search_term != "" do %>
          <div>Brak rezutatów - zmień wyszukiwaną frazę</div>
        <% end %>

        <div
          :for={transaction <- @search_results}
          id={"potential-transaction-#{transaction.id}"}
          class="grid grid-cols-[1fr_120px_120px_50px]"
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
            <input
              type="checkbox"
              id={"potential-transaction-#{transaction.id}-checkbox"}
              name={transaction.id}
              phx-click="transaction-toggled"
              phx-value-transaction_id={transaction.id}
              checked={Enum.find(@selected_transaction_ids, &(&1 == transaction.id)) != nil}
              class="w-7 h-7 border text-darkGrey border-darkGrey/[.5] rounded focus:ring-0"
            />
          </div>
        </div>
      </form>
    </div>
    """
  end

  defp invoice_potential_transactions(%{potential_transactions: []} = assigns) do
    ~H"""
    <div class="flex flex-col gap-6 items-center text-center">
      <div class="gap-4 flex flex-col items-center border border-greyButtonBg p-4 rounded-md">
        <.icon name="hero-face-frown" class="w-10 h-10 block" />

        <h3 class="text-lg font-semibold">Brak rekomendacji</h3>

        <p class="max-w-[400px]">
          Firmowid nie znalazł żadnych transakcji, które potencjalnie pasowałyby
          do tej faktury.
        </p>
      </div>
    </div>
    <h3 class="text-lg font-semibold my-10">Co możesz zrobić?</h3>
    <div class="text-darkGrey flex flex-col gap-8">
      <div class="flex flex-row justify-between gap-16">
        <%= if @is_cost_invoice do %>
          <p>
            Możesz wykonać przelew teraz - kliknij przycisk, aby skopiować
            potrzebne dane.
          </p>

          <.live_component
            id="bank-transfer-modal"
            module={FirmowidWeb.Components.Invoicing.BankTransferModal}
            invoice={@invoice}
          />
        <% end %>
      </div>

      <div class="flex flex-row justify-between gap-16">
        <p>Nie widzisz odpowiedniej transakcji? Dokument ma kilka
          transakcji?</p>

        <button
          type="button"
          phx-click="toggle-freeform"
          class={[
            "text-xs h-6 w-32 uppercase",
            "shrink-0 flex flex-row justify-center items-center py-2 px-2 rounded-md",
            "transition-all duration-500",
            "text-darkGrey bg-greyButtonBg",
            "max-w-[525px]"
          ]}
        >
          Pokaż wszystkie
        </button>
      </div>

      <div class="flex flex-row justify-between gap-16">
        <p>
          A może żadna nie pasuje, bo zapłacono gotówką, lub na inne konto?
          Pomiń jej szukanie. Firmowid oznaczy ją jako rozliczoną poza systemem.
        </p>
        <div class="flex shrink-0 flex-row gap-2 w-32 overflow-hidden">
          <div class={[
            "text-xs h-6",
            "flex flex-row justify-center items-center py-2 px-2 rounded-md",
            "transition-all duration-500",
            "w-10",
            "text-darkGrey bg-greyButtonBg"
          ]}>
            <.icon name="hero-document-text-solid" class="h-4 w-4" />
          </div>
          <button
            phx-click="toggle-invoicing"
            class={[
              "transition-all duration-500 cursor-pointer",
              "w-20",
              "h-6 uppercase text-xs text-darkGrey bg-greyButtonBg rounded-md"
            ]}
          >
            Pomiń
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp invoice_potential_transactions(assigns) do
    ~H"""
    <div class="flex flex-col gap-16">
      <div class="flex flex-col gap-5">
        <div class="flex flex-row justify-between items-center">
          <h2 class="text-lg font-semibold">
            Potencjalne transakcje dla dokumentu
          </h2>

          <button phx-click="toggle-freeform" class="px-2 py-1 text-darkGrey">
            Dopasuj dowolne transakcje
          </button>
        </div>

        <div class="grid grid-cols-[1fr_120px_120px_220px]">
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
          class="grid grid-cols-[1fr_120px_120px_220px]"
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
                      @llm_eval >= 0.65 -> "wysoka"
                      @llm_eval >= 0.3 -> "średnia"
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
