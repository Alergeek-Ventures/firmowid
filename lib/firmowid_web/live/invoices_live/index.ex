defmodule FirmowidWeb.InvoicesLive.Index do
  alias Firmowid.Invoices
  alias Firmowid.Invoices.Invoice
  use FirmowidWeb, :live_view
  require Logger

  def mount(params, _session, socket) do
    Money.ExchangeRates.Retriever.latest_rates()

    organization_id = socket.assigns.current_user.organization_id

    invoice =
      case params["id"] do
        nil ->
          :new_invoice

        id ->
          Invoices.get_invoice(organization_id, id)
      end

    {:ok,
     socket
     |> assign_invoice(invoice)}
  end

  def assign_invoice(socket, %Invoice{} = invoice) do
    form =
      invoice
      |> Invoice.changeset()
      |> to_form

    socket
    |> assign(form: form)
    |> assign(invoice: invoice)
    |> assign(invoice_id: invoice.id)
  end

  def assign_invoice(socket, nil) do
    socket
    |> put_flash(:error, "Nie znaleziono faktury")
    |> push_navigate(to: "/invoices")
  end

  def assign_invoice(socket, :new_invoice) do
    organization_id = socket.assigns.current_user.organization_id

    last_invoice = Invoices.get_latest_invoice(organization_id) || %{}

    invoice =
      struct(
        Invoice,
        %{
          payment_method: "Przelew",
          issue_date: Date.utc_today(),
          sale_date: Date.utc_today(),
          due_date: Date.utc_today()
        }
        |> Map.merge(Map.take(last_invoice, Invoice.__schema__(:fields)))
        |> Map.merge(%{
          invoice_number: "",
          invoice_type: :poland,
          currency: "PLN",
          organization_id: organization_id,
          invoice_items: [],
          is_reverse_charge: false
        })
        |> Map.drop([:id])
      )

    form =
      invoice
      |> Invoice.changeset()
      |> to_form

    socket
    |> assign(form: form)
    |> assign(invoice: invoice)
    |> assign(invoice_id: nil)
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  def handle_event("change", %{"invoice" => invoice}, socket) do
    form =
      socket.assigns.invoice
      |> Invoice.changeset(invoice)
      |> to_form

    socket =
      socket
      |> assign(form: form)

    {:noreply, socket}
  end

  def handle_event("submit", %{"invoice" => invoice}, socket) do
    user = socket.assigns.current_user
    organization_id = user.organization_id

    invoice = invoice |> add_organization_id(organization_id)

    socket =
      case socket.assigns do
        %{invoice_id: nil} ->
          Invoices.create_invoice(socket.assigns.invoice, invoice)

        %{invoice_id: _invoice_id} ->
          Invoices.update_invoice(organization_id, socket.assigns.invoice, invoice)
      end
      |> case do
        {:ok, db_invoice} ->
          socket
          |> push_patch(to: "/invoices/#{db_invoice.id}")
          |> assign(invoice_id: db_invoice.id)
          |> assign(invoice: db_invoice)

        {:error, changeset} ->
          Logger.error("Failed to save invoice: #{inspect(changeset)}")
          socket |> put_flash(:error, "Nie udało się zapisać faktury")
      end

    {:noreply, socket}
  end

  defp add_organization_id(invoice, organization_id) do
    case(Map.get(invoice, "invoice_items", nil)) do
      nil ->
        invoice

      invoice_items ->
        updated_items =
          invoice_items
          |> Enum.into(%{}, fn {key, item} ->
            {key, Map.put(item, "organization_id", organization_id)}
          end)

        invoice |> Map.put("invoice_items", updated_items)
    end
    |> Map.put("organization_id", organization_id)
  end
end
