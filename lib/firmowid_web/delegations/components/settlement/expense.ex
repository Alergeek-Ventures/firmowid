defmodule FirmowidWeb.Delegations.Components.Settlement.Expense do
  @moduledoc "Function components for delegation settlement expense categories."

  use FirmowidWeb, :html

  import FirmowidWeb.Delegations.Components.Settlement.Documents
  import FirmowidWeb.Delegations.Components.Settlement.ForeignCurrency
  import FirmowidWeb.Delegations.Components.Settlement.Trips
  import FirmowidWeb.DesignSystem.Components.Button
  import FirmowidWeb.DesignSystem.Components.CoreComponents, except: [button: 1]
  import FirmowidWeb.DesignSystem.Components.Link
  import Phoenix.Component, except: [link: 1]

  alias FirmowidWeb.Delegations.Utilities.SettlementPresentation
  alias Phoenix.HTML.Form
  alias Phoenix.LiveView.Rendered

  @doc "Renders an expense category, its documents, and upload control."
  @spec expense_section(map()) :: Rendered.t()
  attr :title, :string, required: true
  slot :icon, required: true
  attr :expenses, :list, required: true
  attr :upload, :any, required: true
  attr :kind, :string, required: true
  attr :editable?, :boolean, required: true
  attr :sort_active?, :boolean, required: true
  attr :description_visible?, :map, default: %{}
  attr :expense_forms, :map, required: true
  attr :trip_forms, :map, required: true
  attr :timezone, :string, required: true
  attr :related_upload, :any, required: true
  attr :expense_currencies, :map, default: %{}
  attr :foreign_currency_modes, :map, default: %{}
  attr :nbp_settlements, :map, default: %{}
  attr :statement_upload, :any, required: true
  attr :statement_expense_id, :string, default: nil

  def expense_section(assigns) do
    ~H"""
    <section class="mt-10">
      <header class="mb-3">
        <div class="flex flex-wrap items-center gap-3">
          <h2 class="flex items-center gap-2 font-normal">
            {render_slot(@icon)}{@title}
          </h2>
          <span
            :if={@kind == "transport" && @editable?}
            class="bg-grey-200 h-5 w-px sm:hidden"
            aria-hidden="true"
          />
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
          <span class="bg-grey-200 hidden h-5 w-px sm:block" aria-hidden="true" />
          <.button
            type="button"
            variant="unstyled"
            class="text-grey-700 hidden text-sm font-medium hover:underline sm:inline-flex"
            phx-click={show_modal("#{@kind}-documents-modal")}
          >Jakie dokumenty załączyć?</.button>
        </div>
        <.button
          type="button"
          variant="unstyled"
          class="text-grey-700 mt-2 text-sm font-medium hover:underline sm:hidden"
          phx-click={show_modal("#{@kind}-documents-modal")}
        >Jakie dokumenty załączyć?</.button>
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
              type="select"
              new
              label="Środek lokomocji"
              options={SettlementPresentation.transport_options()}
            />
            <.input
              :if={@kind == "accommodation"}
              id={"#{@kind}-locality-#{expense.id}"}
              field={forms.details[:locality]}
              type="text"
              new
              label="Miejscowość"
            />
            <.document_fields
              expense={expense}
              form={forms.expense}
              currency={Map.get(@expense_currencies, expense.id)}
              foreign_currency_mode={Map.get(@foreign_currency_modes, expense.id, :notice)}
              nbp_settlement={Map.get(@nbp_settlements, expense.id)}
              statement_upload={@statement_upload}
              statement_blob={expense.statement_blob}
              statement_expense_id={@statement_expense_id}
            />
            <.input
              :if={@kind == "accommodation"}
              id={"#{@kind}-arrival-date-#{expense.id}"}
              field={forms.details[:arrival_date]}
              type="date"
              new
              label="Zameldowanie"
            />
            <.input
              :if={@kind == "accommodation"}
              id={"#{@kind}-departure-date-#{expense.id}"}
              field={forms.details[:departure_date]}
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
        <div
          :if={@editable? && @upload}
          id={"#{@kind}-upload-form"}
          class="relative"
        >
          <.file_upload
            upload={@upload}
            prompt="Wgraj fakturę/rachunek"
            content_class="text-grey-700!"
            prompt_class="sm:hidden"
            class="border-grey-200! justify-between! rounded-lg! border! px-4! py-7! sm:py-10!"
            phx_change="upload"
          />
          <p class="text-grey-700 pointer-events-none absolute top-1/2 left-4 hidden -translate-y-1/2 text-sm sm:block">
            Przeciągnij tu fakturę/rachunek lub wybierz plik z komputera
          </p>
          <.button
            as="label"
            for={@upload.ref}
            type="button"
            variant="secondary"
            size="small"
            class="absolute top-1/2 right-3 -translate-y-1/2"
          >Wybierz plik</.button>
        </div>
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
        type="textarea"
        new
        label="Opis"
        class="w-full"
      />
    </div>
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
end
