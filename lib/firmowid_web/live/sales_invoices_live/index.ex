defmodule FirmowidWeb.SalesInvoicesLive.Index do
  alias Firmowid.Finances
  alias Firmowid.SalesInvoices.SalesInvoice
  alias Firmowid.SalesInvoices

  import FirmowidWeb.SalesInvoicesLive.EditButton
  import FirmowidWeb.SalesInvoicesLive.BuyerForm
  import FirmowidWeb.SalesInvoicesLive.SellerForm
  import FirmowidWeb.SalesInvoicesLive.SalesInvoiceItems

  use FirmowidWeb, :live_view
  require Logger

  def mount(params, _session, socket) do
    Bodyguard.permit!(SalesInvoices, :read_sales_invoice, socket.assigns.current_user)

    sales_invoice =
      case params["id"] do
        nil ->
          :new_invoice

        id ->
          case UUIDv7.cast(id) do
            {:ok, id} -> SalesInvoices.get_sales_invoice(id)
            _ -> nil
          end
      end

    socket =
      socket
      |> assign_sales_invoice(sales_invoice)
      |> assign_bank_accounts()
      |> assign_buyers()
      |> assign(nip_form: to_form(%{"nip" => ""}))
      |> assign_buyer_form_state("closed")
      |> assign(is_buyer_dirty: false)
      |> assign(is_seller_dirty: false)

    {:ok, socket}
  end

  def assign_buyers(socket) do
    socket |> assign(buyers: SalesInvoices.list_buyers())
  end

  def assign_bank_accounts(socket) do
    socket |> assign(bank_accounts: Finances.list_bank_accounts())
  end

  def assign_currency(socket) do
    sales_invoice = socket.assigns.sales_invoice

    case sales_invoice.currency do
      "PLN" ->
        socket |> assign(currency_rate: nil)

      currency ->
        socket
        |> assign(
          currency_rate:
            currency
            |> Firmowid.Nbp.ApiClient.get_exchange_rate(
              SalesInvoice.get_currency_conversion_date(sales_invoice)
            )
        )
    end
  end

  def assign_sales_invoice(socket, %SalesInvoice{} = sales_invoice) do
    form =
      sales_invoice
      |> SalesInvoice.changeset()
      |> to_form

    socket
    |> assign(form: form)
    |> assign(sales_invoice: sales_invoice)
    |> assign(sales_invoice_id: sales_invoice.id)
    |> assign_currency()
  end

  def assign_sales_invoice(socket, nil) do
    socket
    |> put_flash(:error, "Nie znaleziono faktury")
    |> push_navigate(to: ~p"/sprzedazowe")
  end

  def assign_sales_invoice(socket, :new_invoice) do
    last_sales_invoice = SalesInvoices.get_latest_sales_invoice() || %{}

    organization = socket.assigns.current_user.organization

    sales_invoice =
      %{
        payment_method: "Przelew",
        issue_date: Date.utc_today(),
        sale_date: Date.utc_today(),
        due_date: Date.utc_today()
      }
      |> Map.merge(
        Map.take(last_sales_invoice, [
          :payment_method,
          :issue_date,
          :sale_date,
          :due_date,
          :is_cash_account,
          :is_reverse_charge
        ])
      )

    sales_invoice =
      sales_invoice
      |> Map.merge(%{
        invoice_number: SalesInvoices.get_next_invoice_number(sales_invoice.issue_date),
        invoice_type: :poland,
        currency: "PLN",
        organization_id: Firmowid.Repo.get_org_id(),
        sales_invoice_items: [],
        buyer_type: :company,
        is_basic_info_confirmed: false,
        is_seller_confirmed: true,
        is_buyer_confirmed: false,
        are_sales_invoice_items_confirmed: false
      })
      |> Map.merge(%{
        seller_nip: organization.identification_number,
        seller_display_name: organization.name,
        seller_address: organization.address,
        seller_name: organization.name,
        seller_surname: nil,
        seller_account_number: nil
      })

    sales_invoice = struct(SalesInvoice, sales_invoice)

    form =
      sales_invoice
      |> SalesInvoice.changeset()
      |> to_form

    socket
    |> assign(form: form)
    |> assign(sales_invoice: sales_invoice)
    |> assign(sales_invoice_id: nil)
  end

  def assign_buyer_form_state(%{assigns: %{sales_invoice: sales_invoice}} = socket, desired_state) do
    state =
      case {sales_invoice.invoice_type, desired_state} do
        {:foreign, "nip"} ->
          "expanded"

        _ ->
          desired_state
      end

    state =
      case sales_invoice.buyer_id do
        nil -> state
        _ -> "expanded"
      end

    socket |> assign(buyer_form_state: state)
  end

  def assign_buyer_form_state(socket, desired_state) do
    socket |> assign(buyer_form_state: desired_state)
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  def populate_buyer(%{"buyer_id" => ""} = sales_invoice) do
    Map.merge(sales_invoice, %{
      "buyer_nip" => "",
      "buyer_type" => :company,
      "buyer_display_name" => "",
      "buyer_name" => "",
      "buyer_surname" => "",
      "buyer_address" => "",
      "buyer_country" => "",
      "buyer_email" => "",
      "buyer_phone" => "",
      "buyer_description" => ""
    })
  end

  def populate_buyer(%{"buyer_id" => buyer_id} = sales_invoice) do
    buyer = SalesInvoices.get_buyer!(buyer_id)

    Map.merge(sales_invoice, %{
      "buyer_nip" => buyer.nip,
      "buyer_type" => buyer.buyer_type,
      "buyer_pesel" => buyer.pesel,
      "buyer_display_name" => buyer.display_name,
      "buyer_name" => buyer.name,
      "buyer_surname" => buyer.surname,
      "buyer_address" => buyer.address,
      "buyer_country" => buyer.country,
      "buyer_email" => buyer.email,
      "buyer_phone" => buyer.phone,
      "buyer_description" => buyer.description,
      "is_buyer_confirmed" => true
    })
  end

  def populate_buyer(sales_invoice), do: sales_invoice

  def handle_event("update_buyer_state", %{"buyer_form_state" => state}, socket) do
    {:noreply, socket |> assign_buyer_form_state(state)}
  end

  def handle_event("change", %{"sales_invoice" => sales_invoice}, socket) do
    whole_form = Map.merge(socket.assigns.form.params, sales_invoice)

    sales_invoice_changeset =
      socket.assigns.sales_invoice
      |> SalesInvoice.changeset(whole_form)

    seller_changeset =
      socket.assigns.sales_invoice
      |> SalesInvoice.seller_changeset(sales_invoice)

    buyer_changeset = socket.assigns.sales_invoice |> SalesInvoice.buyer_changeset(sales_invoice)

    form = sales_invoice_changeset |> to_form()

    socket =
      socket
      |> assign(form: form)
      |> assign(is_seller_dirty: seller_changeset.changes != %{})
      |> assign(is_buyer_dirty: buyer_changeset.changes != %{})

    {:noreply, socket}
  end

  def handle_event("submit", %{"nip" => nip}, socket) do
    case SalesInvoices.NipApiClient.fetch_org_data_by_nip(nip) do
      {:ok, buyer_info} ->
        buyer =
          %{
            "buyer_display_name" => buyer_info.name,
            "buyer_address" => buyer_info.address,
            "buyer_country" => "Polska",
            "buyer_nip" => buyer_info.nip
          }

        socket = socket |> assign_buyer_form_state("expanded")
        handle_event("change", %{"sales_invoice" => buyer}, socket)

      {:error, :not_found} ->
        {:noreply,
         socket
         |> put_flash(:error, "Nie udało się znaleźć takiej firmy")}

      {:error, :invalid_nip} ->
        {:noreply,
         socket
         |> put_flash(:error, "Niepoprawny NIP")}

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "Niespodziewany błąd. Spróbuj ponownie później")}
    end
  end

  def handle_event("submit", %{"sales_invoice" => sales_invoice} = params, socket) do
    {socket, buyer_id} = socket |> maybe_create_or_update_buyer(params)

    sales_invoice = sales_invoice |> populate_buyer()

    sales_invoice =
      if buyer_id != nil, do: Map.put(sales_invoice, "buyer_id", buyer_id), else: sales_invoice

    user = socket.assigns.current_user

    socket =
      case socket.assigns do
        %{sales_invoice_id: nil, sales_invoice: socket_sales_invoice} ->
          Bodyguard.permit!(SalesInvoices, :create_sales_invoice, user)

          SalesInvoices.create_sales_invoice(socket_sales_invoice, sales_invoice)

        %{sales_invoice_id: _sales_invoice_id, sales_invoice: socket_sales_invoice} ->
          Bodyguard.permit!(SalesInvoices, :update_sales_invoice, user)

          SalesInvoices.update_sales_invoice(socket_sales_invoice, sales_invoice)
      end
      |> case do
        {:ok, new_invoice} ->
          socket
          |> push_patch(to: ~p"/sprzedazowe/#{new_invoice.id}/edycja")
          |> assign(sales_invoice_id: new_invoice.id)
          |> assign(sales_invoice: SalesInvoices.get_sales_invoice(new_invoice.id))
          |> assign_currency()

        {:error, changeset} ->
          Logger.error("Failed to save invoice: #{inspect(changeset)}")
          LiveToast.send_toast(:error, "Nie udało się zapisać faktury")
          socket
      end

    socket =
      if Map.get(sales_invoice, "is_buyer_confirmed"),
        do: socket |> assign_buyer_form_state("expanded"),
        else: socket

    handle_event("change", %{"sales_invoice" => sales_invoice}, socket)
  end

  defp maybe_create_or_update_buyer(socket, %{
         "action" => "add_or_update_buyer",
         "sales_invoice" => sales_invoice
       }) do
    buyer_id = socket.assigns.sales_invoice.buyer_id
    user = socket.assigns.current_user

    attrs = %{
      buyer_type: sales_invoice["buyer_type"],
      nip: sales_invoice["buyer_nip"],
      pesel: sales_invoice["buyer_pesel"],
      display_name: sales_invoice["buyer_display_name"],
      name: sales_invoice["buyer_name"],
      surname: sales_invoice["buyer_surname"],
      address: sales_invoice["buyer_address"],
      country: sales_invoice["buyer_country"],
      email: sales_invoice["buyer_email"],
      phone: sales_invoice["buyer_phone"],
      description: sales_invoice["buyer_description"]
    }

    case buyer_id do
      id when id in [nil, ""] ->
        Bodyguard.permit!(SalesInvoices, :create_buyer, user)
        SalesInvoices.create_buyer(attrs)

      id ->
        Bodyguard.permit!(SalesInvoices, :update_buyer, user)
        SalesInvoices.update_buyer(SalesInvoices.get_buyer!(id), attrs)
    end
    |> case do
      {:ok, buyer} ->
        {socket |> assign_buyers(), buyer.id}

      {:error, _} ->
        LiveToast.send_toast(:error, "Nie udało się zapisać nabywcy")
        {socket, nil}
    end
  end

  defp maybe_create_or_update_buyer(socket, _params), do: {socket, nil}
end
