defmodule FirmowidWeb.DocumentsLive.Show do
  use FirmowidWeb, :live_view

  alias Firmowid.Documents
  alias Firmowid.InvoiceMatcher

  @impl true
  def mount(params, _session, socket) do
    user = socket.assigns.current_user
    organization_id = user.organization_id

    document_id = params["id"]

    document = Documents.get_document(organization_id, document_id)

    potential_transactions =
      if document.imported_transactions == [] do
        potential_transactions =
          InvoiceMatcher.get_potential_transactions_for_document(
            document,
            organization_id,
            similarity_threshold: 0.0,
            days_before: 15,
            days_after: 10,
            exact_amount: false
          )
          |> Enum.map(fn t ->
            Map.merge(t, %{
              amount:
                Money.new(
                  t.transaction_currency,
                  t.transaction_amount
                )
            })
          end)

        InvoiceMatcher.llm_re_grade_matches(
          document,
          potential_transactions
        )
        |> Enum.map(fn {t, grade} -> Map.put(t, :llm_eval, grade) end)
        |> Enum.sort_by(& &1.llm_eval, :desc)
      else
        []
      end

    is_llm_certain = Enum.all?(potential_transactions, fn t -> t.llm_eval > 0.9 end)

    grouped_potential_transactions =
      if document.imported_transactions == [] and
           (potential_transactions == [] or
              not is_llm_certain) do
        InvoiceMatcher.match_with_transaction_combo(document, organization_id)
      else
        []
      end

    socket =
      socket
      |> assign(:document, document)
      |> assign(:potential_transactions, potential_transactions)
      |> assign(:grouped_potential_transactions, grouped_potential_transactions)

      # styling
      |> assign(:no_padding, true)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    socket =
      socket
      |> apply_action(socket.assigns.live_action, params)

    {:noreply, socket}
  end

  @impl true
  def handle_event(
        "connect-group",
        %{"group-id" => group_id},
        socket
      ) do
    user = socket.assigns.current_user
    organization_id = user.organization_id
    group_id = String.to_integer(group_id)

    document_id = socket.assigns.document.id

    grouped_potential_transactions = socket.assigns.grouped_potential_transactions

    {_group, imported_transactions} =
      Enum.find(grouped_potential_transactions, fn {group, _} -> group.id == group_id end)

    imported_transactions
    |> Enum.map(fn t ->
      Documents.create_documents_imported_transactions_connection(
        document_id,
        t.id,
        organization_id
      )
    end)

    document = Documents.get_document(organization_id, document_id)

    socket =
      socket
      |> assign(:document, document)
      |> assign(:grouped_potential_transactions, [])
      |> assign(:potential_transactions, [])

    {:noreply, socket}
  end

  @impl true
  def handle_event(
        "connect",
        %{
          "document-id" => document_id,
          "imported-transaction-id" => imported_transaction_id
        },
        socket
      ) do
    user = socket.assigns.current_user
    organization_id = user.organization_id

    Documents.create_documents_imported_transactions_connection(
      document_id,
      imported_transaction_id,
      organization_id
    )

    document = Documents.get_document(organization_id, document_id)

    socket =
      socket
      |> assign(:document, document)

    {:noreply, socket}
  end

  @impl true
  def handle_event(
        "disconnect",
        %{"document-id" => document_id, "imported-transaction-id" => imported_transaction_id},
        socket
      ) do
    user = socket.assigns.current_user
    organization_id = user.organization_id

    Documents.delete_documents_imported_transactions_connection(
      organization_id,
      document_id,
      imported_transaction_id
    )

    document = Documents.get_document(organization_id, document_id)

    potential_transactions =
      InvoiceMatcher.get_potential_transactions_for_document(
        document,
        organization_id,
        similarity_threshold: 0.0,
        days_before: 15,
        days_after: 10,
        exact_amount: false
      )
      |> Enum.map(fn t ->
        Map.merge(t, %{
          amount:
            Money.new(
              t.transaction_currency,
              t.transaction_amount
            )
        })
      end)

    potential_transactions =
      InvoiceMatcher.llm_re_grade_matches(
        document,
        potential_transactions
      )
      |> Enum.map(fn {t, grade} -> Map.put(t, :llm_eval, grade) end)
      |> Enum.sort_by(& &1.llm_eval, :desc)

    socket =
      socket
      |> assign(:document, document)
      |> assign(:potential_transactions, potential_transactions)

    {:noreply, socket}
  end

  @impl true
  def handle_event(
        "disconnect-group",
        %{"document-id" => document_id},
        socket
      ) do
    user = socket.assigns.current_user
    organization_id = user.organization_id

    document = Documents.get_document(organization_id, document_id)

    document.imported_transactions
    |> Enum.map(fn t ->
      Documents.delete_documents_imported_transactions_connection(
        organization_id,
        document_id,
        t.id
      )
    end)

    document = Documents.get_document(organization_id, document_id)

    potential_transactions =
      InvoiceMatcher.get_potential_transactions_for_document(
        document,
        organization_id,
        similarity_threshold: 0.0,
        days_before: 15,
        days_after: 10,
        exact_amount: false
      )
      |> Enum.map(fn t ->
        Map.merge(t, %{
          amount:
            Money.new(
              t.transaction_currency,
              t.transaction_amount
            )
        })
      end)

    potential_transactions =
      InvoiceMatcher.llm_re_grade_matches(
        document,
        potential_transactions
      )
      |> Enum.map(fn {t, grade} -> Map.put(t, :llm_eval, grade) end)
      |> Enum.sort_by(& &1.llm_eval, :desc)

    grouped_potential_transactions =
      if document.imported_transactions == [] and potential_transactions == [] do
        InvoiceMatcher.match_with_transaction_combo(document, organization_id)
      else
        []
      end

    socket =
      socket
      |> assign(:document, document)
      |> assign(:potential_transactions, potential_transactions)
      |> assign(:grouped_potential_transactions, grouped_potential_transactions)

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle-skip-invoicing", _, socket) do
    user = socket.assigns.current_user
    organization_id = user.organization_id

    skip_invoicing = socket.assigns.document.skip_invoicing

    Documents.update_document(
      organization_id,
      socket.assigns.document.id,
      %{
        skip_invoicing: !skip_invoicing
      }
    )

    document =
      Documents.get_document(
        organization_id,
        socket.assigns.document.id
      )

    socket =
      socket
      |> assign(:document, document)

    {:noreply, socket}
  end

  @impl true
  def handle_event(
        "delete",
        %{"document-id" => document_id},
        socket
      ) do
    user = socket.assigns.current_user
    organization_id = user.organization_id

    Documents.delete_document(
      organization_id,
      document_id
    )

    LiveToast.send_toast(
      :info,
      "Dokument został usunięty."
    )

    socket =
      socket
      |> push_navigate(to: ~p"/")

    {:noreply, socket}
  end

  defp apply_action(socket, :index, params) do
    socket
    |> assign(:page_title, "Podgląd dokumentu #{params["id"]}")
  end
end
