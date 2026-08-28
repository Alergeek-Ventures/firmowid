defmodule FirmowidWeb.Delegations.Views.Delegation do
  @moduledoc "Settlement page for an approved business trip delegation."

  use FirmowidWeb, :live_view

  import FirmowidWeb.DesignSystem.Components.Button
  import FirmowidWeb.DesignSystem.Components.CoreComponents, except: [button: 1]
  import FirmowidWeb.Delegations.Components.Delegation

  alias Firmowid.Ash.Delegations

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case load_delegation(id, socket) do
      {:ok, nil} ->
        {:ok, push_navigate(socket, to: ~p"/ustawienia/profil")}

      {:ok, delegation} ->
        if delegation.status in [:in_progress, :complete] do
          {:ok, setup_socket(socket, delegation)}
        else
          {:ok, push_navigate(socket, to: ~p"/ustawienia/profil")}
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="relative mt-4">
      <.back
        navigate={~p"/ustawienia/profil"}
        class="absolute top-0 left-0.5 inline-flex text-sm"
      />
      <main class="grid gap-10 px-32 pr-34 pb-12 font-[340] lg:grid-cols-[auto_22.5rem]">
        <section aria-labelledby="delegation-settlement-title">
          <small class="text-grey-500 text-sm">Cel:
          <span class="text-grey-700">{@delegation.purpose}</span></small>
          <h1 id="delegation-settlement-title" class="mt-1 text-2xl font-medium">
            Rozliczenie delegacji
          </h1>
          <p class="text-grey-700 mt-3 max-w-2xl text-balance">
            Załącz bilety i rachunki. Uzupełnij potrzebne dane. Kwoty i numery faktur uzupełnimy automatycznie.
          </p>

          <.expense_section
            title="Przejazdy"
            expenses={@delegation.transport_expenses}
            upload={Map.get(@uploads, :transport)}
            kind="transport"
            editable?={@editable?}
            sort_active?={@sort_active?}
          >
            <:icon><Lucideicons.plane class="size-5" /></:icon>
          </.expense_section>
          <.expense_section
            title="Nocleg"
            expenses={@delegation.accommodation_expenses}
            upload={Map.get(@uploads, :accommodation)}
            kind="accommodation"
            editable?={@editable?}
            sort_active?={false}
          >
            <:icon><Lucideicons.bed_double class="size-5" /></:icon>
          </.expense_section>
          <.expense_section
            title="Inne wydatki"
            expenses={@delegation.other_expenses}
            upload={Map.get(@uploads, :other)}
            kind="other"
            editable?={@editable?}
            sort_active?={false}
          >
            <:icon><Lucideicons.wallet class="size-5" /></:icon>
          </.expense_section>
        </section>
        <aside class="lg:pt-1">
          <dl class="text-grey-500 flex justify-end gap-4">
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
          <div class="mt-6 rounded-lg bg-white px-6 py-4 shadow-sm lg:mt-47">
            <h2 class="text-grey-500 font-normal">Podsumowanie</h2>
            <dl class="mt-6 space-y-3 text-sm">
              <.summary_row label="Przejazdy" value={sum(@delegation.transport_expenses)} />
              <.summary_row label="Nocleg" value={sum(@delegation.accommodation_expenses)} />
              <.summary_row label="Inne" value={sum(@delegation.other_expenses)} />
              <div class="border-grey-100 my-5 space-y-3 border-y py-5">
                <.summary_row label="Razem koszty" value={@total} class="font-medium" />
                <.summary_row
                  label="Pobrana zaliczka"
                  value={@delegation.advance_payment_amount}
                />
              </div>
              <.summary_row label={@balance_label} value={@balance} />
            </dl>
          </div>
          <.button
            :if={@editable?}
            variant="primary"
            accent="turquoise"
            size="big"
            class="mt-6 w-full"
            phx-click="submit"
          >Wyślij</.button>
        </aside>
      </main>
    </div>
    """
  end

  attr :title, :string, required: true
  slot :icon, required: true
  attr :expenses, :list, required: true
  attr :upload, :any, required: true
  attr :kind, :string, required: true
  attr :editable?, :boolean, required: true
  attr :sort_active?, :boolean, required: true

  defp expense_section(assigns) do
    ~H"""
    <section class="mt-10">
      <header class="mb-3 flex items-center justify-between">
        <h2 class="flex items-center gap-2 font-normal">
          {render_slot(@icon)}{@title}
        </h2>
        <.button
          :if={@kind == "transport"}
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
        <article :for={expense <- @expenses} class="border-grey-200 rounded-lg border p-4">
          <div class="text-grey-500 flex items-center justify-between gap-3 text-sm">
            <span class="flex min-w-0 items-center gap-2 truncate"><.icon
              name="hero-document"
              class="size-5 shrink-0"
            />{expense.original_filename}</span>
            <.button
              :if={@editable?}
              type="button"
              variant="icon"
              aria-label="Usuń dokument"
              phx-click="delete"
              phx-value-kind={@kind}
              phx-value-id={expense.id}
            ><Lucideicons.x class="size-4" /></.button>
          </div>
          <form
            :if={@editable?}
            phx-change="update"
            phx-value-kind={@kind}
            phx-value-id={expense.id}
            class="mt-4 grid gap-3 sm:grid-cols-2"
          >
            <label>Nr dokumentu<input
              class="input"
              name="document_number"
              value={expense.document_number}
            /></label>
            <label>Kwota<input
              class="input"
              name="expense_amount"
              type="number"
              min="0"
              step="0.01"
              value={Money.to_decimal(expense.expense_amount)}
            /></label>
            <label :if={@kind == "transport"}>Środek lokomocji<select
              class="input"
              name="transport_type"
            ><option
              :for={type <- ~w(railway airplane bus other)}
              value={type}
              selected={expense.transport_type == String.to_existing_atom(type)}
            >
              {transport_label(type)}
            </option></select></label>
            <label :if={@kind == "accommodation"}>Miejscowość<input
              class="input"
              name="locality"
              value={expense.locality}
            /></label>
            <label :if={@kind == "accommodation"}>Zameldowanie<input
              class="input"
              type="date"
              name="arrival_date"
              value={expense.arrival_date}
            /></label>
            <label :if={@kind == "accommodation"}>Wymeldowanie<input
              class="input"
              type="date"
              name="departure_date"
              value={expense.departure_date}
            /></label>
            <label :if={@kind == "other" or @kind == "accommodation"} class="sm:col-span-2">Opis<textarea
              class="input"
              name="description"
            >{expense.description}</textarea></label>
          </form>
        </article>
        <form
          :if={@editable? && @upload}
          id={"#{@kind}-upload-form"}
          phx-change="upload"
          phx-submit="upload"
          phx-value-kind={@kind}
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
        </form>
      </div>
    </section>
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

  @impl true
  def handle_event("upload", _params, %{assigns: %{editable?: false}} = socket), do: {:noreply, socket}

  def handle_event("upload", %{"kind" => kind}, socket) do
    {:noreply, consume_upload(socket, String.to_existing_atom(kind))}
  end

  def handle_event("update", %{"kind" => kind, "id" => id} = params, socket) do
    attrs = update_attrs(kind, params)
    result = update_expense(kind, id, attrs, socket.assigns.ash_scope)

    {:noreply,
     if(match?({:ok, _}, result),
       do: reload(socket),
       else: put_flash(socket, :error, "Nie udało się zapisać danych.")
     )}
  end

  def handle_event("delete", %{"kind" => kind, "id" => id}, socket) do
    result = destroy_expense(kind, id, socket.assigns.ash_scope)

    {:noreply,
     if(match?({:ok, _}, result),
       do: reload(socket),
       else: put_flash(socket, :error, "Nie udało się usunąć dokumentu.")
     )}
  end

  def handle_event("sort", _params, socket), do: {:noreply, assign(socket, :sort_active?, true)}

  def handle_event("submit", _params, %{assigns: %{editable?: false}} = socket), do: {:noreply, socket}

  def handle_event("submit", _params, socket) do
    case Delegations.complete_delegation(socket.assigns.delegation.id,
           scope: socket.assigns.ash_scope
         ) do
      {:ok, delegation} ->
        {:noreply, setup_socket(socket, load_delegation!(delegation.id, socket))}

      _ ->
        {:noreply, put_flash(socket, :error, "Nie udało się wysłać rozliczenia.")}
    end
  end

  defp setup_socket(socket, delegation) do
    transport =
      if delegation.status == :complete,
        do: nil,
        else:
          allow_upload(socket, :transport,
            accept: ~w(.pdf .png .jpg .jpeg),
            max_entries: 1,
            auto_upload: true
          )

    socket = if transport, do: transport, else: socket

    socket =
      if delegation.status == :complete,
        do: socket,
        else:
          socket
          |> allow_upload(:accommodation,
            accept: ~w(.pdf .png .jpg .jpeg),
            max_entries: 1,
            auto_upload: true
          )
          |> allow_upload(:other,
            accept: ~w(.pdf .png .jpg .jpeg),
            max_entries: 1,
            auto_upload: true
          )

    socket
    |> assign(
      delegation: delegation,
      editable?: delegation.status == :in_progress,
      page_title: "Rozliczenie delegacji",
      sort_active?: false
    )
    |> assign_summary()
  end

  defp load_delegation(id, socket),
    do:
      Delegations.get_delegation(id,
        scope: socket.assigns.ash_scope,
        load: [:transport_expenses, :accommodation_expenses, :other_expenses],
        not_found_error?: false
      )

  defp load_delegation!(id, socket), do: elem(load_delegation(id, socket), 1)

  defp reload(socket), do: setup_socket(socket, load_delegation!(socket.assigns.delegation.id, socket))

  defp consume_upload(socket, kind) do
    consume_uploaded_entries(socket, kind, fn %{path: _path}, entry ->
      create_expense(
        kind,
        socket.assigns.delegation.id,
        entry.client_name,
        socket.assigns.ash_scope
      )
    end)

    reload(socket)
  end

  defp create_expense(:transport, id, filename, scope),
    do: Delegations.create_transport_expense(%{delegation_id: id, original_filename: filename}, scope: scope)

  defp create_expense(:accommodation, id, filename, scope),
    do: Delegations.create_accommodation_expense(%{delegation_id: id, original_filename: filename}, scope: scope)

  defp create_expense(:other, id, filename, scope),
    do: Delegations.create_other_expense(%{delegation_id: id, original_filename: filename, description: ""}, scope: scope)

  defp update_expense(kind, id, attrs, scope) do
    with {:ok, expense} <- get_expense(kind, id, scope) do
      case kind do
        "transport" -> Delegations.update_transport_expense(expense, attrs, scope: scope)
        "accommodation" -> Delegations.update_accommodation_expense(expense, attrs, scope: scope)
        "other" -> Delegations.update_other_expense(expense, attrs, scope: scope)
      end
    end
  end

  defp destroy_expense(kind, id, scope) do
    with {:ok, expense} <- get_expense(kind, id, scope) do
      case kind do
        "transport" -> Delegations.destroy_transport_expense(expense, scope: scope)
        "accommodation" -> Delegations.destroy_accommodation_expense(expense, scope: scope)
        "other" -> Delegations.destroy_other_expense(expense, scope: scope)
      end
    end
  end

  defp get_expense("transport", id, scope),
    do: Delegations.get_transport_expense(id, scope: scope, not_found_error?: false)

  defp get_expense("accommodation", id, scope),
    do: Delegations.get_accommodation_expense(id, scope: scope, not_found_error?: false)

  defp get_expense("other", id, scope), do: Delegations.get_other_expense(id, scope: scope, not_found_error?: false)

  defp update_attrs(kind, params) do
    params
    |> Map.take([
      "document_number",
      "description",
      "locality",
      "arrival_date",
      "departure_date",
      "transport_type"
    ])
    |> maybe_put_amount(params["expense_amount"])
    |> maybe_atom(:transport_type, kind)
  end

  defp maybe_put_amount(attrs, nil), do: attrs

  defp maybe_put_amount(attrs, amount), do: Map.put(attrs, :expense_amount, Money.new(:PLN, Decimal.new(amount)))

  defp maybe_atom(attrs, _key, kind) when kind != "transport", do: attrs

  defp maybe_atom(attrs, key, _kind), do: Map.update(attrs, key, :other, &String.to_existing_atom/1)

  defp assign_summary(socket) do
    total =
      Enum.reduce(
        [
          socket.assigns.delegation.transport_expenses,
          socket.assigns.delegation.accommodation_expenses,
          socket.assigns.delegation.other_expenses
        ],
        Money.new(:PLN, 0),
        fn expenses, acc -> Enum.reduce(expenses, acc, &Money.add!(&2, &1.expense_amount)) end
      )

    advance = socket.assigns.delegation.advance_payment_amount
    comparison = Money.compare(total, advance)

    {label, balance} =
      if comparison in [:gt, :eq],
        do: {"Do dopłaty", Money.sub!(total, advance)},
        else: {"Pomniejszenie wypłaty", Money.sub!(advance, total)}

    assign(socket,
      total: total,
      balance_label: label,
      balance: balance
    )
  end

  defp sum(expenses), do: Enum.reduce(expenses, Money.new(:PLN, 0), &Money.add!(&2, &1.expense_amount))

  defp transport_label("railway"), do: "Kolej"
  defp transport_label("airplane"), do: "Samolot"
  defp transport_label("bus"), do: "Autobus"
  defp transport_label("other"), do: "Inne"
end
