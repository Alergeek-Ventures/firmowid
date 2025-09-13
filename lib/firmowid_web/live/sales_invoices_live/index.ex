defmodule FirmowidWeb.SalesInvoicesLive.Index do
  @moduledoc false
  use FirmowidWeb, :live_view

  import FirmowidWeb.SalesInvoicesLive.BuyerForm
  import FirmowidWeb.SalesInvoicesLive.EditButton
  import FirmowidWeb.SalesInvoicesLive.SalesInvoiceItems
  import FirmowidWeb.SalesInvoicesLive.SellerForm

  alias Firmowid.Finances
  alias Firmowid.SalesInvoices
  alias Firmowid.SalesInvoices.SalesInvoice

  require Logger

  def mount(params, _session, socket) do
    Bodyguard.permit!(SalesInvoices, :read_sales_invoice, socket.assigns.current_user)

    sales_invoice =
      case params["id"] do
        nil ->
          :new_invoice

        id ->
          case UUIDv7.cast(id) do
            {:ok, id} -> SalesInvoices.get_sales_invoice_with_logo_url(id)
            _ -> nil
          end
      end

    socket =
      socket
      |> assign(bank_accounts: Finances.list_bank_accounts())
      |> assign_sales_invoice(sales_invoice, params)
      |> assign(nip_form: to_form(%{"nip" => ""}))
      |> assign_buyer_form_state("nip")
      |> assign(is_buyer_dirty: false)
      |> assign(is_seller_dirty: false)

    {:ok, socket}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  def assign_currency(socket) do
    sales_invoice = socket.assigns.sales_invoice

    currency_rate =
      case sales_invoice.currency do
        "PLN" ->
          nil

        currency ->
          Firmowid.Nbp.ApiClient.get_exchange_rate(
            currency,
            SalesInvoice.get_currency_conversion_date(sales_invoice)
          )
      end

    assign(socket, currency_rate: currency_rate)
  end

  def assign_sales_invoice(socket, %SalesInvoice{} = sales_invoice, _) do
    form =
      sales_invoice
      |> SalesInvoice.changeset()
      |> to_form()

    socket
    |> assign(form: form)
    |> assign(sales_invoice: sales_invoice)
    |> assign(sales_invoice_id: sales_invoice.id)
    |> assign_currency()
  end

  def assign_sales_invoice(socket, :new_invoice, params) do
    organization = socket.assigns.current_user.organization
    last_sales_invoice = SalesInvoices.get_latest_sales_invoice() || %{}

    base_sales_invoice =
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
      |> Map.merge(%{
        invoice_number: SalesInvoices.get_next_invoice_number(Date.utc_today()),
        organization_id: Firmowid.Repo.get_org_id(),
        sales_invoice_items: [],
        buyer_type: :company,
        is_basic_info_confirmed: false,
        is_seller_confirmed: true,
        is_buyer_confirmed: false,
        are_sales_invoice_items_confirmed: false,
        seller_nip: organization.identification_number,
        seller_display_name: organization.name,
        seller_address: organization.address,
        seller_name: organization.name,
        seller_surname: nil,
        seller_account_number: nil
      })

    sales_invoice =
      cond do
        # Copy from existing invoice
        params["skopiuj"] ->
          sales_invoice_to_copy = SalesInvoices.get_sales_invoice_with_logo_url(params["skopiuj"])

          data_to_copy =
            Map.take(sales_invoice_to_copy, [
              :buyer_nip,
              :buyer_display_name,
              :buyer_name,
              :buyer_surname,
              :buyer_address,
              :buyer_country,
              :buyer_email,
              :buyer_phone,
              :buyer_description,
              :buyer_pesel,
              :buyer_type,
              :buyer_is_different_mail_address,
              :buyer_mail_address,
              :buyer_mail_country,
              :currency,
              :payment_method,
              :is_reverse_charge,
              :is_cash_account,
              :invoice_type
            ])

          sales_invoice_items =
            Enum.map(sales_invoice_to_copy.sales_invoice_items, fn item ->
              %{
                name: item.name,
                quantity: item.quantity,
                unit: item.unit,
                unit_price: item.unit_price,
                vat_rate: item.vat_rate
              }
            end)

          base_sales_invoice
          |> Map.merge(%{
            invoice_type: :poland,
            currency: "PLN",
            sales_invoice_items: sales_invoice_items
          })
          |> Map.merge(data_to_copy)

        # Foreign invoice type
        params["typ"] == "zagraniczny" ->
          Map.merge(base_sales_invoice, %{
            invoice_type: :foreign,
            currency: "EUR",
            is_reverse_charge: true
          })

        # Polish invoice type or empty params
        params["typ"] == "polski" || !params["typ"] ->
          Map.merge(base_sales_invoice, %{invoice_type: :poland, currency: "PLN"})
      end

    default_bank_account =
      Enum.find_value(
        socket.assigns.bank_accounts,
        &(&1.is_default and &1.currency == sales_invoice.currency)
      )

    sales_invoice =
      if default_bank_account do
        Map.put(sales_invoice, :seller_account_number, default_bank_account)
      else
        sales_invoice
      end

    sales_invoice =
      %SalesInvoice{}
      |> SalesInvoice.changeset(sales_invoice)
      |> Ecto.Changeset.apply_changes()

    assign_sales_invoice(socket, sales_invoice, params)
  end

  def assign_buyer_form_state(%{assigns: %{sales_invoice: %{invoice_type: :foreign}}} = socket, _) do
    assign(socket, buyer_form_state: "expanded")
  end

  def assign_buyer_form_state(socket, desired_state) do
    assign(socket, buyer_form_state: desired_state)
  end

  def handle_event("update_buyer_state", %{"buyer_form_state" => state}, socket) do
    {:noreply, assign_buyer_form_state(socket, state)}
  end

  def handle_event("change", %{"sales_invoice" => sales_invoice}, socket) do
    default_bank_account =
      Enum.find_value(
        socket.assigns.bank_accounts,
        &(&1.is_default and &1.currency == sales_invoice["currency"])
      )

    sales_invoice =
      if default_bank_account do
        Map.put(sales_invoice, "seller_account_number", default_bank_account)
      else
        sales_invoice
      end

    # Update invoice_number if issue_date is present and valid
    sales_invoice =
      case sales_invoice["issue_date"] do
        nil ->
          sales_invoice

        date_str ->
          case Date.from_iso8601(date_str) do
            {:ok, issue_date} ->
              Map.put(
                sales_invoice,
                "invoice_number",
                SalesInvoices.get_next_invoice_number(issue_date)
              )

            {:error, _} ->
              sales_invoice
          end
      end

    whole_form = Map.merge(socket.assigns.form.params, sales_invoice)

    sales_invoice_changeset = SalesInvoice.changeset(socket.assigns.sales_invoice, whole_form)

    seller_changeset = SalesInvoice.seller_changeset(socket.assigns.sales_invoice, sales_invoice)

    buyer_changeset = SalesInvoice.buyer_changeset(socket.assigns.sales_invoice, sales_invoice)

    form = to_form(sales_invoice_changeset)

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

        socket = assign_buyer_form_state(socket, "expanded")
        handle_event("change", %{"sales_invoice" => buyer}, socket)

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Nie udało się znaleźć takiej firmy")}

      {:error, :invalid_nip} ->
        {:noreply, put_flash(socket, :error, "Niepoprawny NIP")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Niespodziewany błąd. Spróbuj ponownie później")}
    end
  end

  def handle_event("submit", %{"sales_invoice" => sales_invoice}, socket) do
    user = socket.assigns.current_user

    case_result =
      case socket.assigns do
        %{sales_invoice_id: nil, sales_invoice: socket_sales_invoice} ->
          Bodyguard.permit!(SalesInvoices, :create_sales_invoice, user)

          SalesInvoices.create_sales_invoice(socket_sales_invoice, sales_invoice)

        %{sales_invoice_id: _sales_invoice_id, sales_invoice: socket_sales_invoice} ->
          Bodyguard.permit!(SalesInvoices, :update, user, socket_sales_invoice)

          SalesInvoices.update_sales_invoice(socket_sales_invoice, sales_invoice)
      end

    socket =
      case case_result do
        {:ok, new_invoice} ->
          socket
          |> push_patch(to: ~p"/sprzedazowe/#{new_invoice.id}/edycja")
          |> assign(sales_invoice_id: new_invoice.id)
          |> assign(sales_invoice: SalesInvoices.get_sales_invoice_with_logo_url(new_invoice.id))
          |> assign_currency()

        {:error, %Ecto.Changeset{errors: errors} = changeset} ->
          case Keyword.get(errors, :invoice_number) do
            {_message,
             [
               constraint: :unique,
               constraint_name: "sales_invoices_invoice_number_organization_id_index"
             ]} ->
              Logger.error("Duplicate invoice number: #{inspect(changeset)}")

              LiveToast.send_toast(
                :error,
                "Ten numer faktury już istnieje w organizacji. Wybierz inny numer."
              )

              assign(socket, form: to_form(changeset))

            {message, []} ->
              Logger.error("Failed to save invoice: #{inspect(changeset)}")
              LiveToast.send_toast(:error, message)

              assign(socket, form: to_form(changeset))

            _ ->
              Logger.error("Failed to save invoice: #{inspect(changeset)}")
              LiveToast.send_toast(:error, "Nie udało się zapisać faktury")

              assign(socket, form: to_form(changeset))
          end
      end

    # unique error message for invoice number duplication
    socket =
      if Map.get(sales_invoice, "is_buyer_confirmed"),
        do: assign_buyer_form_state(socket, "expanded"),
        else: socket

    handle_event("change", %{"sales_invoice" => sales_invoice}, socket)
  end

  def handle_event("save", _params, socket) do
    if socket.assigns.sales_invoice.seller_account_number in [nil, ""] do
      LiveToast.send_toast(:error, "Wypełnij numer konta bankowego")
      {:noreply, socket}
    else
      {:noreply, push_navigate(socket, to: ~p"/sprzedazowe/#{socket.assigns.sales_invoice.id}")}
    end
  end
end
