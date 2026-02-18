defmodule FirmowidWeb.SalesInvoicesLive.Edit do
  @moduledoc """
  LiveView for editing sales invoices with live PDF preview.

  Shows the original invoice and a live preview of changes being made.
  For non-draft invoices, edits create a correction invoice (faktura korygująca).
  """
  use FirmowidWeb, :live_view

  alias Firmowid.Accounts
  alias Firmowid.Finances
  alias Firmowid.Ksef
  alias Firmowid.Repo
  alias Firmowid.SalesInvoices
  alias Firmowid.SalesInvoices.CorrectionReason
  alias Firmowid.SalesInvoices.SalesInvoice
  alias FirmowidWeb.SalesInvoicesLive.Creator

  require Logger

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    invoice = SalesInvoices.get_sales_invoice(id)

    if is_nil(invoice) do
      {:ok,
       socket
       |> put_flash(:error, "Nie znaleziono faktury")
       |> push_navigate(to: ~p"/sprzedazowe")}
    else
      current_user = socket.assigns.current_user
      Bodyguard.permit!(SalesInvoices, :show, current_user, invoice)
      Bodyguard.permit!(SalesInvoices, :update, current_user, invoice)

      if SalesInvoice.editable?(invoice) do
        {:ok, organization} = Accounts.get_organization(Repo.get_org_id())
        bank_accounts = Finances.list_bank_accounts()

        invoice = Repo.preload(invoice, [:corrected_invoice])

        invoice_changeset =
          if SalesInvoice.draft?(invoice) do
            changeset(invoice)
          else
            original_invoice = if invoice.ksef_invoice_kind == :kor, do: invoice.corrected_invoice, else: invoice
            reference_invoice = invoice

            original_invoice
            |> SalesInvoice.prepare_correction_invoice_changeset(reference_invoice)
            |> Ecto.Changeset.change(%{
              issue_date: Date.utc_today(),
              invoice_number: SalesInvoices.get_next_invoice_number(Date.utc_today(), series: "FK")
            })
            |> changeset()
          end

        socket =
          socket
          |> assign(:invoice, invoice)
          |> assign(:organization, organization)
          |> assign(:reference_invoice, get_reference_invoice(invoice))
          |> assign(:correction_reason_touched, false)
          |> assign(:last_auto_reason, "")
          |> assign_form_with_preview(invoice_changeset)
          |> assign(:bank_accounts, bank_accounts)
          |> assign(
            :selected_bank_account,
            Enum.find(bank_accounts, &(&1.iban == invoice.seller_account_number)) ||
              Enum.find(bank_accounts, &(&1.is_default and &1.currency == invoice.currency))
          )
          |> assign(:counterparties, SalesInvoices.list_counterparties())
          |> assign(:ksef_connected?, Ksef.get_credential() != nil)

        {:ok, socket}
      else
        {:ok,
         socket
         |> put_flash(:error, not_editable_message(invoice))
         |> push_navigate(to: ~p"/sprzedazowe/#{invoice.id}")}
      end
    end
  end

  @impl true
  def handle_event("validate", %{"sales_invoice" => params}, socket) do
    socket = detect_correction_reason_touched(params, socket)

    changeset =
      socket.assigns.invoice
      |> changeset(params)
      |> Map.put(:action, :validate)

    socket =
      socket
      |> assign_form_with_preview(changeset)
      |> push_event("unsaved-changed", %{value: true})

    {:noreply, socket}
  end

  def handle_event("cancel_edit", _params, socket) do
    socket =
      socket
      |> push_event("unsaved-changed", %{value: false})
      |> push_navigate(to: ~p"/sprzedazowe/#{socket.assigns.invoice.id}")

    {:noreply, socket}
  end

  def handle_event("select_bank_account", %{"account_id" => account_id}, socket) do
    selected_account = Enum.find(socket.assigns.bank_accounts, &(&1.id == account_id))

    params =
      if selected_account do
        %{seller_account_number: selected_account.iban}
      else
        %{seller_account_number: nil}
      end

    changeset =
      socket.assigns.invoice
      |> changeset(params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:selected_bank_account, selected_account)
     |> assign_form_with_preview(changeset)}
  end

  def handle_event("save_as_draft", _params, socket) do
    # Use the current form params that have been validated through phx-change
    form_params = socket.assigns.form.params || %{}

    case SalesInvoices.update_sales_invoice(socket.assigns.invoice, form_params) do
      {:ok, invoice} ->
        {:noreply,
         socket
         |> push_event("unsaved-changed", %{value: false})
         |> put_flash(:info, "Wersja robocza faktury została zapisana")
         |> push_navigate(to: ~p"/sprzedazowe/#{invoice.id}")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("send_to_ksef", %{"sales_invoice" => params}, socket) do
    organization = socket.assigns.organization
    original_invoice = socket.assigns.invoice

    invoice =
      if SalesInvoice.draft?(original_invoice) do
        create_confirmed_invoice(organization, original_invoice, params)
      else
        original_invoice =
          if original_invoice.ksef_invoice_kind == :kor, do: original_invoice.corrected_invoice, else: original_invoice

        create_correction_invoice(organization, original_invoice, params)
      end

    case invoice do
      {:ok, invoice} ->
        if Ksef.get_credential() == nil do
          {:noreply,
           socket
           |> push_event("unsaved-changed", %{value: false})
           |> put_flash(:info, "Faktura została wystawiona, ale nie można jej wysłać do KSeF — brak połączenia z KSeF")
           |> push_navigate(to: ~p"/sprzedazowe/#{invoice.id}/podsumowanie")}
        else
          send_invoice_to_ksef(socket, invoice)
        end

      {:error, changeset} ->
        Logger.error("Failed to create invoice: #{inspect(changeset)}")

        socket =
          socket
          |> put_flash(:error, Creator.get_invoice_error_message(changeset))
          |> assign(:form, to_form(changeset))

        {:noreply, socket}
    end
  end

  def send_invoice_to_ksef(socket, invoice) do
    case Ksef.submit_sales_invoice(invoice.id) do
      {:ok, _job} ->
        {:noreply,
         socket
         |> push_event("unsaved-changed", %{value: false})
         |> push_navigate(to: ~p"/sprzedazowe/#{invoice.id}/podsumowanie")}

      {:error, reason} ->
        Logger.error("Failed to submit invoice to KSeF: #{inspect(reason)}")

        {:noreply,
         socket
         |> push_event("unsaved-changed", %{value: false})
         |> put_flash(:error, "Faktura została wystawiona, ale wysyłka do KSeF nie powiodła się")
         |> push_navigate(to: ~p"/sprzedazowe/#{invoice.id}/podsumowanie")}
    end
  end

  def create_confirmed_invoice(organization, invoice, invoice_params) do
    case Creator.validate_organization_for_invoicing(organization) do
      :ok ->
        issue_date = Date.utc_today()
        invoice_number = SalesInvoices.get_next_invoice_number(issue_date)

        attrs =
          Map.merge(invoice_params, %{
            "invoice_number" => invoice_number,
            "issue_date" => issue_date,
            "seller_display_name" => organization.name,
            "seller_address" => organization.address,
            "seller_nip" => organization.nip,
            "is_cash_account" => invoice_params["payment_method"] == "cash"
          })

        SalesInvoices.update_sales_invoice(invoice, attrs)

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def create_correction_invoice(organization, original_invoice, correction_invoice_params) do
    case Creator.validate_organization_for_invoicing(organization) do
      :ok ->
        issue_date = Date.utc_today()
        invoice_number = SalesInvoices.get_next_invoice_number(issue_date, series: "FK")

        correction_invoice_params =
          Map.merge(correction_invoice_params, %{"invoice_number" => invoice_number, "issue_date" => issue_date})

        SalesInvoices.create_correction_invoice(original_invoice, correction_invoice_params)

      {:error, changeset} ->
        {:error, changeset}
    end
  rescue
    e ->
      Logger.error("Error creating invoice: #{inspect(e)}")
      reraise e, __STACKTRACE__
  end

  defp assign_form_with_preview(socket, changeset) do
    socket = assign(socket, :form, to_form(changeset))

    case Ecto.Changeset.apply_action(changeset, :update) do
      {:ok, preview_invoice} ->
        preview_invoice =
          if preview_invoice.ksef_invoice_kind == :kor do
            original_invoice = socket.assigns.invoice.corrected_invoice || socket.assigns.invoice

            Map.put(preview_invoice, :corrected_invoice, original_invoice)
          else
            preview_invoice
          end

        socket
        |> assign(:preview_invoice, preview_invoice)
        |> assign(:currency_rate, SalesInvoices.get_currency_rate(preview_invoice))
        |> assign(:stale_preview_invoice?, false)
        |> maybe_auto_fill_correction_reason()

      {:error, _reason} ->
        assign(socket, :stale_preview_invoice?, true)
    end
  end

  defp detect_correction_reason_touched(params, socket) do
    if SalesInvoice.draft?(socket.assigns.invoice) do
      socket
    else
      user_reason = Map.get(params, "correction_reason", "")
      last_auto = socket.assigns.last_auto_reason

      if user_reason != last_auto and user_reason != "" do
        assign(socket, :correction_reason_touched, true)
      else
        socket
      end
    end
  end

  defp maybe_auto_fill_correction_reason(socket) do
    if SalesInvoice.draft?(socket.assigns.invoice) or socket.assigns.correction_reason_touched do
      sync_user_reason_to_preview(socket)
    else
      auto_fill_correction_reason(socket)
    end
  end

  defp sync_user_reason_to_preview(socket) do
    preview = socket.assigns[:preview_invoice]
    form_reason = Ecto.Changeset.get_field(socket.assigns.form.source, :correction_reason)

    if preview && form_reason do
      assign(socket, :preview_invoice, Map.put(preview, :correction_reason, form_reason))
    else
      socket
    end
  end

  defp auto_fill_correction_reason(socket) do
    reference = socket.assigns[:reference_invoice] || socket.assigns.invoice
    preview = socket.assigns[:preview_invoice]

    auto_reason =
      if preview do
        CorrectionReason.generate(preview, reference)
      else
        ""
      end

    form = socket.assigns.form
    updated_params = Map.put(form.params || %{}, "correction_reason", auto_reason)
    updated_source = Ecto.Changeset.put_change(form.source, :correction_reason, auto_reason)

    socket
    |> assign(:last_auto_reason, auto_reason)
    |> assign(:preview_invoice, Map.put(preview, :correction_reason, auto_reason))
    |> assign(:form, to_form(%{updated_source | params: updated_params}))
  end

  defp changeset(sales_invoice, params \\ %{}) do
    sales_invoice
    |> Ecto.Changeset.cast(params, [:issue_date, :invoice_number, :ksef_invoice_kind, :correction_reason])
    |> SalesInvoice.step1_changeset(params)
    |> SalesInvoice.step2_changeset(params)
    |> SalesInvoice.step3_changeset(params)
  end

  defp not_editable_message(%SalesInvoice{ksef_invoice_kind: :vat}) do
    "Nie można edytować tej faktury — posiada korekty. Edytuj ostatnią korektę."
  end

  defp not_editable_message(%SalesInvoice{ksef_invoice_kind: :kor}) do
    "Nie można edytować tej korekty — istnieje nowsza korekta."
  end

  defp get_reference_invoice(%SalesInvoice{ksef_invoice_kind: :kor} = invoice) do
    SalesInvoices.get_reference_invoice_for_correction(invoice)
  end

  defp get_reference_invoice(_invoice), do: nil
end
