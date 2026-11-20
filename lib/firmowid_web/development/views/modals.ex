defmodule FirmowidWeb.Development.Views.Modals do
  @moduledoc """
  Development-only gallery of every modal in the app, open one under another, to
  compare their headers and chrome. Each modal uses the real `modal/1` with the
  heading markup copied from its source (named above it); bodies that need records
  are shortened to a placeholder, and the delegation documents modal is the real
  component.
  """
  use FirmowidWeb, :live_view

  import FirmowidUI.Components.Link
  import FirmowidWeb.Delegations.Components.Settlement.Documents, only: [documents_modal: 1]
  import Phoenix.Component, except: [link: 1]

  @guide_path "/development"

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Modale", guide_path: @guide_path)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto flex max-w-4xl flex-col gap-10 p-8">
      <header class="flex flex-col gap-2">
        <.link navigate={@guide_path} kind="text">← Development</.link>
        <h1 class="text-2xl font-medium">Modale</h1>
        <p class="text-sm text-grey-700">
          Wszystkie modale aplikacji, otwarte. Nagłówki są jak w kodzie; treść wymagająca danych jest skrócona.
        </p>
      </header>

      <.frame source="lib/firmowid_web/feedback/components/form.ex">
        <.modal id="gallery-feedback">
          <:header>
            <h2 class="mb-2 text-xl font-semibold">{gettext("Share your feedback")}</h2>
            <p class="text-sm text-grey-700">
              {gettext(
                "Your opinion helps us develop Firmowid. Tell us what we can improve, what works well, or what you are missing."
              )}
            </p>
          </:header>
          <.body_placeholder text="Pole tekstowe i przyciski" />
        </.modal>
      </.frame>

      <.frame source="lib/firmowid_web/settings/components/account_tab.ex">
        <.modal id="gallery-close-account">
          <:header>
            <h3 class="text-lg font-semibold text-grey-900">
              Czy na pewno chcesz zamknąć konto? <b>{gettext("This cannot be undone.")}</b>
            </h3>
          </:header>
          <p class="text-sm text-grey-700">
            {gettext("We will delete your account and all data assigned to it.")}
          </p>
          <.body_placeholder text="Przyciski" class="mt-6" />
        </.modal>
      </.frame>

      <.frame source="lib/firmowid_web/settings/components/company_tab.ex (usunięcie konta bankowego)">
        <.modal id="gallery-delete-bank-account">
          <:header>
            <h3 class="text-lg font-semibold text-grey-900">{gettext("Confirm deletion")}</h3>
            <p class="mt-3 text-sm text-grey-700">
              {gettext(
                "Are you sure you want to delete this bank account? We will also delete the related transactions."
              )}
            </p>
          </:header>
          <.body_placeholder text="Przyciski" />
        </.modal>
      </.frame>

      <.frame source="lib/firmowid_web/settings/components/company_tab.ex (konto ręczne)">
        <.modal id="gallery-manual-bank-account">
          <:header>
            <h3 class="text-lg font-semibold text-grey-900">
              {gettext("Add a bank account manually")}
            </h3>
            <p class="mt-2 text-sm text-grey-700">
              {gettext(
                "This feature lets you add an account without a bank integration. Transaction synchronization will be disabled."
              )}
            </p>
          </:header>
          <.body_placeholder text="Formularz konta" />
        </.modal>
      </.frame>

      <.frame source="lib/firmowid_web/settings/components/profile_tab.ex">
        <.modal id="gallery-leave-request" class="max-w-xl">
          <:header>
            <h2 class="text-xl font-medium">{gettext("Absence request")}</h2>
          </:header>
          <.body_placeholder text="Formularz wniosku" />
        </.modal>
      </.frame>

      <.frame source="lib/firmowid_web/timetracker/views/index.html.heex">
        <.modal id="gallery-overlap">
          <:header>
            <h3 class="text-lg font-bold text-grey-900">{gettext("Overlapping sessions")}</h3>
            <p class="mt-1 text-sm text-grey-700">
              {gettext("The new session overlaps existing ones. Saving requires the changes below:")}
            </p>
          </:header>
          <.body_placeholder text="Podgląd sesji i zmian" />
        </.modal>
      </.frame>

      <.frame source="lib/firmowid_web/hours_record/components/upload_form.ex">
        <.modal id="gallery-sign-warning">
          <:header>
            <h2 class="mb-6 font-bold">{gettext("Check your hours before signing")}</h2>
            <p>
              {gettext(
                "Check the month, hours and your details in the downloaded document. Submitting the signed record will lock editing of this month's hours. Later changes require a correction or cancellation request to your organization administrators."
              )}
            </p>
          </:header>
          <.body_placeholder text="Przyciski" />
        </.modal>
      </.frame>

      <.frame source="lib/firmowid_web/hours_record/views/index.html.heex">
        <.modal id="gallery-change-request">
          <:header>
            <h2 class="mb-6 font-bold">{gettext("Request correction or cancellation")}</h2>
            <p>
              {gettext(
                "Your request will be saved and emailed to your organization administrators. It does not cancel the signature or unlock hours automatically."
              )}
            </p>
          </:header>
          <.body_placeholder text="Formularz wniosku" />
        </.modal>
      </.frame>

      <.frame source="lib/firmowid_web/management/components/employee_tax_details.ex">
        <.modal id="gallery-declarations" class="max-w-xl!">
          <:header>
            <h2 class="text-lg/snug font-medium">{gettext("Declaration history")}</h2>
            <p class="mt-2 text-sm/snug text-grey-600">
              {gettext("Choose a date to see the employee's declarations.")}
            </p>
          </:header>
          <.body_placeholder text="Lista deklaracji" />
        </.modal>
      </.frame>

      <.frame source="lib/firmowid_web/management/components/employee_payout_details.ex">
        <.modal id="gallery-rate-history">
          <:header>
            <h2 class="text-xl font-medium">{gettext("Rate history")}</h2>
          </:header>
          <.body_placeholder text="Lista stawek" />
        </.modal>
      </.frame>

      <.frame source="lib/firmowid_web/management/components/roles.ex (zaproszenie)">
        <.modal id="gallery-invite" class="max-w-lg">
          <:header>
            <h3 class="mb-8 text-xl font-medium">{gettext("Invite a new employee")}</h3>
            <p>
              {gettext(
                "Choose a role, then generate a code. An employee who enters it when creating an account will automatically join your organization."
              )}
            </p>
          </:header>
          <.body_placeholder text="Wybór roli i kod" />
        </.modal>
      </.frame>

      <.frame source="lib/firmowid_web/management/components/roles.ex (zmiana roli)">
        <.modal id="gallery-role" class="max-w-lg">
          <:header>
            <h3 class="mb-8 text-xl font-medium">{gettext("Changing the role")}</h3>
            <p>
              {gettext("You are changing the role of user %{user}. Their current role is:",
                user: "Jan Kowalski"
              )}
            </p>
          </:header>
          <.body_placeholder text="Wybór roli" />
        </.modal>
      </.frame>

      <.frame source="lib/firmowid_web/management/components/leaves_tab.ex">
        <.modal id="gallery-leave-review">
          <:header>
            <div class="flex items-center gap-3">
              <span class="flex size-6.5 shrink-0 items-center justify-center rounded bg-grey-100 text-grey-700">
                <Lucideicons.sun class="size-4" />
              </span>
              <div class="flex min-w-0 flex-wrap items-center gap-x-3 gap-y-1">
                <h2 class="font-medium">Urlop wypoczynkowy</h2>
                <span class="inline text-grey-500">|</span>
                <span class="text-base font-medium text-grey-600 tabular-nums">3–7 lis</span>
              </div>
            </div>
          </:header>
          <.body_placeholder text="Treść wniosku i decyzja" />
        </.modal>
      </.frame>

      <.frame source="lib/firmowid_web/delegations/components/settlement/documents.ex (prawdziwy komponent)">
        <.documents_modal id="gallery-documents" title="Transport" icon={nil} kind="transport" />
      </.frame>

      <.frame source="lib/firmowid_web/management/views/project.html.heex">
        <.modal id="gallery-delete-project">
          <:header>
            <h3 class="mb-6 text-lg font-medium">Czy na pewno chcesz usunąć projekt Acme?</h3>
            <p class="text-sm text-grey-700">
              {gettext(
                "This operation is irreversible. All data related to this project will be permanently deleted."
              )}
            </p>
          </:header>
          <.body_placeholder text="Przyciski" />
        </.modal>
      </.frame>

      <.frame source="lib/firmowid_web/invoicing/sales_invoices/components/invoice_payment.ex">
        <.modal id="gallery-change-account" class="max-w-4xl">
          <:header>
            <h2 class="mb-2 text-xl font-medium">{gettext("Change account")}</h2>
            <p class="text-grey-600">{gettext("Choose the bank account to receive the payment.")}</p>
          </:header>
          <.body_placeholder text="Lista kont" />
        </.modal>
      </.frame>

      <.frame source="lib/firmowid_web/invoicing/sales_invoices/views/creator_counterparty.html.heex">
        <.modal id="gallery-counterparty">
          <:header>
            <h2 class="text-xl font-semibold text-grey-900">
              {gettext("Enter the counterparty details")}
            </h2>
          </:header>
          <.body_placeholder text="Formularz kontrahenta" />
        </.modal>
      </.frame>

      <.frame source="lib/firmowid_web/invoicing/sales_invoices/views/edit_form.html.heex">
        <.modal id="gallery-buyer">
          <:header>
            <h2 class="text-xl font-semibold text-grey-900">{gettext("Edit buyer details")}</h2>
          </:header>
          <.body_placeholder text="Formularz nabywcy" />
        </.modal>
      </.frame>

      <.frame source="lib/firmowid_web/invoicing/components/invoice_download_modal.ex">
        <.modal id="gallery-invoice-download">
          <:header>
            <h3 class="text-lg font-semibold">{gettext("Download PDF")}</h3>
            <p class="mt-2 text-sm text-grey-700">
              {gettext("Choose whether to include the page with the internal comment.")}
            </p>
          </:header>
          <.body_placeholder text="Przełącznik i przyciski" />
        </.modal>
      </.frame>

      <.frame source="lib/firmowid_web/invoicing/components/download_modal.ex">
        <.modal id="gallery-download">
          <:header>
            <h3 class="mb-8 text-lg font-semibold text-balance">{gettext("Download invoices")}</h3>
            <p class="text-pretty">Wybierz dokumenty z listopada 2026, które chcesz pobrać.</p>
          </:header>
          <.body_placeholder text="Wybór dokumentów i przyciski" />
        </.modal>
      </.frame>

      <.frame source="lib/firmowid_web/invoicing/components/bank_transfer_modal.ex">
        <.modal id="gallery-transfer" class="max-w-[1000px]">
          <:header>
            <h3 class="text-lg font-semibold">{gettext("Transfer details")}</h3>
          </:header>
          <.body_placeholder text="Dane przelewu i kod QR" />
        </.modal>
      </.frame>
      <.frame source="lib/firmowid_web/invoicing/components/sales_invoice_details.ex i cost_invoice_details.ex (usunięcie, anulowanie)">
        <.modal id="gallery-delete-invoice">
          <p>Czy na pewno chcesz usunąć fakturę <span class="font-semibold">FV/1/2026</span>?</p>
          <.body_placeholder text="Przyciski" class="mt-6" />
        </.modal>
      </.frame>
    </div>
    """
  end

  attr :source, :string, required: true
  slot :inner_block, required: true

  # Shows an open modal in the flow of the page: the overlay is the frame's own
  # backdrop instead of a fixed layer over the whole window.
  defp frame(assigns) do
    ~H"""
    <section class="flex flex-col gap-2">
      <p class="font-mono text-xs text-grey-500">{@source}</p>
      <div class="rounded-sm bg-black/60 [&_.fixed]:relative! **:[[id$=-bg]]:hidden! **:[[id$=-container]]:block! [&>div]:block!">
        {render_slot(@inner_block)}
      </div>
    </section>
    """
  end

  attr :text, :string, required: true
  attr :class, :any, default: nil

  defp body_placeholder(assigns) do
    ~H"""
    <div class={[
      "grid h-20 place-items-center rounded-sm border border-dashed border-grey-300 text-sm text-grey-500",
      @class
    ]}>
      {@text}
    </div>
    """
  end
end
