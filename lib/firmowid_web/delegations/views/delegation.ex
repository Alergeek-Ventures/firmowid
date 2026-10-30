defmodule FirmowidWeb.Delegations.Views.Delegation do
  @moduledoc "Settlement page for an approved business trip delegation."

  use FirmowidWeb, :live_view

  import FirmowidWeb.Delegations.Components.SettlementPage
  import FirmowidWeb.Delegations.Components.SettlementSignaturePage

  alias Firmowid.Delegations
  alias Firmowid.Delegations.DelegationExpense
  alias Firmowid.Delegations.DelegationExpense.Trip
  alias Firmowid.Delegations.DelegationExpenseExtractor
  alias Firmowid.Delegations.PerDiem
  alias FirmowidWeb.Delegations.Utilities.NbpSettlement
  alias FirmowidWeb.Delegations.Utilities.SettlementDocument
  alias FirmowidWeb.Delegations.Utilities.SettlementForm
  alias FirmowidWeb.Delegations.Utilities.SettlementPresentation
  alias Phoenix.HTML.Form

  @impl true
  def mount(%{"reference" => reference}, _session, socket) do
    case load_delegation(reference, socket) do
      {:ok, nil} ->
        {:ok, push_navigate(socket, to: ~p"/ustawienia/profil")}

      {:ok, delegation} ->
        if delegation.status in [:in_progress, :awaiting_signature, :submitted, :complete] do
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
    if assigns.delegation.status == :awaiting_signature,
      do: settlement_signature_page(assigns),
      else: settlement_page(assigns)
  end

  def handle_event("validate-signed-settlement", _params, socket), do: {:noreply, socket}

  def handle_event("cancel-signed-settlement", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :signed_settlement, ref)}
  end

  def handle_event("edit-settlement", _params, socket) do
    socket =
      Enum.reduce(socket.assigns.uploads.signed_settlement.entries, socket, fn entry, socket ->
        cancel_upload(socket, :signed_settlement, entry.ref)
      end)

    case Delegations.edit_settlement(socket.assigns.delegation.id,
           scope: socket.assigns.ash_scope
         ) do
      {:ok, delegation} ->
        {:noreply, reload(socket, delegation.reference)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Nie udało się wrócić do edycji.")}
    end
  end

  def handle_event("submit-for-review", _params, %{assigns: %{submitting?: true}} = socket), do: {:noreply, socket}

  def handle_event("submit-for-review", _params, socket) do
    socket = assign(socket, :submitting?, true)

    result =
      consume_uploaded_entries(socket, :signed_settlement, fn %{path: path}, entry ->
        case Delegations.submit_for_review(
               socket.assigns.delegation.id,
               %{
                 upload_path: path,
                 content_type: entry.client_type,
                 original_filename: entry.client_name
               },
               scope: socket.assigns.ash_scope
             ) do
          {:ok, delegation} -> {:ok, {:ok, delegation}}
          {:error, reason} -> {:postpone, {:error, reason}}
        end
      end)

    case result do
      [{:ok, _delegation}] ->
        {:noreply,
         socket
         |> put_flash(:info, "Rozliczenie zostało wysłane do rozpatrzenia.")
         |> push_navigate(to: ~p"/ustawienia/profil")}

      [] ->
        {:noreply,
         socket
         |> assign(:submitting?, false)
         |> put_flash(:error, "Wgraj podpisane rozliczenie w formacie PDF.")}

      _errors ->
        {:noreply,
         socket
         |> assign(:submitting?, false)
         |> put_flash(:error, "Nie udało się wysłać rozliczenia. Spróbuj ponownie.")}
    end
  end

  @impl true
  def handle_event("upload", _params, socket), do: {:noreply, assign(socket, :uploading?, true)}

  def handle_event("upload-related-document", _params, socket), do: {:noreply, assign(socket, :uploading?, true)}

  def handle_event("upload-statement-document", _params, socket), do: {:noreply, assign(socket, :uploading?, true)}

  def handle_event("validate", _params, %{assigns: %{editable?: false}} = socket), do: {:noreply, socket}

  def handle_event("validate", %{"delegation" => params} = event_params, socket) do
    expense_currencies =
      Map.merge(
        socket.assigns.expense_currencies,
        Map.get(event_params, "expense_currencies", %{})
      )

    params =
      params
      |> SettlementForm.merge_expense_currencies(expense_currencies)
      |> SettlementForm.merge_foreign_currency_settlements(
        socket.assigns.foreign_currency_modes,
        socket.assigns.nbp_settlements
      )

    date_change = detected_date_change(socket.assigns.delegation, params)

    {:noreply,
     socket
     |> assign(
       expense_currencies: expense_currencies,
       submission_failed?: false,
       date_change: date_change
     )
     |> save_draft(params, Map.get(event_params, "draft_revision"))}
  end

  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("foreign-currency-action", %{"action" => "notice", "expense-id" => expense_id}, socket) do
    {:noreply,
     socket
     |> update(:foreign_currency_modes, &Map.delete(&1, expense_id))
     |> save_current_draft()}
  end

  def handle_event("foreign-currency-action", %{"action" => "statement", "expense-id" => expense_id}, socket) do
    {:noreply,
     socket
     |> update(:foreign_currency_modes, &Map.put(&1, expense_id, :statement))
     |> save_current_draft()}
  end

  def handle_event("foreign-currency-action", %{"action" => "nbp", "expense-id" => expense_id}, socket) do
    case NbpSettlement.calculate(
           socket.assigns.expense_forms,
           socket.assigns.expense_currencies,
           expense_id,
           "PLN"
         ) do
      {:ok, settlement} ->
        {:noreply,
         socket
         |> update(:foreign_currency_modes, &Map.put(&1, expense_id, :nbp))
         |> update(:nbp_settlements, &Map.put(&1, expense_id, settlement))
         |> save_current_draft()}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not fetch the NBP exchange rate."))}
    end
  end

  def handle_event("select-related-expense", %{"id" => expense_id}, socket),
    do: {:noreply, assign(socket, :related_expense_id, expense_id)}

  def handle_event("select-statement-expense", %{"id" => expense_id}, socket),
    do:
      {:noreply,
       socket |> assign(:statement_expense_id, expense_id) |> push_event("preserve-statement-upload-scroll", %{})}

  def handle_event("delete", %{"kind" => kind, "id" => id}, socket) do
    result = destroy_expense(kind, id, socket.assigns.ash_scope)

    {:noreply,
     if(result == :ok,
       do: refresh_delegation(socket),
       else: put_flash(socket, :error, gettext("Could not delete the document."))
     )}
  end

  def handle_event("remove-related-document", %{"expense-id" => expense_id, "blob-id" => blob_id}, socket) do
    result =
      with {:ok, expense} <- get_expense(nil, expense_id, socket.assigns.ash_scope),
           {:ok, _expense} <-
             Delegations.remove_related_document(expense, %{blob_id: blob_id}, scope: socket.assigns.ash_scope) do
        :ok
      end

    case result do
      :ok ->
        {:noreply, refresh_delegation(socket)}

      _ ->
        {:noreply, put_flash(socket, :error, gettext("Could not remove the related document."))}
    end
  end

  def handle_event("remove-statement-document", %{"expense-id" => expense_id}, socket) do
    result =
      with {:ok, expense} <- get_expense(nil, expense_id, socket.assigns.ash_scope) do
        Delegations.remove_statement_document(expense, scope: socket.assigns.ash_scope)
      end

    case result do
      {:ok, _expense} -> {:noreply, refresh_delegation(socket)}
      _ -> {:noreply, put_flash(socket, :error, gettext("Could not remove the statement."))}
    end
  end

  def handle_event("show-description", %{"id" => id}, socket),
    do: {:noreply, update(socket, :description_visible?, &Map.put(&1, id, true))}

  def handle_event("hide-description", %{"id" => id}, socket),
    do: {:noreply, update(socket, :description_visible?, &Map.put(&1, id, false))}

  def handle_event("sort", _params, socket) do
    # Reorder the presentation only: nested form indexes and unfinished inputs keep their identity.
    {:noreply,
     assign(socket,
       delegation: decorate_delegation(socket.assigns.delegation, true),
       sort_active?: true
     )}
  end

  def handle_event("submit", _params, %{assigns: %{editable?: false}} = socket), do: {:noreply, socket}

  def handle_event("submit", _params, %{assigns: %{uploading?: true}} = socket), do: {:noreply, socket}

  def handle_event("submit", params, socket) do
    expense_currencies =
      Map.merge(socket.assigns.expense_currencies, Map.get(params, "expense_currencies", %{}))

    params =
      params
      |> Map.get("delegation", %{})
      |> SettlementForm.merge_expense_currencies(expense_currencies)
      |> SettlementForm.merge_foreign_currency_settlements(
        socket.assigns.foreign_currency_modes,
        socket.assigns.nbp_settlements
      )

    date_change = detected_date_change(socket.assigns.delegation, params)

    with {:ok, delegation} when not is_nil(delegation) <-
           load_delegation(socket.assigns.delegation.reference, socket),
         true <- delegation.status == :in_progress,
         complete_form = SettlementForm.complete_form(delegation, socket.assigns.ash_scope),
         false <- SettlementForm.stale_params?(complete_form, params) do
      case AshPhoenix.Form.submit(complete_form, params: params) do
        {:ok, delegation} ->
          {:noreply, reload(socket, delegation.reference)}

        {:error, %Form{} = complete_form} ->
          socket =
            socket
            |> assign(submission_failed?: true, date_change: date_change, save_status: :invalid)
            |> assign_complete_form(complete_form)
            |> scroll_to_date_change(date_change)

          {:noreply, socket}
      end
    else
      _ ->
        {:noreply, socket |> assign(:submission_failed?, true) |> assign_failed_draft(params)}
    end
  end

  defp setup_socket(socket, delegation) do
    if delegation.status == :awaiting_signature,
      do: setup_signature_socket(socket, delegation),
      else: setup_editor_socket(socket, delegation)
  end

  defp setup_signature_socket(socket, delegation) do
    delegation = decorate_delegation(delegation, false)
    document = SettlementDocument.build(delegation, nil, nil)

    socket
    |> allow_upload(:signed_settlement,
      accept: ~w(.pdf),
      max_entries: 1,
      max_file_size: 10 * 1024 * 1024,
      auto_upload: true,
      progress: &handle_signed_upload_progress/3
    )
    |> assign(
      delegation: delegation,
      document: document,
      submitting?: false,
      page_title: "Podpisz rozliczenie delegacji"
    )
  end

  defp setup_editor_socket(socket, delegation) do
    sort_active? = socket.assigns[:sort_active?] || false
    # Closed settlements show only the saved trip times, as their document and the review do.
    delegation =
      if delegation.status == :in_progress,
        do: SettlementForm.prefill_trip_times(delegation),
        else: delegation

    complete_form =
      SettlementForm.complete_form(
        delegation,
        socket.assigns.ash_scope,
        :save_draft
      )

    delegation = decorate_delegation(delegation, sort_active?)

    transport =
      if delegation.status == :in_progress,
        do:
          allow_upload(socket, :transport,
            accept: ~w(.pdf .png .jpg .jpeg),
            max_entries: 1,
            auto_upload: true,
            progress: &handle_upload_progress/3
          )

    socket = if transport, do: transport, else: socket

    socket =
      if delegation.status == :in_progress do
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
      else
        socket
      end

    socket
    |> assign(
      delegation: delegation,
      editable?: delegation.status == :in_progress,
      uploading?: false,
      submission_failed?: false,
      save_status: :idle,
      related_expense_id: nil,
      statement_expense_id: nil,
      page_title: gettext("Business trip settlement"),
      sort_active?: sort_active?,
      date_change: persisted_date_change(delegation),
      expense_currencies: expense_currencies(delegation.expenses),
      foreign_currency_modes: foreign_currency_modes(delegation.expenses),
      nbp_settlements: nbp_settlements(delegation.expenses)
    )
    |> assign_complete_form(complete_form)
    |> assign_new(:description_visible?, fn -> %{} end)
    |> assign_summary()
  end

  defp load_delegation(reference, socket),
    do:
      Delegations.get_delegation_by_reference(reference,
        scope: socket.assigns.ash_scope,
        load: [expenses: [blob: [:url], statement_blob: [:url], related_blobs: [:url]]],
        not_found_error?: false
      )

  defp save_draft(socket, params, revision) do
    with {:ok, delegation} when not is_nil(delegation) <-
           load_delegation(socket.assigns.delegation.reference, socket),
         true <- delegation.status == :in_progress,
         form =
           SettlementForm.complete_form(
             delegation,
             socket.assigns.ash_scope,
             :save_draft
           ),
         false <- SettlementForm.stale_params?(form, params),
         {:ok, _saved} <- AshPhoenix.Form.submit(form, params: params),
         {:ok, persisted} when not is_nil(persisted) <-
           load_delegation(delegation.reference, socket) do
      form = SettlementForm.complete_form(persisted, socket.assigns.ash_scope, :save_draft)

      socket
      |> assign(
        delegation: preserve_expense_order(persisted, socket.assigns.delegation),
        foreign_currency_modes: foreign_currency_modes(persisted.expenses),
        nbp_settlements: nbp_settlements(persisted.expenses),
        save_status: :saved
      )
      |> assign_complete_form(form)
      |> assign_summary()
      |> push_event("settlement-saved", %{revision: revision})
    else
      {:error, %Form{} = form} ->
        socket |> assign(:save_status, :invalid) |> assign_complete_form(form)

      _ ->
        assign_failed_draft(socket, params)
    end
  end

  defp assign_failed_draft(socket, params) do
    socket = assign(socket, :save_status, :error)

    if SettlementForm.stale_params?(socket.assigns.complete_form, params) do
      socket
    else
      form = AshPhoenix.Form.validate(socket.assigns.complete_form, params)
      assign_complete_form(socket, form)
    end
  end

  defp save_current_draft(socket) do
    params =
      socket.assigns.complete_form
      |> SettlementForm.preserve_expense_params(socket.assigns.complete_form.source.raw_params)
      |> SettlementForm.merge_expense_currencies(socket.assigns.expense_currencies)
      |> SettlementForm.merge_foreign_currency_settlements(
        socket.assigns.foreign_currency_modes,
        socket.assigns.nbp_settlements
      )

    save_draft(socket, params, nil)
  end

  defp reload(socket, reference) do
    case load_delegation(reference, socket) do
      {:ok, delegation} when not is_nil(delegation) -> setup_socket(socket, delegation)
      _ -> unavailable_delegation(socket)
    end
  end

  defp refresh_delegation(socket) do
    case load_delegation(socket.assigns.delegation.reference, socket) do
      {:ok, delegation} when not is_nil(delegation) ->
        # A newly added ticket can suggest the trip times that are still empty.
        delegation = SettlementForm.prefill_trip_times(delegation)

        complete_form =
          SettlementForm.complete_form(
            delegation,
            socket.assigns.ash_scope,
            :save_draft
          )

        params =
          SettlementForm.preserve_expense_params(
            complete_form,
            SettlementForm.drop_blank_trip_times(socket.assigns.complete_form.source.raw_params)
          )

        if SettlementForm.stale_params?(complete_form, params) do
          assign_failed_draft(socket, params)
        else
          complete_form = AshPhoenix.Form.validate(complete_form, params)
          delegation = preserve_expense_order(delegation, socket.assigns.delegation)

          socket
          |> assign(
            delegation: delegation,
            expense_currencies:
              Map.merge(
                expense_currencies(delegation.expenses),
                socket.assigns.expense_currencies
              )
          )
          |> assign_complete_form(complete_form)
          |> assign_summary()
        end

      _ ->
        unavailable_delegation(socket)
    end
  end

  defp unavailable_delegation(socket) do
    socket
    |> put_flash(:error, gettext("This business trip can no longer be displayed."))
    |> push_navigate(to: ~p"/ustawienia/profil")
  end

  defp decorate_delegation(delegation, sort_active?) do
    expenses =
      if sort_active?, do: sort_transport_expenses(delegation.expenses), else: delegation.expenses

    Map.put(delegation, :expenses, Enum.map(expenses, &decorate_expense/1))
  end

  defp preserve_expense_order(delegation, previous) do
    order =
      previous.expenses
      |> Enum.with_index()
      |> Map.new(fn {expense, index} -> {expense.id, index} end)

    delegation
    |> Map.update!(
      :expenses,
      &Enum.sort_by(&1, fn expense -> Map.get(order, expense.id, map_size(order)) end)
    )
    |> decorate_delegation(false)
  end

  defp decorate_expense(%{details: %Ash.Union{value: details}} = expense),
    do: decorate_expense(%{expense | details: details})

  defp decorate_expense(
         %{details: %{__struct__: Firmowid.Delegations.DelegationExpense.TransportDetails} = details} = expense
       ) do
    expense |> Map.put(:transport_type, details.transport_type) |> Map.put(:trips, details.trips)
  end

  defp decorate_expense(
         %{details: %{__struct__: Firmowid.Delegations.DelegationExpense.AccommodationDetails} = details} = expense
       ) do
    expense
    |> Map.put(:locality, details.locality)
    |> Map.put(:arrival_date, details.arrival_date)
    |> Map.put(:departure_date, details.departure_date)
    |> Map.put(:description, details.description)
  end

  defp decorate_expense(
         %{details: %{__struct__: Firmowid.Delegations.DelegationExpense.OtherDetails} = details} = expense
       ), do: Map.put(expense, :description, details.description)

  defp sort_transport_expenses(expenses) do
    Enum.sort_by(
      expenses,
      fn expense ->
        case Map.get(expense, :trips, []) do
          [trip] ->
            case Trip.local_datetime(trip, :departure) do
              %NaiveDateTime{} = datetime ->
                {0, NaiveDateTime.to_iso8601(datetime), expense.inserted_at, expense.id}

              nil ->
                {1, "", expense.inserted_at, expense.id}
            end

          _ ->
            {1, "", expense.inserted_at, expense.id}
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
              create_expense(
                kind,
                socket.assigns.delegation.id,
                entry.client_name,
                entry.client_type,
                path,
                socket.assigns.delegation.start_date,
                socket.assigns.delegation.end_date,
                socket.assigns.ash_scope
              )}
           end) do
        {:ok, _expense} -> refresh_delegation(socket)
        {:error, _reason} -> put_flash(socket, :error, gettext("Could not add the document."))
      end

    {:noreply, assign(socket, :uploading?, uploads_in_progress?(socket))}
  end

  defp handle_signed_upload_progress(_kind, _entry, socket), do: {:noreply, socket}

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
          |> put_flash(:error, gettext("Could not add the statement."))
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
          |> put_flash(:error, gettext("Could not add the related document."))
      end

    {:noreply, assign(socket, :uploading?, uploads_in_progress?(socket))}
  end

  defp consume_related_document(socket, entry, expense_id) when is_binary(expense_id) do
    consume_uploaded_entry(socket, entry, fn %{path: path} ->
      {:ok,
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
       end}
    end)
  end

  defp consume_related_document(socket, entry, _expense_id) do
    consume_uploaded_entry(socket, entry, fn _meta -> {:ok, {:error, :expense_not_selected}} end)
  end

  defp consume_statement_document(socket, entry, expense_id) when is_binary(expense_id) do
    consume_uploaded_entry(socket, entry, fn %{path: path} ->
      {:ok,
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
       end}
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

  defp assign_complete_form(socket, form) do
    %{expense_forms: expense_forms, trip_forms: trip_forms} = SettlementForm.nested_forms(form)
    assign(socket, complete_form: form, expense_forms: expense_forms, trip_forms: trip_forms)
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

  defp expense_currencies(expenses) do
    Map.new(expenses, fn expense ->
      currency = expense.expense_amount |> Money.to_currency_code() |> Atom.to_string()
      {expense.id, currency}
    end)
  end

  defp nbp_settlements(expenses) do
    expenses
    |> Enum.filter(&(&1.settlement_method == :nbp))
    |> Map.new(fn expense ->
      {expense.id,
       %{
         source_currency: Atom.to_string(Money.to_currency_code(expense.expense_amount)),
         rate: expense.nbp_rate,
         date: expense.nbp_rate_date,
         amount: expense.settlement_amount
       }}
    end)
  end

  defp foreign_currency_modes(expenses) do
    expenses
    |> Enum.reject(&is_nil(&1.settlement_method))
    |> Map.new(&{&1.id, &1.settlement_method})
  end

  defp assign_summary(socket) do
    per_diem = PerDiem.for_delegation(socket.assigns.delegation)
    total = SettlementPresentation.total(socket.assigns.delegation.expenses, per_diem)

    advance = socket.assigns.delegation.advance_amount
    {label, balance} = SettlementPresentation.settlement_balance(total, advance)

    assign(socket,
      per_diem: per_diem,
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
end
