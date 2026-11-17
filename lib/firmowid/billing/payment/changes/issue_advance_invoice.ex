defmodule Firmowid.Billing.Payment.Changes.IssueAdvanceInvoice do
  @moduledoc """
  Issues the advance invoice (KSeF ZAL) for a paid payment and marks the payment invoiced.

  The seller is the organization configured as `:billing` `:seller_organization_id`; the
  invoice is issued in its tenant by the invoicing domain's own `:issue`, so it is numbered,
  queued for KSeF and, once KSeF confirms it, emailed to the buyer like any other invoice.
  The buyer is the paying organization, the payment date is the sale date. Invoice emails go
  to the invoice's counterparty, so the buyer is first found among the seller's counterparties
  by NIP (restored if archived, given the payer's email when it has none), or added there
  with it.
  An upgrade payment's line names the plan change and the period its difference pays for.

  The invoice takes the payment's id and is issued in the payment's transaction, so either
  both the invoice and `invoiced_at` are saved or neither is. A buyer without an address or a
  seller without a KSeF connection fails the issue, and the hourly trigger tries again.
  """

  use Ash.Resource.Change

  alias Ash.Resource.Change.Context
  alias Firmowid.Billing
  alias Firmowid.Billing.PlanCatalog
  alias Firmowid.Invoicing
  alias Firmowid.Invoicing.Counterparty
  alias Firmowid.Invoicing.SalesInvoice
  alias Firmowid.Invoicing.TaxId
  alias Firmowid.LocalDate
  alias Firmowid.Scope
  alias Firmowid.SystemActor

  require Ash.Query

  @doc "Issues the advance invoice inside the payment's transaction and sets `invoiced_at`."
  @spec change(Ash.Changeset.t(), keyword(), Context.t()) :: Ash.Changeset.t()
  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, &issue/1)
  end

  defp issue(changeset) do
    payment = changeset.data
    seller_scope = seller_scope()

    with {:ok, payment} <-
           Ash.load(payment, [:organization, :payer_email, :period_label], scope: Billing.scope(payment.organization_id)),
         {:ok, counterparty} <- buyer_counterparty(payment, seller_scope),
         {:ok, invoice_number} <-
           SalesInvoice.get_next_number(LocalDate.today(), nil, nil, scope: seller_scope),
         {:ok, _invoice} <-
           Invoicing.issue_sales_invoice(
             %{confirmation_id: payment.id, input: input(payment, counterparty, invoice_number)},
             scope: seller_scope
           ) do
      Ash.Changeset.force_change_attribute(changeset, :invoiced_at, DateTime.utc_now())
    else
      {:error, error} -> Ash.Changeset.add_error(changeset, error)
    end
  end

  # A counterparty may store the NIP with or without the PL prefix. An archived one is restored,
  # since a second counterparty with its NIP cannot be added. The invoice email goes to the
  # counterparty's email: one the seller entered (an accounting address) stays, a missing one
  # becomes the payer's.
  defp buyer_counterparty(payment, seller_scope) do
    buyer = payment.organization
    nip = TaxId.normalize(buyer.nip)
    payer_email = to_string(payment.payer_email)

    query =
      Ash.Query.filter(
        Counterparty,
        type == :company and country == "PL" and normalized_tax_id in ^[nip, "PL" <> nip]
      )

    case Counterparty.list(%{status: :all}, query: query, scope: seller_scope) do
      {:ok, []} ->
        Invoicing.create_counterparty(
          %{
            type: :company,
            tax_id: buyer.nip,
            full_name: buyer.name,
            display_name: buyer.display_name,
            address: buyer.address,
            country: "PL",
            email: payer_email
          },
          scope: seller_scope
        )

      {:ok, counterparties} ->
        counterparty = Enum.find(counterparties, &is_nil(&1.archived_at)) || hd(counterparties)

        with {:ok, counterparty} <- restore(counterparty, seller_scope) do
          fill_email(counterparty, payer_email, seller_scope)
        end

      {:error, error} ->
        {:error, error}
    end
  end

  defp restore(%{archived_at: nil} = counterparty, _seller_scope), do: {:ok, counterparty}

  defp restore(counterparty, seller_scope), do: Invoicing.unarchive_counterparty(counterparty, scope: seller_scope)

  defp fill_email(%{email: nil} = counterparty, payer_email, seller_scope),
    do: Invoicing.update_counterparty(counterparty, %{email: payer_email}, scope: seller_scope)

  defp fill_email(counterparty, _payer_email, _seller_scope), do: {:ok, counterparty}

  defp input(payment, counterparty, invoice_number) do
    buyer = payment.organization

    %{
      ksef_invoice_kind: :advance,
      counterparty_id: counterparty.id,
      invoice_number: invoice_number,
      issue_date: LocalDate.today(),
      sale_date: payment_date(payment.paid_at),
      payment_method: :card,
      buyer_type: :company,
      buyer_id: buyer.nip,
      buyer_full_name: buyer.name,
      buyer_display_name: buyer.display_name,
      buyer_address: buyer.address,
      buyer_country: "PL",
      buyer_email: to_string(payment.payer_email),
      should_send_emails: true,
      sales_invoice_items: [
        %{
          name: line_name(payment),
          quantity: Decimal.new(1),
          unit: "szt.",
          unit_price: payment.net_amount,
          vat_rate: payment.vat_rate
        }
      ]
    }
  end

  defp line_name(%{kind: :upgrade} = payment),
    do: "Firmowid — zmiana planu na #{PlanCatalog.name(payment.plan)}, dopłata za #{payment.period_label}"

  defp line_name(payment), do: "Firmowid — plan #{PlanCatalog.name(payment.plan)}, #{payment.period_label}"

  # The card was charged on this day in Poland, as `Firmowid.LocalDate` counts days.
  defp payment_date(paid_at) do
    paid_at |> DateTime.shift_zone!("Europe/Warsaw") |> DateTime.to_date()
  end

  defp seller_scope do
    seller_id =
      :firmowid |> Application.fetch_env!(:billing) |> Keyword.fetch!(:seller_organization_id)

    Scope.new!(%SystemActor{org_id: seller_id, role: :sales_invoice_processor}, seller_id)
  end
end
