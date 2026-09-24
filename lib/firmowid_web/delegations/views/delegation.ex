defmodule FirmowidWeb.Delegations.Views.Delegation do
  @moduledoc "Settlement page for an approved business trip delegation."

  use FirmowidWeb, :live_view

  import FirmowidWeb.Delegations.Components.Delegation
  import FirmowidWeb.Delegations.Components.Settlement
  import FirmowidWeb.DesignSystem.Components.Button
  import FirmowidWeb.DesignSystem.Components.CoreComponents, except: [button: 1]
  import Phoenix.Component, except: [link: 1]

  alias AshPhoenix.Form.Auto
  alias Firmowid.Ash.Currencies.NbpApiClient
  alias Firmowid.Ash.Delegations
  alias Firmowid.Ash.Delegations.DelegationExpense
  alias Firmowid.Ash.Delegations.DelegationExpenseExtractor
  alias FirmowidWeb.Delegations.Utilities.SettlementPresentation
  alias Phoenix.HTML.Form

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
    <div id="delegation-settlement" phx-hook="DelegationDateChange" class="relative mt-4">
      <.back
        navigate={~p"/ustawienia/profil"}
        class="absolute top-0 left-0.5 z-10 inline-flex text-sm"
      />
      <.form
        for={@complete_form}
        id="delegation-complete-form"
        phx-change={if @editable?, do: "validate"}
        phx-submit={if @editable?, do: "submit"}
        class="group relative grid gap-10 px-32 pr-34 pb-12 font-[340] lg:grid-cols-[auto_22.5rem]"
      >
        <.nested_hidden_inputs :if={@editable?} form={@complete_form} />
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
          <div :if={@editable?} class="relative mt-6 lg:mt-47">
            <div class="absolute -top-12 right-0 flex h-6 items-center justify-end">
              <span class="font-lexend text-grey-500 inline-flex items-center gap-1 text-[11px] font-medium uppercase group-[.phx-change-loading]:hidden">
                Zmiany zostały zapisane <.save_check_icon class="size-3" />
              </span>
              <span class="font-lexend text-grey-500 hidden items-center gap-1 text-[11px] font-medium uppercase group-[.phx-change-loading]:inline-flex">
                Zapisywanie zmian
                <Lucideicons.refresh_ccw class="size-3 animate-spin [animation-direction:reverse]" />
              </span>
            </div>
            <div class="rounded-lg bg-white px-6 py-4 shadow-sm">
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
                  <.summary_row
                    label="Pobrana zaliczka"
                    value={@delegation.advance_payment_amount}
                  />
                </div>
                <.summary_row label={@balance_label} value={@balance} />
              </dl>
            </div>
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
          <div :if={!@editable?} class="mt-6 rounded-lg bg-white px-6 py-4 shadow-sm lg:mt-47">
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
                <.summary_row
                  label="Pobrana zaliczka"
                  value={@delegation.advance_payment_amount}
                />
              </div>
              <.summary_row label={@balance_label} value={@balance} />
            </dl>
          </div>
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
    </div>
    """
  end

  @impl true
  def handle_event("upload", _params, socket), do: {:noreply, assign(socket, :uploading?, true)}

  def handle_event("upload-related-document", _params, socket), do: {:noreply, assign(socket, :uploading?, true)}

  def handle_event("upload-statement-document", _params, socket), do: {:noreply, assign(socket, :uploading?, true)}

  def handle_event("validate", %{"delegation" => params} = event_params, socket) do
    expense_currencies =
      Map.merge(
        socket.assigns.expense_currencies,
        Map.get(event_params, "expense_currencies", %{})
      )

    params = merge_expense_currencies(params, expense_currencies)

    date_change = detected_date_change(socket.assigns.delegation, params)

    params = transform_trip_datetimes(params, socket.assigns.timezone)

    form = validate_complete_form(socket.assigns.complete_form, params)

    {:noreply,
     socket
     |> assign(
       expense_currencies: expense_currencies,
       submission_failed?: false,
       date_change: date_change
     )
     |> assign_complete_form(form)}
  end

  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("foreign-currency-action", %{"action" => "notice", "expense-id" => expense_id}, socket) do
    {:noreply, update(socket, :foreign_currency_modes, &Map.delete(&1, expense_id))}
  end

  def handle_event("foreign-currency-action", %{"action" => "statement", "expense-id" => expense_id}, socket) do
    {:noreply, update(socket, :foreign_currency_modes, &Map.put(&1, expense_id, :statement))}
  end

  def handle_event("foreign-currency-action", %{"action" => "nbp", "expense-id" => expense_id}, socket) do
    case nbp_settlement(
           socket,
           expense_id,
           "PLN"
         ) do
      {:ok, settlement} ->
        {:noreply,
         socket
         |> update(:foreign_currency_modes, &Map.put(&1, expense_id, :nbp))
         |> update(:nbp_settlements, &Map.put(&1, expense_id, settlement))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Nie udało się pobrać kursu NBP.")}
    end
  end

  def handle_event("select-related-expense", %{"id" => expense_id}, socket),
    do: {:noreply, assign(socket, :related_expense_id, expense_id)}

  def handle_event("select-statement-expense", %{"id" => expense_id}, socket),
    do:
      {:noreply,
       socket |> assign(:statement_expense_id, expense_id) |> push_event("preserve-statement-upload-scroll", %{})}

  def handle_event("delete", %{"kind" => kind, "id" => id}, socket) do
    result = safely(fn -> destroy_expense(kind, id, socket.assigns.ash_scope) end)

    {:noreply,
     if(result == :ok,
       do: reload(socket),
       else: put_flash(socket, :error, "Nie udało się usunąć dokumentu.")
     )}
  end

  def handle_event("remove-related-document", %{"expense-id" => expense_id, "blob-id" => blob_id}, socket) do
    result =
      safely(fn ->
        with {:ok, expense} <- get_expense(nil, expense_id, socket.assigns.ash_scope),
             {:ok, _expense} <-
               Delegations.remove_related_document(expense, %{blob_id: blob_id}, scope: socket.assigns.ash_scope) do
          :ok
        end
      end)

    case result do
      :ok -> {:noreply, reload(socket)}
      _ -> {:noreply, put_flash(socket, :error, "Nie udało się usunąć powiązanego dokumentu.")}
    end
  end

  def handle_event("remove-statement-document", %{"expense-id" => expense_id}, socket) do
    result =
      safely(fn ->
        with {:ok, expense} <- get_expense(nil, expense_id, socket.assigns.ash_scope) do
          Delegations.remove_statement_document(expense, scope: socket.assigns.ash_scope)
        end
      end)

    case result do
      {:ok, _expense} -> {:noreply, refresh_delegation(socket)}
      _ -> {:noreply, put_flash(socket, :error, "Nie udało się usunąć wyciągu.")}
    end
  end

  def handle_event("show-description", %{"id" => id}, socket),
    do: {:noreply, update(socket, :description_visible?, &Map.put(&1, id, true))}

  def handle_event("hide-description", %{"id" => id}, socket),
    do: {:noreply, update(socket, :description_visible?, &Map.put(&1, id, false))}

  def handle_event("sort", _params, socket) do
    delegation =
      socket.assigns.delegation.id
      |> load_delegation!(socket)
      |> Map.update!(:expenses, &sort_transport_expenses/1)

    form = complete_form(delegation, socket.assigns.ash_scope, socket.assigns.timezone)

    {:noreply,
     socket
     |> assign(delegation: decorate_delegation(delegation, false), sort_active?: true)
     |> assign_complete_form(form)}
  end

  def handle_event("submit", _params, %{assigns: %{editable?: false}} = socket), do: {:noreply, socket}

  def handle_event("submit", _params, %{assigns: %{uploading?: true}} = socket), do: {:noreply, socket}

  def handle_event("submit", params, socket) do
    expense_currencies =
      Map.merge(socket.assigns.expense_currencies, Map.get(params, "expense_currencies", %{}))

    params =
      params
      |> Map.get("delegation", %{})
      |> merge_expense_currencies(expense_currencies)
      |> merge_foreign_currency_settlements(socket)

    date_change = detected_date_change(socket.assigns.delegation, params)

    params = transform_trip_datetimes(params, socket.assigns.timezone)

    case safely(fn -> AshPhoenix.Form.submit(socket.assigns.complete_form, params: params) end) do
      {:ok, delegation} ->
        {:noreply, setup_socket(socket, load_delegation!(delegation.id, socket))}

      {:error, %Form{} = complete_form} ->
        socket =
          socket
          |> assign(submission_failed?: true, date_change: date_change)
          |> assign_complete_form(complete_form)
          |> scroll_to_date_change(date_change)

        {:noreply, socket}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Nie udało się wysłać ewidencji.")}
    end
  end

  defp setup_socket(socket, delegation) do
    sort_active? = socket.assigns[:sort_active?] || false
    complete_form = complete_form(delegation, socket.assigns.ash_scope, socket.assigns.timezone)
    delegation = decorate_delegation(delegation, sort_active?)

    transport =
      if delegation.status == :complete,
        do: nil,
        else:
          allow_upload(socket, :transport,
            accept: ~w(.pdf .png .jpg .jpeg),
            max_entries: 1,
            auto_upload: true,
            progress: &handle_upload_progress/3
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
            auto_upload: true,
            progress: &handle_upload_progress/3
          )
          |> allow_upload(:other,
            accept: ~w(.pdf .png .jpg .jpeg),
            max_entries: 1,
            auto_upload: true,
            progress: &handle_upload_progress/3
          )
          |> allow_upload(:related_document,
            accept: ~w(.pdf .png .jpg .jpeg),
            max_entries: 1,
            auto_upload: true,
            progress: &handle_related_upload_progress/3
          )
          |> allow_upload(:statement_document,
            accept: ~w(.pdf .png .jpg .jpeg),
            max_entries: 1,
            auto_upload: true,
            progress: &handle_statement_upload_progress/3
          )

    socket
    |> assign(
      delegation: delegation,
      editable?: delegation.status == :in_progress,
      uploading?: false,
      submission_failed?: false,
      related_expense_id: nil,
      statement_expense_id: nil,
      page_title: "Rozliczenie delegacji",
      sort_active?: sort_active?,
      date_change: persisted_date_change(delegation),
      expense_currencies: expense_currencies(delegation.expenses),
      foreign_currency_modes: %{},
      nbp_settlements: %{}
    )
    |> assign_complete_form(complete_form)
    |> assign_new(:description_visible?, fn -> %{} end)
    |> assign_summary()
  end

  defp load_delegation(id, socket),
    do:
      Delegations.get_delegation(id,
        scope: socket.assigns.ash_scope,
        load: [expenses: [blob: [:url], statement_blob: [:url], related_blobs: [:url]]],
        not_found_error?: false
      )

  defp load_delegation!(id, socket), do: elem(load_delegation(id, socket), 1)

  defp reload(socket), do: setup_socket(socket, load_delegation!(socket.assigns.delegation.id, socket))

  defp refresh_delegation(socket) do
    delegation = load_delegation!(socket.assigns.delegation.id, socket)

    complete_form = complete_form(delegation, socket.assigns.ash_scope, socket.assigns.timezone)
    delegation = decorate_delegation(delegation, socket.assigns.sort_active?)

    socket
    |> assign(
      delegation: delegation,
      expense_currencies: Map.merge(expense_currencies(delegation.expenses), socket.assigns.expense_currencies)
    )
    |> assign_complete_form(complete_form)
    |> assign_summary()
  end

  defp decorate_delegation(delegation, sort_active?) do
    expenses =
      if sort_active?, do: sort_transport_expenses(delegation.expenses), else: delegation.expenses

    Map.put(delegation, :expenses, Enum.map(expenses, &decorate_expense/1))
  end

  defp decorate_expense(%{details: %Ash.Union{value: details}} = expense),
    do: decorate_expense(%{expense | details: details})

  defp decorate_expense(
         %{details: %{__struct__: Firmowid.Ash.Delegations.DelegationExpense.TransportDetails} = details} = expense
       ) do
    expense |> Map.put(:transport_type, details.transport_type) |> Map.put(:trips, details.trips)
  end

  defp decorate_expense(
         %{details: %{__struct__: Firmowid.Ash.Delegations.DelegationExpense.AccommodationDetails} = details} = expense
       ) do
    expense
    |> Map.put(:locality, details.locality)
    |> Map.put(:arrival_date, details.arrival_date)
    |> Map.put(:departure_date, details.departure_date)
    |> Map.put(:description, details.description)
  end

  defp decorate_expense(
         %{details: %{__struct__: Firmowid.Ash.Delegations.DelegationExpense.OtherDetails} = details} = expense
       ), do: Map.put(expense, :description, details.description)

  defp sort_transport_expenses(expenses) do
    Enum.sort_by(
      expenses,
      fn expense ->
        case Map.get(expense, :trips, []) do
          [%{departure_datetime: %DateTime{} = departure_datetime}] ->
            {0, DateTime.to_unix(departure_datetime, :microsecond), expense.inserted_at, expense.id}

          _ ->
            {1, 0, expense.inserted_at, expense.id}
        end
      end,
      :asc
    )
  end

  defp handle_upload_progress(_kind, %{done?: false}, socket), do: {:noreply, assign(socket, :uploading?, true)}

  defp handle_upload_progress(kind, entry, socket) do
    socket =
      case consume_uploaded_entry(socket, entry, fn %{path: path} ->
             {:ok,
              safely(fn ->
                create_expense(
                  kind,
                  socket.assigns.delegation.id,
                  entry.client_name,
                  entry.client_type,
                  path,
                  socket.assigns.delegation.start_date,
                  socket.assigns.delegation.end_date,
                  socket.assigns.ash_scope
                )
              end)}
           end) do
        {:ok, _expense} -> refresh_delegation(socket)
        {:error, _reason} -> put_flash(socket, :error, "Nie udało się dodać dokumentu.")
      end

    {:noreply, assign(socket, :uploading?, uploads_in_progress?(socket))}
  end

  defp handle_statement_upload_progress(_kind, %{done?: false}, socket), do: {:noreply, assign(socket, :uploading?, true)}

  defp handle_statement_upload_progress(_kind, entry, socket) do
    expense_id = socket.assigns.statement_expense_id

    socket =
      case consume_statement_document(socket, entry, expense_id) do
        {:ok, _expense} ->
          socket |> refresh_delegation() |> assign(:statement_expense_id, nil)

        {:error, _reason} ->
          socket
          |> assign(:statement_expense_id, nil)
          |> put_flash(:error, "Nie udało się dodać wyciągu.")
      end

    {:noreply, assign(socket, :uploading?, uploads_in_progress?(socket))}
  end

  defp handle_related_upload_progress(_kind, %{done?: false}, socket), do: {:noreply, assign(socket, :uploading?, true)}

  defp handle_related_upload_progress(_kind, entry, socket) do
    expense_id = socket.assigns.related_expense_id

    socket =
      case consume_related_document(socket, entry, expense_id) do
        {:ok, _expense} ->
          socket |> refresh_delegation() |> assign(:related_expense_id, nil)

        {:error, _reason} ->
          socket
          |> assign(:related_expense_id, nil)
          |> put_flash(:error, "Nie udało się dodać powiązanego dokumentu.")
      end

    {:noreply, assign(socket, :uploading?, uploads_in_progress?(socket))}
  end

  defp consume_related_document(socket, entry, expense_id) when is_binary(expense_id) do
    consume_uploaded_entry(socket, entry, fn %{path: path} ->
      {:ok,
       safely(fn ->
         with {:ok, expense} <- get_expense(nil, expense_id, socket.assigns.ash_scope) do
           Delegations.add_related_document(
             expense,
             %{
               upload_path: path,
               content_type: entry.client_type,
               original_filename: entry.client_name
             },
             scope: socket.assigns.ash_scope
           )
         end
       end)}
    end)
  end

  defp consume_related_document(socket, entry, _expense_id) do
    consume_uploaded_entry(socket, entry, fn _meta -> {:ok, {:error, :expense_not_selected}} end)
  end

  defp consume_statement_document(socket, entry, expense_id) when is_binary(expense_id) do
    consume_uploaded_entry(socket, entry, fn %{path: path} ->
      {:ok,
       safely(fn ->
         with {:ok, expense} <- get_expense(nil, expense_id, socket.assigns.ash_scope) do
           Delegations.add_statement_document(
             expense,
             %{
               upload_path: path,
               content_type: entry.client_type,
               original_filename: entry.client_name
             },
             scope: socket.assigns.ash_scope
           )
         end
       end)}
    end)
  end

  defp consume_statement_document(socket, entry, _expense_id) do
    consume_uploaded_entry(socket, entry, fn _meta -> {:ok, {:error, :expense_not_selected}} end)
  end

  defp create_expense(kind, id, filename, content_type, path, start_date, end_date, scope) do
    with {:ok, extracted_details} <-
           DelegationExpenseExtractor.extract(
             path,
             kind,
             start_date,
             end_date
           ) do
      create_expense_form(id, filename, content_type, path, kind, extracted_details, scope)
    end
  end

  defp create_expense_form(id, filename, content_type, path, kind, extracted_details, scope) do
    DelegationExpense
    |> AshPhoenix.Form.for_create(:create,
      scope: scope,
      params: %{"details" => %{"_union_type" => type_name(kind)}}
    )
    |> AshPhoenix.Form.submit(
      params:
        Map.merge(
          %{
            delegation_id: id,
            kind: kind,
            original_filename: filename,
            document_number: "",
            expense_amount: Money.new(:PLN, 0),
            upload_path: path,
            content_type: content_type,
            details: Map.put(initial_expense_details(kind), "_union_type", type_name(kind))
          },
          extracted_details
        )
    )
  end

  defp initial_expense_details(:transport), do: %{type: "transport", transport_type: :other, trips: []}

  defp initial_expense_details(:accommodation), do: %{type: "accommodation", locality: ""}

  defp initial_expense_details(:other), do: %{type: "other", description: ""}

  defp type_name(kind), do: Atom.to_string(kind)

  defp destroy_expense(kind, id, scope) do
    with {:ok, expense} <- get_expense(kind, id, scope) do
      _ = kind
      Delegations.destroy_expense(expense, scope: scope)
    end
  end

  defp get_expense(_kind, id, scope), do: Delegations.get_expense(id, scope: scope, not_found_error?: false)

  defp complete_form(delegation, scope, timezone) do
    forms =
      Firmowid.Ash.Delegations.Delegation
      |> Auto.auto(:complete)
      |> Enum.map(fn {key, config} ->
        config =
          config |> Keyword.fetch!(:updater) |> then(& &1.(config)) |> Keyword.delete(:updater)

        config =
          if key == :expenses do
            Keyword.put(config, :transform_params, fn params, _type ->
              transform_expense_params(params, timezone)
            end)
          else
            config
          end

        {key, config}
      end)

    delegation
    |> AshPhoenix.Form.for_update(:complete,
      scope: scope,
      as: "delegation",
      forms: forms
    )
    |> to_form()
  end

  defp assign_complete_form(socket, form) do
    expense_forms =
      [:expenses]
      |> Enum.flat_map(&nested_forms(form, &1))
      |> Map.new(&{&1.data.id, %{expense: &1, details: nested_form(&1, :details)}})

    trip_forms =
      expense_forms
      |> Map.values()
      |> Enum.flat_map(&nested_forms(&1.details, :trips))
      |> Map.new(&{&1.data.id, &1})

    assign(socket, complete_form: form, expense_forms: expense_forms, trip_forms: trip_forms)
  end

  defp nested_forms(%Form{source: source}, field) do
    source.forms
    |> Map.get(field, [])
    |> List.wrap()
    |> Enum.map(&to_form/1)
  end

  defp nested_form(%Form{source: %{forms: forms}}, field), do: forms |> Map.fetch!(field) |> to_form()

  attr :form, Form, required: true

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

  defp uploads_in_progress?(socket) do
    Enum.any?(
      [:transport, :accommodation, :other, :related_document, :statement_document],
      fn name ->
        {_completed, in_progress} = uploaded_entries(socket, name)
        in_progress != []
      end
    )
  end

  defp transform_expense_params(%{"kind" => kind} = params, _timezone) do
    details =
      case kind do
        "transport" ->
          %{
            "type" => kind,
            "transport_type" => params["transport_type"] || "other",
            "trips" => []
          }

        "accommodation" ->
          params
          |> Map.take(["locality", "arrival_date", "departure_date", "description"])
          |> Map.put("type", kind)

        "other" ->
          params |> Map.take(["description"]) |> Map.put("type", kind)
      end

    params
    |> Map.take([
      "id",
      "_form_type",
      "document_number",
      "expense_amount",
      "expense_currency",
      "settlement_method",
      "settlement_amount",
      "settlement_currency",
      "nbp_rate",
      "nbp_rate_date"
    ])
    |> normalize_expense_amount()
    |> normalize_settlement_amount()
    |> Map.put("details", details)
  end

  defp transform_expense_params(%{"details" => details} = params, _timezone) do
    params
    |> Map.take([
      "id",
      "_form_type",
      "document_number",
      "expense_amount",
      "expense_currency",
      "settlement_method",
      "settlement_amount",
      "settlement_currency",
      "nbp_rate",
      "nbp_rate_date"
    ])
    |> normalize_expense_amount()
    |> normalize_settlement_amount()
    |> Map.put("details", details)
  end

  defp normalize_expense_amount(params) do
    currency = Map.get(params, "expense_currency")

    params
    |> Map.delete("expense_currency")
    |> Map.update("expense_amount", nil, fn
      %{"amount" => _amount} = amount ->
        if currency, do: Map.put(amount, "currency", currency), else: amount

      amount ->
        %{"amount" => amount, "currency" => currency || "PLN"}
    end)
  end

  defp normalize_settlement_amount(params) do
    currency = Map.get(params, "settlement_currency")

    params
    |> Map.delete("settlement_currency")
    |> Map.update("settlement_amount", nil, fn
      %{"amount" => _amount} = amount ->
        if currency, do: Map.put(amount, "currency", currency), else: amount

      amount ->
        %{"amount" => amount, "currency" => currency || "PLN"}
    end)
  end

  defp expense_currencies(expenses) do
    Map.new(expenses, fn expense ->
      currency = expense.expense_amount |> Money.to_currency_code() |> Atom.to_string()
      {expense.id, currency}
    end)
  end

  defp merge_foreign_currency_settlements(params, socket) do
    Map.update(params, "expenses", %{}, fn expenses ->
      Map.new(expenses, fn {index, expense} ->
        expense_id = expense["id"]

        expense =
          case Map.get(socket.assigns.foreign_currency_modes, expense_id) do
            :statement ->
              expense
              |> Map.put("settlement_method", "statement")
              |> Map.put("settlement_currency", "PLN")

            :nbp ->
              case Map.get(socket.assigns.nbp_settlements, expense_id) do
                %{amount: amount, rate: rate, date: date} ->
                  expense
                  |> Map.put("settlement_method", "nbp")
                  |> Map.put(
                    "settlement_amount",
                    Decimal.to_string(Money.to_decimal(amount), :normal)
                  )
                  |> Map.put("settlement_currency", "PLN")
                  |> Map.put("nbp_rate", Decimal.to_string(rate, :normal))
                  |> Map.put("nbp_rate_date", Date.to_iso8601(date))

                nil ->
                  expense
              end

            _ ->
              expense
          end

        {index, expense}
      end)
    end)
  end

  defp nbp_settlement(socket, expense_id, target_currency) do
    with true <- target_currency == "PLN" or NbpApiClient.supported_currency?(target_currency),
         %{expense: form} <- Map.fetch!(socket.assigns.expense_forms, expense_id),
         %Money{} = amount <- form[:expense_amount].value,
         source_currency = Map.get(socket.assigns.expense_currencies, expense_id, "PLN"),
         date = nbp_conversion_date(),
         {:ok, source_rate} <- nbp_rate(source_currency, date),
         {:ok, target_rate} <- nbp_rate(target_currency, date) do
      rate = source_rate |> Decimal.div(target_rate) |> Decimal.round(4)

      {:ok,
       %{
         amount: Money.new(target_currency, Decimal.mult(Money.to_decimal(amount), rate)),
         rate: rate,
         date: date
       }}
    else
      _ -> {:error, :rate_unavailable}
    end
  end

  # Kept separate because the purchase-date rule will be configurable later.
  defp nbp_conversion_date, do: Date.utc_today()

  defp nbp_rate("PLN", _date), do: {:ok, Decimal.new(1)}

  defp nbp_rate(currency, date) do
    case NbpApiClient.get_exchange_rate(currency, date) do
      {:ok, %{rate: rate}} -> {:ok, Decimal.from_float(rate)}
      {:error, _reason} -> {:error, :rate_unavailable}
    end
  end

  defp merge_expense_currencies(params, expense_currencies) do
    Map.update(params, "expenses", %{}, fn expenses ->
      Map.new(expenses, fn {index, expense} ->
        {index, Map.put(expense, "expense_currency", Map.get(expense_currencies, expense["id"], "PLN"))}
      end)
    end)
  end

  defp transform_trip_datetimes(params, timezone) when is_map(params) do
    params =
      Map.new(params, fn {key, value} -> {key, transform_trip_datetimes(value, timezone)} end)

    if Map.has_key?(params, "departure_time") || Map.has_key?(params, "arrival_time") do
      params
      |> put_trip_datetime("departure", timezone)
      |> put_trip_datetime("arrival", timezone)
      |> Map.drop(["departure_date", "departure_time", "arrival_date", "arrival_time"])
    else
      params
    end
  end

  defp transform_trip_datetimes(params, timezone) when is_list(params),
    do: Enum.map(params, &transform_trip_datetimes(&1, timezone))

  defp transform_trip_datetimes(params, _timezone), do: params

  defp put_trip_datetime(params, prefix, timezone) do
    with date when is_binary(date) <- params["#{prefix}_date"],
         time when is_binary(time) <- params["#{prefix}_time"],
         {:ok, date} <- Date.from_iso8601(date),
         {:ok, time} <- Time.from_iso8601(time <> ":00"),
         {:ok, datetime} <- DateTime.new(date, time, timezone) do
      datetime = DateTime.shift_zone!(datetime, "Etc/UTC")
      Map.put(params, "#{prefix}_datetime", DateTime.to_iso8601(datetime))
    else
      _ -> params
    end
  end

  defp assign_summary(socket) do
    total = SettlementPresentation.sum(socket.assigns.delegation.expenses)

    advance = socket.assigns.delegation.advance_payment_amount
    {label, balance} = SettlementPresentation.settlement_balance(total, advance)

    assign(socket,
      total: total,
      balance_label: label,
      balance: balance
    )
  end

  defp detected_date_change(delegation, params) do
    case dates_from_params(params) do
      [] -> persisted_date_change(delegation)
      dates -> date_change(delegation, dates)
    end
  end

  defp dates_from_params(params) do
    params
    |> Enum.flat_map(&dates_from_param/1)
    |> Enum.reject(&is_nil/1)
  end

  defp dates_from_param({key, value}) when key in ["arrival_date", "departure_date"], do: [date_from_param(value)]

  defp dates_from_param({_key, value}) when is_map(value), do: Enum.flat_map(value, &dates_from_param/1)

  defp dates_from_param({_key, value}) when is_list(value), do: Enum.flat_map(value, &dates_from_value/1)

  defp dates_from_param({_key, _value}), do: []

  defp dates_from_value(value) when is_map(value), do: Enum.flat_map(value, &dates_from_param/1)
  defp dates_from_value(_value), do: []

  defp date_from_param(%Date{} = date), do: date

  defp date_from_param(date) when is_binary(date) do
    case Date.from_iso8601(date) do
      {:ok, date} -> date
      {:error, _reason} -> nil
    end
  end

  defp date_from_param(_date), do: nil

  defp date_change(delegation, dates) do
    earliest_date = Enum.min_by(dates, &Date.to_iso8601/1)
    latest_date = Enum.max_by(dates, &Date.to_iso8601/1)

    date_change = %{
      detected_start_date: if(Date.before?(earliest_date, delegation.start_date), do: earliest_date),
      detected_end_date: if(Date.after?(latest_date, delegation.end_date), do: latest_date)
    }

    if date_change.detected_start_date || date_change.detected_end_date, do: date_change
  end

  defp persisted_date_change(delegation) do
    if delegation.detected_start_date || delegation.detected_end_date do
      %{
        detected_start_date: delegation.detected_start_date,
        detected_end_date: delegation.detected_end_date
      }
    end
  end

  defp scroll_to_date_change(socket, date_change) when is_map(date_change),
    do: push_event(socket, "scroll-to-date-change", %{})

  defp scroll_to_date_change(socket, nil), do: socket

  defp validate_complete_form(form, params), do: AshPhoenix.Form.validate(form, params)

  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(nil), do: true
  defp blank?(_value), do: false

  attr :delegation, :map, required: true
  attr :date_change, :map, required: true
  attr :form, Form, required: true
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
          <span class="text-grey-500 line-through">
            <.date_range
              start_date={@delegation.start_date}
              end_date={@delegation.end_date}
            />
          </span>
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

  defp safely(fun) do
    fun.()
  rescue
    exception -> {:error, exception}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

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
      <path d="M7 3v4a1 1 0 0 0 1 1h7" />
    </svg>
    """
  end
end
