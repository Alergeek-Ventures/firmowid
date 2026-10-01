defmodule FirmowidWeb.Delegations.Views.Delegation do
  @moduledoc "Settlement page for an approved business trip delegation."

  use FirmowidWeb, :live_view

  import FirmowidWeb.Delegations.Components.SettlementPage

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

      {:error, _reason} ->
        {:ok, push_navigate(socket, to: ~p"/ustawienia/profil")}
    end
  end

  @impl true
  def render(assigns) do
    settlement_page(assigns)
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
      :ok -> {:noreply, refresh_delegation(socket, preserve_form?: true)}
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
      {:ok, _expense} -> {:noreply, refresh_delegation(socket, preserve_form?: true)}
      _ -> {:noreply, put_flash(socket, :error, "Nie udało się usunąć wyciągu.")}
    end
  end

  def handle_event("show-description", %{"id" => id}, socket),
    do: {:noreply, update(socket, :description_visible?, &Map.put(&1, id, true))}

  def handle_event("hide-description", %{"id" => id}, socket),
    do: {:noreply, update(socket, :description_visible?, &Map.put(&1, id, false))}

  def handle_event("sort", _params, socket) do
    case load_delegation(socket.assigns.delegation.id, socket) do
      {:ok, delegation} when not is_nil(delegation) ->
        delegation = Map.update!(delegation, :expenses, &sort_transport_expenses/1)
        form = complete_form(delegation, socket.assigns.ash_scope, socket.assigns.timezone)

        {:noreply,
         socket
         |> assign(delegation: decorate_delegation(delegation, false), sort_active?: true)
         |> assign_complete_form(form)}

      _ ->
        {:noreply, unavailable_delegation(socket)}
    end
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
        {:noreply, reload(socket, delegation.id)}

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

  defp reload(socket, id \\ nil) do
    case load_delegation(id || socket.assigns.delegation.id, socket) do
      {:ok, delegation} when not is_nil(delegation) -> setup_socket(socket, delegation)
      _ -> unavailable_delegation(socket)
    end
  end

  defp refresh_delegation(socket, options \\ []) do
    case load_delegation(socket.assigns.delegation.id, socket) do
      {:ok, delegation} when not is_nil(delegation) ->
        complete_form =
          complete_form(delegation, socket.assigns.ash_scope, socket.assigns.timezone)

        complete_form =
          if Keyword.get(options, :preserve_form?, false) do
            validate_complete_form(complete_form, socket.assigns.complete_form.source.raw_params)
          else
            complete_form
          end

        delegation = decorate_delegation(delegation, socket.assigns.sort_active?)

        socket
        |> assign(
          delegation: delegation,
          expense_currencies: Map.merge(expense_currencies(delegation.expenses), socket.assigns.expense_currencies)
        )
        |> assign_complete_form(complete_form)
        |> assign_summary()

      _ ->
        unavailable_delegation(socket)
    end
  end

  defp unavailable_delegation(socket) do
    socket
    |> put_flash(:error, "Nie można już wyświetlić tej delegacji.")
    |> push_navigate(to: ~p"/ustawienia/profil")
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
          socket |> refresh_delegation(preserve_form?: true) |> assign(:statement_expense_id, nil)

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
          socket |> refresh_delegation(preserve_form?: true) |> assign(:related_expense_id, nil)

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

  defp safely(fun) do
    fun.()
  rescue
    exception -> {:error, exception}
  catch
    kind, reason -> {:error, {kind, reason}}
  end
end
