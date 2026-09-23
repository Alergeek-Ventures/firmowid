defmodule FirmowidWeb.Delegations.Components.Settlement do
  @moduledoc "Function components for the delegation settlement page."

  use FirmowidWeb, :html

  import FirmowidWeb.DesignSystem.Components.Button
  import FirmowidWeb.DesignSystem.Components.CoreComponents, except: [button: 1]
  import FirmowidWeb.DesignSystem.Components.Link
  import Phoenix.Component, except: [link: 1]

  alias FirmowidWeb.Delegations.Utilities.SettlementPresentation
  alias Phoenix.HTML.Form
  alias Phoenix.LiveView.Rendered

  @company_currency "PLN"

  @doc "Renders an expense category, its documents, and upload control."
  @spec expense_section(map()) :: Rendered.t()
  attr :title, :string, required: true
  slot :icon, required: true
  attr :expenses, :list, required: true
  attr :upload, :any, required: true
  attr :upload_form, Form, required: true
  attr :kind, :string, required: true
  attr :editable?, :boolean, required: true
  attr :sort_active?, :boolean, required: true
  attr :description_visible?, :map, default: %{}
  attr :expense_forms, :map, required: true
  attr :trip_forms, :map, required: true
  attr :timezone, :string, required: true
  attr :related_upload, :any, required: true
  attr :expense_currencies, :map, default: %{}

  def expense_section(assigns) do
    ~H"""
    <section class="mt-10">
      <header class="mb-3 flex items-center justify-between gap-4">
        <div class="flex items-center gap-3">
          <h2 class="flex items-center gap-2 font-normal">
            {render_slot(@icon)}{@title}
          </h2>
          <span class="bg-grey-200 h-5 w-px" aria-hidden="true" />
          <.button
            type="button"
            variant="unstyled"
            class="text-grey-700 text-sm font-medium hover:underline"
            phx-click={show_modal("#{@kind}-documents-modal")}
          >Jakie dokumenty załączyć?</.button>
        </div>
        <.button
          :if={@kind == "transport" && @editable?}
          type="button"
          variant="ghost"
          size="small"
          disabled={
            @expenses == [] or
              (length(@expenses) > 0 and Enum.any?(@expenses, &(length(&1.trips || []) > 1)))
          }
          phx-click="sort"
        >Sortuj chronologicznie <Lucideicons.arrow_down_up class="size-4" /></.button>
      </header>
      <div class="space-y-3">
        <div
          :if={!@editable? && @expenses == []}
          id={"#{@kind}-empty-state"}
          class="text-grey-500 px-4 py-5 text-sm"
        >
          Nie dodano żadnych wydatków w tej kategorii.
        </div>
        <article
          :for={expense <- @expenses}
          class={["border-grey-200 rounded-lg border p-4", !@editable? && "bg-white"]}
        >
          <% forms = Map.fetch!(@expense_forms, expense.id) %>
          <div class="text-grey-500 flex items-center justify-between gap-3 text-sm">
            <.link
              :if={expense.blob}
              kind="unstyled"
              external={expense.blob.url}
              target="_blank"
              rel="noopener noreferrer"
              class="flex min-w-0 items-center gap-2 truncate hover:underline"
            ><.icon name="hero-document" class="size-5 shrink-0" />{expense.original_filename}</.link>
            <span :if={!expense.blob} class="flex min-w-0 items-center gap-2 truncate"><.icon
              name="hero-document"
              class="size-5 shrink-0"
            />{expense.original_filename}</span>
            <.link
              :if={!@editable? && expense.blob}
              kind="button"
              external={expense.blob.url}
              variant="secondary"
              size="small"
              download={expense.original_filename}
              class="shrink-0"
            >
              <Lucideicons.download class="size-4" /> Pobierz
            </.link>
            <.dropdown :if={@editable?} id={"expense-menu-#{expense.id}"}>
              <:trigger>
                <span
                  class="hover:bg-grey-100 text-grey-500 inline-flex size-8 cursor-pointer items-center justify-center rounded"
                  aria-label="Opcje pozycji"
                >
                  <Lucideicons.ellipsis_vertical class="size-4" />
                </span>
              </:trigger>
              <div class="border-grey-200 flex min-w-64 flex-col items-stretch rounded-lg border bg-white p-1 text-left shadow-sm">
                <label
                  id={"add-related-document-#{expense.id}"}
                  for={@related_upload.ref}
                  class="hover:bg-grey-50 text-grey-700 cursor-pointer rounded px-3 py-2 text-left text-sm font-medium"
                  phx-click="select-related-expense"
                  phx-value-id={expense.id}
                >
                  Dodaj powiązany dokument
                </label>
                <.button
                  :if={@kind == "accommodation"}
                  type="button"
                  variant="unstyled"
                  class="hover:bg-grey-50 text-grey-700 cursor-pointer justify-start rounded px-3 py-2 text-left text-sm font-medium"
                  phx-click={
                    if Map.get(@description_visible?, expense.id, false),
                      do: "hide-description",
                      else: "show-description"
                  }
                  phx-value-id={expense.id}
                >{if Map.get(@description_visible?, expense.id, false),
                  do: "Usuń opis",
                  else: "Dodaj opis"}</.button>
                <.button
                  type="button"
                  variant="unstyled"
                  class="cursor-pointer justify-start rounded px-3 py-2 text-left text-sm font-medium text-red-700 hover:bg-red-50"
                  phx-click="delete"
                  phx-value-kind={@kind}
                  phx-value-id={expense.id}
                >Usuń pozycję</.button>
              </div>
            </.dropdown>
          </div>
          <div
            :if={@editable?}
            id={"#{@kind}-expense-#{expense.id}"}
            class="mt-4 grid items-end gap-3 sm:grid-cols-2 lg:grid-cols-3"
          >
            <.input
              :if={@kind == "transport"}
              id={"#{@kind}-transport-type-#{expense.id}"}
              field={forms.details[:transport_type]}
              form="delegation-complete-form"
              type="select"
              new
              label="Środek lokomocji"
              options={SettlementPresentation.transport_options()}
            />
            <.input
              :if={@kind == "accommodation"}
              id={"#{@kind}-locality-#{expense.id}"}
              field={forms.details[:locality]}
              form="delegation-complete-form"
              type="text"
              new
              label="Miejscowość"
            />
            <.document_fields
              expense={expense}
              form={forms.expense}
              currency={Map.get(@expense_currencies, expense.id)}
            />
            <.input
              :if={@kind == "accommodation"}
              id={"#{@kind}-arrival-date-#{expense.id}"}
              field={forms.details[:arrival_date]}
              form="delegation-complete-form"
              type="date"
              new
              label="Zameldowanie"
            />
            <.input
              :if={@kind == "accommodation"}
              id={"#{@kind}-departure-date-#{expense.id}"}
              field={forms.details[:departure_date]}
              form="delegation-complete-form"
              type="date"
              new
              label="Wymeldowanie"
            />
            <.expense_description
              :if={@kind == "accommodation"}
              expense={expense}
              form={forms.details}
              kind={@kind}
              visible?={Map.get(@description_visible?, expense.id, false)}
            />
            <.input
              :if={@kind == "other"}
              id={"#{@kind}-description-#{expense.id}"}
              field={forms.details[:description]}
              form="delegation-complete-form"
              type="textarea"
              new
              label="Opis"
              class="col-span-full"
            />
          </div>
          <.expense_details
            :if={!@editable?}
            expense={expense}
            kind={@kind}
            timezone={@timezone}
          />
          <.trip_fields
            :if={@kind == "transport"}
            trips={expense.trips || []}
            editable?={@editable?}
            timezone={@timezone}
            description_visible?={@description_visible?}
            trip_forms={@trip_forms}
          />
          <.related_documents
            :if={expense.related_blobs != []}
            expense={expense}
            editable?={@editable?}
          />
        </article>
        <.pending_expense
          :for={entry <- if(@upload, do: @upload.entries, else: [])}
          entry={entry}
          kind={@kind}
        />
        <.form
          :if={@editable? && @upload}
          for={@upload_form}
          id={"#{@kind}-upload-form"}
          phx-change="upload"
          phx-submit="upload"
          class="relative"
        >
          <.file_upload
            upload={@upload}
            prompt="Przeciągnij tu fakturę/rachunek lub wybierz plik z komputera"
            content_class="text-grey-700!"
            class="border-grey-200! justify-between! rounded-lg! border! px-4! py-7!"
          />
          <.button
            as="label"
            for={@upload.ref}
            type="button"
            variant="secondary"
            size="small"
            class="absolute top-1/2 right-3 -translate-y-1/2"
          >Wybierz plik</.button>
        </.form>
      </div>
      <.documents_modal
        id={"#{@kind}-documents-modal"}
        title={@title}
        icon={render_slot(@icon)}
        kind={@kind}
      />
    </section>
    """
  end

  attr :expense, :any, required: true
  attr :editable?, :boolean, required: true

  defp related_documents(assigns) do
    ~H"""
    <div class="mt-4 flex flex-wrap items-center gap-2 text-sm">
      <span class="text-grey-700 font-medium">Powiązane dokumenty:</span>
      <div class="flex flex-wrap gap-2">
        <span
          :for={blob <- @expense.related_blobs}
          class="bg-grey-200 text-grey-600 inline-flex cursor-pointer items-center gap-1 rounded px-2 py-1 font-medium whitespace-nowrap"
        >
          <.link
            :if={blob.url}
            kind="unstyled"
            external={blob.url}
            target="_blank"
            rel="noopener noreferrer"
            class="inline-flex items-center gap-1"
          ><Lucideicons.file class="size-4 shrink-0" />{blob.original_filename}</.link>
          <span :if={!blob.url} class="inline-flex items-center gap-1">
            <Lucideicons.file class="size-4 shrink-0" />{blob.original_filename}
          </span>
          <.button
            :if={@editable?}
            type="button"
            variant="unstyled"
            class="text-grey-500 cursor-pointer"
            phx-click="remove-related-document"
            phx-value-expense-id={@expense.id}
            phx-value-blob-id={blob.id}
            aria-label={"Usuń #{blob.original_filename}"}
          ><Lucideicons.x class="size-3" /></.button>
        </span>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :icon, :any, required: true
  attr :kind, :string, required: true

  defp documents_modal(assigns) do
    ~H"""
    <.modal id={@id} on_cancel={hide_modal(@id)} class="max-w-[600px]">
      <h2 id={"#{@id}-title"} class="flex items-center gap-2 text-base font-medium text-black">
        {@icon}{@title} - jakie dokumenty załączyć?
      </h2>
      <div id={"#{@id}-description"} class="mt-5 flex flex-col gap-2 text-sm text-black">
        <%= case @kind do %>
          <% "transport" -> %>
            <.modal_paragraph heading="Masz Fakturę?">
              Jeśli masz
              <.document_emphasis>fakturę</.document_emphasis>
              za bilet lub przejazd, dodaj ją jako podstawowy dokument rozliczeniowy.
            </.modal_paragraph>
            <.modal_paragraph heading="Nie masz faktury?">
              Załącz
              <.document_emphasis>bilet</.document_emphasis>
              np. bilet kolejowy, autobusowy, lotniczy lub bilet komunikacji miejskiej wykorzystany w trakcie delegacji.
            </.modal_paragraph>
            <.modal_paragraph heading="Nie masz ani faktury, ani biletu?">
              Załącz
              <.document_emphasis>rezerwację</.document_emphasis>
              lub <.document_emphasis>potwierdzenie rezerwacji</.document_emphasis>. Dokument powinien pokazywać, czego dotyczył wydatek: trasę, datę, przewoźnika lub usługę. W tym przypadku załącz także <.document_emphasis>potwierdzenie płatności</.document_emphasis>.
            </.modal_paragraph>
            <hr class="border-grey-200 my-2 w-full" />
            <p>
              <span class="font-medium">Uwaga:</span>
              Samo potwierdzenie płatności nie wystarczy. Jeśli załączasz potwierdzenie przelewu lub płatności kartą, dodaj do niego dokument potwierdzający, za co była płatność, np. rezerwację.
            </p>
          <% "accommodation" -> %>
            <.modal_paragraph heading="Masz fakturę?">
              Jeśli masz
              <.document_emphasis>fakturę</.document_emphasis>
              za nocleg, dodaj ją jako podstawowy dokument rozliczeniowy.
            </.modal_paragraph>
            <.modal_paragraph heading="Nie masz faktury?">
              Załącz
              <.document_emphasis>rezerwację noclegu</.document_emphasis>
              oraz <.document_emphasis>potwierdzenie zapłaty</.document_emphasis>. Dotyczy to np. sytuacji, gdy nocleg był rezerwowany przez Booking lub podobny serwis i obiekt nie wystawił faktury. Wtedy do rozliczenia dodaj dokument rezerwacji oraz dowód, że nocleg został opłacony.
            </.modal_paragraph>
            <.modal_paragraph heading="Nie masz żadnego dokumentu?">
              Możesz wybrać
              <.document_emphasis>ryczałt</.document_emphasis>
              za nocleg. W takiej sytuacji musisz jednak mieć inne potwierdzenie, że delegacja faktycznie się odbyła, np. bilety transportowe lub inny dokument związany z wyjazdem. Do tego wystarczy ci wypełniona sekcja "Przejazdy".
            </.modal_paragraph>
          <% "other" -> %>
            <p>
              Inne wydatki powinny mieć dokument pokazujący, czego dotyczył koszt. Najlepiej załączyć fakturę, rachunek, bilet, rezerwację, polisę albo inny dokument potwierdzający usługę lub zakup. Jeśli masz tylko potwierdzenie płatności, dodaj też dokument opisujący, za co zapłacono.
            </p>
            <p>
              Wydatek musi być związany z delegacją. Przykładowo ubezpieczenie można rozliczyć wtedy, gdy pokrywa się z podróżą służbową.
            </p>
        <% end %>
      </div>
    </.modal>
    """
  end

  attr :heading, :string, required: true
  slot :inner_block, required: true

  defp modal_paragraph(assigns) do
    ~H"""
    <div>
      <h3 class="font-medium">{@heading}</h3><p>{render_slot(@inner_block)}</p>
    </div>
    """
  end

  slot :inner_block, required: true

  defp document_emphasis(assigns) do
    ~H"""
    <span class="text-turquoise-700 font-medium underline">{render_slot(@inner_block)}</span>
    """
  end

  @doc "Renders a money row in the settlement summary."
  @spec summary_row(map()) :: Rendered.t()
  attr :label, :string, required: true
  attr :value, Money, required: true
  attr :class, :string, default: ""

  def summary_row(assigns) do
    ~H"""
    <div class={["flex justify-between gap-4", @class]}>
      <dt>{@label}</dt><dd class={[Money.zero?(@value) && "text-grey-500"]}>
        {Money.to_string!(@value)}
      </dd>
    </div>
    """
  end

  attr :entry, :any, required: true
  attr :kind, :string, required: true

  defp pending_expense(assigns) do
    ~H"""
    <article
      :if={!@entry.done?}
      id={"#{@kind}-pending-expense-#{@entry.ref}"}
      aria-busy="true"
      class="border-grey-200 rounded-lg border p-4"
    >
      <div class="text-grey-500 flex items-center justify-between gap-3 text-sm">
        <span class="flex min-w-0 items-center gap-2 truncate">
          <Lucideicons.loader_circle class="size-5 shrink-0 animate-spin" />
          {@entry.client_name}
        </span>
        <span class="shrink-0 tabular-nums">{@entry.progress}%</span>
      </div>
      <.pending_expense_form kind={@kind} />
    </article>
    """
  end

  attr :kind, :string, required: true

  defp pending_expense_form(%{kind: "transport"} = assigns) do
    ~H"""
    <div class="mt-4 grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
      <.skeleton_field label="Środek lokomocji" />
      <.skeleton_field label="Nr dokumentu" shimmer? />
      <.skeleton_amount_field />
    </div>
    <div class="border-grey-100 mt-4 border-t pt-4">
      <table class="border-separate border-spacing-y-3 text-left text-sm">
        <thead class="text-grey-500">
          <tr>
            <th scope="col"></th>
            <th scope="col" class="font-normal">Miejscowość</th>
            <th scope="col" class="font-normal">Data</th>
            <th scope="col" class="font-normal">Godzina</th>
          </tr>
        </thead>
        <tbody>
          <tr>
            <th scope="row" class="text-grey-700 pr-3 font-normal">Wyjazd</th>
            <td class="pr-3"><.skeleton_blob class="w-[237px] min-w-[237px]" /></td>
            <td class="pr-3"><.skeleton_blob class="w-[172px] min-w-[172px]" /></td>
            <td><.skeleton_blob class="w-[91px] min-w-[91px]" /></td>
          </tr>
          <tr>
            <th scope="row" class="text-grey-700 pr-3 font-normal">Przyjazd</th>
            <td class="pr-3"><.skeleton_blob class="w-[237px] min-w-[237px]" /></td>
            <td class="pr-3"><.skeleton_blob class="w-[172px] min-w-[172px]" /></td>
            <td><.skeleton_blob class="w-[91px] min-w-[91px]" /></td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  defp pending_expense_form(%{kind: "accommodation"} = assigns) do
    ~H"""
    <div class="mt-4 grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
      <.skeleton_field label="Miejscowość" />
      <.skeleton_field label="Nr dokumentu" shimmer? />
      <.skeleton_amount_field />
      <.skeleton_field label="Zameldowanie" />
      <.skeleton_field label="Wymeldowanie" />
    </div>
    """
  end

  defp pending_expense_form(%{kind: "other"} = assigns) do
    ~H"""
    <div class="mt-4 grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
      <.skeleton_field label="Nr dokumentu" shimmer? />
      <.skeleton_amount_field />
      <.skeleton_field label="Opis" class="col-span-full" />
    </div>
    """
  end

  attr :label, :string, required: true
  attr :class, :any, default: nil
  attr :shimmer?, :boolean, default: false

  defp skeleton_field(assigns) do
    ~H"""
    <div class={["w-full min-w-0", @class]}>
      <div class="text-grey-700 mb-2 flex items-center gap-1 text-sm/6">
        <Lucideicons.sparkles :if={@shimmer?} class="size-4" aria-hidden="true" />
        {@label}
      </div>
      <.skeleton_blob />
    </div>
    """
  end

  defp skeleton_amount_field(assigns) do
    ~H"""
    <div class="w-full min-w-0">
      <div class="text-grey-700 mb-2 flex items-center gap-1 text-sm/6">
        <Lucideicons.sparkles class="size-4" aria-hidden="true" /> Kwota
      </div>
      <div class="flex items-end gap-2">
        <.skeleton_blob class="flex-1" />
        <span class="text-grey-500 shrink-0 pb-2 text-sm whitespace-nowrap">PLN</span>
      </div>
    </div>
    """
  end

  attr :class, :any, default: nil

  defp skeleton_blob(assigns) do
    ~H"""
    <div class={[
      "bg-grey-200 border-grey-200 block h-9 min-h-9 w-full min-w-0 animate-pulse rounded-lg border",
      @class
    ]} />
    """
  end

  attr :expense, :any, required: true
  attr :form, Form, required: true
  attr :currency, :string, default: nil

  defp document_fields(assigns) do
    amount_field = assigns.form[:expense_amount]
    currency = assigns.currency || expense_currency(amount_field.value)

    assigns =
      assigns
      |> assign(:amount_field, amount_field)
      |> assign(:currency, currency)
      |> assign(:foreign_currency?, currency != @company_currency)

    ~H"""
    <.input
      id={"document-number-#{@expense.id}"}
      field={@form[:document_number]}
      form="delegation-complete-form"
      type="text"
      new
    >
      <:label_slot>
        <span class="inline-flex items-center gap-1">
          <Lucideicons.sparkles class="size-4" aria-hidden="true" /> Nr dokumentu
        </span>
      </:label_slot>
    </.input>
    <div class="flex items-end gap-2">
      <div class="w-25 shrink-0">
        <.input
          id={"expense-amount-#{@expense.id}"}
          field={@form[:expense_amount]}
          form="delegation-complete-form"
          value={expense_amount_value(@form[:expense_amount].value)}
          type="number"
          new
          min="0"
          step="0.01"
          input_class="w-25"
        >
          <:label_slot>
            <span class="inline-flex items-center gap-1">
              <Lucideicons.sparkles class="size-4" aria-hidden="true" /> Kwota
            </span>
          </:label_slot>
        </.input>
      </div>
      <form id={"expense-currency-form-#{@expense.id}"} phx-change="select-expense-currency">
        <.input
          id={"expense-currency-#{@expense.id}"}
          name={"expense_currencies[#{@expense.id}]"}
          value={@currency}
          type="select"
          new
          options={currency_options()}
          input_class={["w-24 shrink-0", @foreign_currency? && "bg-turquoise-100"]}
          aria-label="Waluta"
        />
      </form>
    </div>
    <.foreign_currency_notice :if={@foreign_currency?} expense_id={@expense.id} />
    """
  end

  attr :expense_id, :string, required: true

  defp foreign_currency_notice(assigns) do
    ~H"""
    <section
      id={"foreign-currency-notice-#{@expense_id}"}
      class="bg-turquoise-100 border-grey-200 text-turquoise-700 mt-1 flex w-full flex-wrap items-center justify-between gap-3 rounded-lg border p-6 sm:col-span-2 lg:col-span-3"
    >
      <p>Wykryto obcą walutę</p>
      <div class="flex gap-2">
        <.button
          type="button"
          variant="primary"
          accent="turquoise"
          size="small"
          phx-click="foreign-currency-action"
          phx-value-action="statement"
        >Mam kwotę z wyciągu</.button>
        <.button
          type="button"
          variant="primary"
          accent="turquoise"
          size="small"
          phx-click="foreign-currency-action"
          phx-value-action="nbp"
        >Przelicz wg kursu NBP</.button>
      </div>
    </section>
    """
  end

  defp currency_options do
    popular = ~w(PLN EUR GBP USD)
    currencies = Enum.map(Money.known_current_currencies(), &Atom.to_string/1)

    [
      {"Najczęściej używane", popular},
      {"Wszystkie waluty", currencies -- popular}
    ]
  end

  defp expense_currency(%Money{} = amount), do: amount |> Money.to_currency_code() |> Atom.to_string()

  defp expense_currency(%{"currency" => currency}) when is_binary(currency), do: currency
  defp expense_currency(_amount), do: @company_currency

  attr :expense, :any, required: true
  attr :kind, :string, required: true
  attr :timezone, :string, required: true

  defp expense_details(assigns) do
    ~H"""
    <dl class="mt-4 grid gap-3 text-sm sm:grid-cols-2 lg:grid-cols-3">
      <.expense_detail
        :if={@kind == "transport"}
        label="Środek lokomocji"
        value={SettlementPresentation.transport_label(to_string(@expense.transport_type))}
      />
      <.expense_detail label="Nr dokumentu" value={@expense.document_number} />
      <.expense_detail label="Kwota" value={Money.to_string!(@expense.expense_amount)} />
      <.expense_detail :if={@kind == "accommodation"} label="Miejscowość" value={@expense.locality} />
      <.expense_detail
        :if={@kind == "accommodation"}
        label="Zameldowanie"
        value={SettlementPresentation.format_date(@expense.arrival_date)}
      />
      <.expense_detail
        :if={@kind == "accommodation"}
        label="Wymeldowanie"
        value={SettlementPresentation.format_date(@expense.departure_date)}
      />
      <.expense_detail
        :if={@kind in ["accommodation", "other"]}
        label="Opis"
        value={@expense.description}
        class="sm:col-span-2 lg:col-span-3"
      />
      <.trip_details :if={@kind == "transport"} trips={@expense.trips || []} timezone={@timezone} />
    </dl>
    """
  end

  attr :expense, :any, required: true
  attr :form, Form, required: true
  attr :kind, :string, required: true
  attr :visible?, :boolean, required: true

  defp expense_description(assigns) do
    ~H"""
    <div class="col-span-full flex flex-col items-end gap-2">
      <.input
        :if={@visible?}
        id={"#{@kind}-description-#{@expense.id}"}
        field={@form[:description]}
        form="delegation-complete-form"
        type="textarea"
        new
        label="Opis"
        class="w-full"
      />
    </div>
    """
  end

  attr :trips, :list, required: true
  attr :editable?, :boolean, required: true
  attr :timezone, :string, required: true
  attr :description_visible?, :map, required: true
  attr :trip_forms, :map, required: true

  defp trip_fields(assigns) do
    ~H"""
    <section
      :for={{trip, index} <- Enum.with_index(@trips, 1)}
      :if={@editable?}
      class={[
        "border-grey-100 mt-4 border-t pt-4",
        length(@trips) > 1 && "grid grid-cols-[1.5rem_minmax(0,1fr)] gap-x-4"
      ]}
    >
      <% trip_form = Map.fetch!(@trip_forms, trip.id) %>
      <span :if={length(@trips) > 1} class="text-grey-900 self-center text-center text-sm font-medium">
        {SettlementPresentation.roman_numeral(index)}
      </span>
      <div
        id={"transport-trip-#{trip.id}"}
        class={[length(@trips) > 1 && "border-grey-200 border-l pl-4"]}
      >
        <div class="min-w-0">
          <table class="border-separate border-spacing-y-3 text-left text-sm">
            <thead class="text-grey-500">
              <tr>
                <th scope="col"></th>
                <th scope="col" class="font-normal">Miejscowość</th>
                <th scope="col" class="font-normal">Data</th>
                <th scope="col" class="font-normal">Godzina</th>
                <th scope="col"></th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <th scope="row" class="text-grey-700 pr-3 font-normal">Wyjazd</th>
                <td class="pr-3">
                  <.input
                    id={"trip-departure-city-#{trip.id}"}
                    field={trip_form[:departure_city]}
                    form="delegation-complete-form"
                    type="text"
                    new
                    aria-label="Miejscowość wyjazdu"
                    input_class="w-36"
                  />
                </td>
                <td class="pr-3">
                  <.input
                    id={"trip-departure-date-#{trip.id}"}
                    form="delegation-complete-form"
                    name={"#{trip_form.name}[departure_date]"}
                    value={
                      trip_form.params["departure_date"] ||
                        date_value(trip_form[:departure_datetime].value, @timezone)
                    }
                    errors={translated_errors(trip_form[:departure_datetime])}
                    type="date"
                    new
                    aria-label="Data wyjazdu"
                    input_class="w-34"
                  />
                </td>
                <td>
                  <.input
                    id={"trip-departure-time-#{trip.id}"}
                    form="delegation-complete-form"
                    name={"#{trip_form.name}[departure_time]"}
                    value={
                      trip_form.params["departure_time"] ||
                        time_value(trip_form[:departure_datetime].value, @timezone)
                    }
                    errors={translated_errors(trip_form[:departure_datetime])}
                    type="time"
                    new
                    aria-label="Godzina wyjazdu"
                    input_class="w-24"
                  />
                </td>
                <td rowspan="2" class="w-24 pl-3 align-bottom">
                  <% description_visible? = Map.get(@description_visible?, trip.id, false) %>
                  <.button
                    type="button"
                    variant="unstyled"
                    class={[
                      "block w-24 cursor-pointer text-left text-sm font-normal whitespace-nowrap",
                      description_visible? && "text-red-700"
                    ]}
                    phx-click={
                      if description_visible?, do: "hide-description", else: "show-description"
                    }
                    phx-value-id={trip.id}
                  >{if description_visible?, do: "Usuń opis", else: "Dodaj opis"}</.button>
                </td>
              </tr>
              <tr>
                <th scope="row" class="text-grey-700 pr-3 font-normal">Przyjazd</th>
                <td class="pr-3">
                  <.input
                    id={"trip-arrival-city-#{trip.id}"}
                    field={trip_form[:arrival_city]}
                    form="delegation-complete-form"
                    type="text"
                    new
                    aria-label="Miejscowość przyjazdu"
                    input_class="w-36"
                  />
                </td>
                <td class="pr-3">
                  <.input
                    id={"trip-arrival-date-#{trip.id}"}
                    form="delegation-complete-form"
                    name={"#{trip_form.name}[arrival_date]"}
                    value={
                      trip_form.params["arrival_date"] ||
                        date_value(trip_form[:arrival_datetime].value, @timezone)
                    }
                    errors={translated_errors(trip_form[:arrival_datetime])}
                    type="date"
                    new
                    aria-label="Data przyjazdu"
                    input_class="w-34"
                  />
                </td>
                <td>
                  <.input
                    id={"trip-arrival-time-#{trip.id}"}
                    form="delegation-complete-form"
                    name={"#{trip_form.name}[arrival_time]"}
                    value={
                      trip_form.params["arrival_time"] ||
                        time_value(trip_form[:arrival_datetime].value, @timezone)
                    }
                    errors={translated_errors(trip_form[:arrival_datetime])}
                    type="time"
                    new
                    aria-label="Godzina przyjazdu"
                    input_class="w-24"
                  />
                </td>
              </tr>
              <tr :if={
                Map.get(@description_visible?, trip.id, false) ||
                  trip_form[:description].value not in [nil, ""]
              }>
                <th scope="row" class="text-grey-700 pt-2 pr-3 align-top font-normal">Opis</th>
                <td colspan="4">
                  <.input
                    id={"trip-description-#{trip.id}"}
                    field={trip_form[:description]}
                    form="delegation-complete-form"
                    type="textarea"
                    new
                    aria-label="Opis"
                  />
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </section>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :class, :any, default: nil

  defp expense_detail(assigns) do
    ~H"""
    <div class={@class}>
      <dt class="text-grey-500">{@label}</dt>
      <dd class="text-grey-700 mt-1 whitespace-pre-wrap">
        {SettlementPresentation.present_value(@value)}
      </dd>
    </div>
    """
  end

  attr :trips, :list, required: true
  attr :timezone, :string, required: true

  defp trip_details(assigns) do
    ~H"""
    <section
      :for={{trip, index} <- Enum.with_index(@trips, 1)}
      class={[
        "border-grey-100 mt-1 border-t pt-4 sm:col-span-2 lg:col-span-3",
        length(@trips) > 1 && "grid grid-cols-[1.5rem_minmax(0,1fr)] gap-x-4"
      ]}
    >
      <span :if={length(@trips) > 1} class="text-grey-900 self-center text-center text-sm font-medium">
        {SettlementPresentation.roman_numeral(index)}
      </span>
      <div class={[length(@trips) > 1 && "border-grey-200 border-l pl-4"]}>
        <table class="border-separate border-spacing-y-3 text-left text-sm">
          <thead class="text-grey-500">
            <tr>
              <th scope="col"></th>
              <th scope="col" class="font-normal">Miejscowość</th>
              <th scope="col" class="font-normal">Data</th>
              <th scope="col" class="font-normal">Godzina</th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <th scope="row" class="text-grey-700 pr-3 font-normal">Wyjazd</th>
              <td class="pr-3">{SettlementPresentation.present_value(trip.departure_city)}</td>
              <td class="pr-3">
                {SettlementPresentation.format_date(
                  SettlementPresentation.datetime_date(trip.departure_datetime, @timezone)
                )}
              </td>
              <td>{SettlementPresentation.format_time(trip.departure_datetime, @timezone)}</td>
            </tr>
            <tr>
              <th scope="row" class="text-grey-700 pr-3 font-normal">Przyjazd</th>
              <td class="pr-3">{SettlementPresentation.present_value(trip.arrival_city)}</td>
              <td class="pr-3">
                {SettlementPresentation.format_date(
                  SettlementPresentation.datetime_date(trip.arrival_datetime, @timezone)
                )}
              </td>
              <td>{SettlementPresentation.format_time(trip.arrival_datetime, @timezone)}</td>
            </tr>
          </tbody>
        </table>
        <dl class="mt-3"><.expense_detail label="Opis" value={trip.description} /></dl>
      </div>
    </section>
    """
  end

  defp date_value(nil, _timezone), do: nil

  defp date_value(datetime, timezone) do
    datetime |> DateTime.shift_zone!(timezone) |> Calendar.strftime("%Y-%m-%d")
  end

  defp time_value(nil, _timezone), do: nil

  defp time_value(datetime, timezone) do
    datetime |> DateTime.shift_zone!(timezone) |> Calendar.strftime("%H:%M")
  end

  defp translated_errors(field), do: Enum.map(field.errors, &translate_error/1)

  defp expense_amount_value(%Money{} = amount), do: Money.to_decimal(amount)
  defp expense_amount_value(amount), do: amount
end
