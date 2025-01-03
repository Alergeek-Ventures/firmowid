defmodule FirmowidWeb.InvoicesLive.Index do
  alias Firmowid.Invoices
  alias Firmowid.Invoices.Invoice
  import FirmowidWeb.InvoicesLive.EditButton
  import FirmowidWeb.InvoicesLive.BuyerForm
  import FirmowidWeb.InvoicesLive.SellerForm
  import FirmowidWeb.InvoicesLive.InvoiceItems

  use FirmowidWeb, :live_view
  require Logger

  def mount(params, _session, socket) do
    invoice =
      case params["id"] do
        nil ->
          :new_invoice

        id ->
          Invoices.get_invoice(id)
      end

    {:ok,
     socket
     |> assign_invoice(invoice)
     |> assign_buyers()
     |> assign_sellers()
     |> assign(nip_form: to_form(%{"nip" => ""}))
     |> assign_buyer_form_state("closed")
     |> assign(is_buyer_dirty: false)
     |> assign(is_seller_dirty: false)}
  end

  def assign_buyers(socket) do
    socket |> assign(buyers: Invoices.list_buyers())
  end

  def assign_sellers(socket) do
    socket |> assign(sellers: Invoices.list_sellers())
  end

  def assign_currency(socket) do
    invoice = socket.assigns.invoice

    case invoice.currency do
      "PLN" ->
        socket |> assign(currency_rate: nil)

      currency ->
        socket
        |> assign(
          currency_rate:
            currency
            |> Firmowid.Nbp.ApiClient.get_exchange_rate(
              Invoice.get_currency_conversion_date(invoice)
            )
        )
    end
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
    |> assign_currency()
  end

  def assign_invoice(socket, nil) do
    socket
    |> put_flash(:error, "Nie znaleziono faktury")
    |> push_navigate(to: "/invoices")
  end

  def assign_invoice(socket, :new_invoice) do
    last_invoice = Invoices.get_latest_invoice() || %{}

    seller =
      if is_nil(Map.get(last_invoice, :seller_id)) do
        Invoices.list_sellers() |> Enum.at(0)
      else
        Invoices.get_seller!(last_invoice.seller_id)
      end

    seller_in_invoice =
      case seller do
        nil ->
          %{}

        _ ->
          %{
            seller_id: seller.id,
            seller_nip: seller.nip,
            seller_display_name: seller.display_name,
            seller_address: seller.street,
            seller_name: seller.name,
            seller_surname: seller.surname,
            seller_account_number: seller.account_number,
            is_seller_confirmed: true
          }
      end

    invoice =
      struct(
        Invoice,
        %{
          payment_method: "Przelew",
          issue_date: Date.utc_today(),
          sale_date: Date.utc_today(),
          due_date: Date.utc_today()
        }
        |> Map.merge(
          Map.take(last_invoice, [
            :payment_method,
            :issue_date,
            :sale_date,
            :due_date,
            :is_cash_account,
            :is_reverse_charge
          ])
        )
        |> Map.merge(%{
          invoice_number: "",
          invoice_type: :poland,
          currency: "PLN",
          organization_id: Firmowid.Repo.get_org_id(),
          invoice_items: [],
          buyer_type: :company,
          is_basic_info_confirmed: false,
          is_seller_confirmed: false,
          is_buyer_confirmed: false,
          are_invoice_items_confirmed: false
        })
        |> Map.merge(seller_in_invoice)
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

  def assign_buyer_form_state(socket, desired_state) do
    state =
      case {socket.assigns.invoice.invoice_type, desired_state} do
        {:foreign, "nip"} ->
          "expanded"

        _ ->
          desired_state
      end

    state =
      case socket.assigns.invoice.buyer_id do
        nil -> state
        _ -> "expanded"
      end

    socket |> assign(buyer_form_state: state)
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  def populate_seller(%{"seller_id" => ""} = invoice) do
    Map.merge(invoice, %{
      "seller_nip" => "",
      "seller_display_name" => "",
      "seller_address" => "",
      "seller_name" => "",
      "seller_surname" => "",
      "seller_account_number" => ""
    })
  end

  def populate_seller(%{"seller_id" => seller_id} = invoice) do
    seller = Invoices.get_seller!(seller_id)

    Map.merge(invoice, %{
      "seller_nip" => seller.nip,
      "seller_display_name" => seller.display_name,
      "seller_address" => seller.street,
      "seller_name" => seller.name,
      "seller_surname" => seller.surname,
      "seller_account_number" => seller.account_number,
      "is_seller_confirmed" => true
    })
  end

  def populate_seller(invoice), do: invoice

  def populate_buyer(%{"buyer_id" => ""} = invoice) do
    Map.merge(invoice, %{
      "buyer_nip" => "",
      "buyer_type" => :company,
      "buyer_display_name" => "",
      "buyer_name" => "",
      "buyer_surname" => "",
      "buyer_street" => "",
      "buyer_house_number" => "",
      "buyer_apartment_number" => "",
      "buyer_postal_code" => "",
      "buyer_city" => "",
      "buyer_country" => "",
      "buyer_email" => "",
      "buyer_phone" => "",
      "buyer_description" => ""
    })
  end

  def populate_buyer(%{"buyer_id" => buyer_id} = invoice) do
    buyer = Invoices.get_buyer!(buyer_id)

    Map.merge(invoice, %{
      "buyer_nip" => buyer.nip,
      "buyer_type" => buyer.buyer_type,
      "buyer_pesel" => buyer.pesel,
      "buyer_display_name" => buyer.display_name,
      "buyer_name" => buyer.name,
      "buyer_surname" => buyer.surname,
      "buyer_street" => buyer.street,
      "buyer_house_number" => buyer.house_number,
      "buyer_apartment_number" => buyer.apartment_number,
      "buyer_postal_code" => buyer.postal_code,
      "buyer_city" => buyer.city,
      "buyer_country" => buyer.country,
      "buyer_email" => buyer.email,
      "buyer_phone" => buyer.phone,
      "buyer_description" => buyer.description,
      "is_buyer_confirmed" => true
    })
  end

  def populate_buyer(invoice), do: invoice

  def handle_event("update_buyer_state", %{"buyer_form_state" => state}, socket) do
    {:noreply, socket |> assign_buyer_form_state(state)}
  end

  def handle_event("change", %{"invoice" => invoice}, socket) do
    whole_form = Map.merge(socket.assigns.form.params, invoice)

    invoice_changeset =
      socket.assigns.invoice
      |> Invoice.changeset(whole_form)

    seller_changeset =
      socket.assigns.invoice
      |> Invoice.seller_changeset(invoice)

    buyer_changeset = socket.assigns.invoice |> Invoice.buyer_changeset(invoice)

    form = invoice_changeset |> to_form()

    socket =
      socket
      |> assign(form: form)
      |> assign(is_seller_dirty: seller_changeset.changes != %{})
      |> assign(is_buyer_dirty: buyer_changeset.changes != %{})

    {:noreply, socket}
  end

  def handle_event("submit", %{"nip" => nip}, socket) do
    case Invoices.NipApiClient.fetch_org_data_by_nip(nip) do
      {:ok, buyer_info} ->
        buyer =
          %{
            "buyer_display_name" => buyer_info.name,
            "buyer_street" => buyer_info.street,
            "buyer_city" => buyer_info.city,
            "buyer_country" => "Polska",
            "buyer_postal_code" => buyer_info.postal_code,
            "buyer_nip" => buyer_info.nip
          }

        socket = socket |> assign_buyer_form_state("expanded")
        handle_event("change", %{"invoice" => buyer}, socket)

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

  def handle_event("submit", %{"invoice" => invoice} = params, socket) do
    {socket, buyer_id} = socket |> maybe_create_or_update_buyer(params)
    {socket, seller_id} = socket |> maybe_create_or_update_seller(params)

    invoice = invoice |> populate_seller() |> populate_buyer()

    invoice = if buyer_id != nil, do: Map.put(invoice, "buyer_id", buyer_id), else: invoice
    invoice = if seller_id != nil, do: Map.put(invoice, "seller_id", seller_id), else: invoice

    socket =
      case socket.assigns do
        %{invoice_id: nil, invoice: socket_invoice} ->
          Invoices.create_invoice(socket_invoice, invoice)

        %{invoice_id: _invoice_id, invoice: socket_invoice} ->
          Invoices.update_invoice(socket_invoice, invoice)
      end
      |> case do
        {:ok, db_invoice} ->
          socket
          |> push_patch(to: "/invoices/#{db_invoice.id}")
          |> assign(invoice_id: db_invoice.id)
          |> assign(invoice: db_invoice)
          |> assign_currency()

        {:error, changeset} ->
          Logger.error("Failed to save invoice: #{inspect(changeset)}")
          socket |> put_flash(:error, "Nie udało się zapisać faktury")
      end

    socket =
      if Map.get(invoice, "is_buyer_confirmed"),
        do: socket |> assign_buyer_form_state("expanded"),
        else: socket

    handle_event("change", %{"invoice" => invoice}, socket)
  end

  defp maybe_create_or_update_seller(socket, %{
         "action" => "add_or_update_seller",
         "invoice" => invoice
       }) do
    case Invoices.create_or_update_seller(socket.assigns.invoice.seller_id, %{
           nip: invoice["seller_nip"],
           display_name: invoice["seller_display_name"],
           name: invoice["seller_name"],
           surname: invoice["seller_surname"],
           street: invoice["seller_address"],
           house_number: "",
           apartment_number: "",
           postal_code: "",
           city: "",
           country: "",
           account_number: invoice["seller_account_number"]
         }) do
      {:ok, seller} ->
        {socket
         |> assign_sellers(), seller.id}

      {:error, changeset} ->
        Logger.error("Failed to save seller: #{inspect(changeset)}")
        {socket |> put_flash(:error, "Nie udało się zapisać sprzedawcy"), nil}
    end
  end

  defp maybe_create_or_update_seller(socket, _params), do: {socket, nil}

  defp maybe_create_or_update_buyer(socket, %{
         "action" => "add_or_update_buyer",
         "invoice" => invoice
       }) do
    case Invoices.create_or_update_buyer(
           socket.assigns.invoice.buyer_id,
           %{
             buyer_type: invoice["buyer_type"],
             nip: invoice["buyer_nip"],
             pesel: invoice["buyer_pesel"],
             display_name: invoice["buyer_display_name"],
             name: invoice["buyer_name"],
             surname: invoice["buyer_surname"],
             street: invoice["buyer_street"],
             house_number: invoice["buyer_house_number"],
             apartment_number: invoice["buyer_apartment_number"],
             postal_code: invoice["buyer_postal_code"],
             city: invoice["buyer_city"],
             country: invoice["buyer_country"],
             email: invoice["buyer_email"],
             phone: invoice["buyer_phone"],
             description: invoice["buyer_description"]
           }
         ) do
      {:ok, buyer} ->
        {socket
         |> assign_buyers(), buyer.id}

      {:error, changeset} ->
        Logger.error("Failed to save buyer: #{inspect(changeset)}")
        {socket |> put_flash(:error, "Nie udało się zapisać nabywcy"), nil}
    end
  end

  defp maybe_create_or_update_buyer(socket, _params), do: {socket, nil}
end
