defmodule Firmowid.Billing.Payment.AdvanceInvoice do
  @moduledoc """
  What a paid Stripe invoice puts on its advance invoice (KSeF ZAL).

  Everything about the buyer and the amounts comes from the Stripe invoice: the buyer's name,
  tax id, address and email, the day Stripe took the payment, the currency and the gross amount.
  The line is named by Stripe's description of the largest line and the period it covers. The
  line's net is derived from the gross Stripe took, with 23% VAT.

  Stripe sends the payment receipt and KSeF delivers the invoice, so no invoice email is sent.
  """

  alias Firmowid.Billing.PlanCatalog
  alias Firmowid.Billing.StripeTerms

  @doc """
  Returns the input of the invoicing domain's `:issue` for a paid Stripe invoice, without the
  invoice number. A buyer without a tax id or a line without a description is an error.
  """
  @spec input(map()) :: {:ok, map()} | {:error, String.t()}
  def input(invoice) do
    with {:ok, line} <- line(invoice),
         {:ok, nip} <- buyer_nip(invoice) do
      {:ok,
       %{
         ksef_invoice_kind: :advance,
         currency: String.upcase(invoice["currency"]),
         sale_date: StripeTerms.warsaw_date(invoice["status_transitions"]["paid_at"]),
         payment_method: :card,
         buyer_type: :company,
         buyer_id: nip,
         buyer_full_name: invoice["customer_name"],
         buyer_display_name: invoice["customer_name"],
         buyer_address: address(invoice["customer_address"]),
         buyer_country: invoice["customer_address"]["country"],
         buyer_email: invoice["customer_email"],
         should_send_emails: false,
         sales_invoice_items: [
           %{
             name: "#{line["description"]}, #{period(line["period"])}",
             quantity: Decimal.new(1),
             unit: "szt.",
             # What Stripe took is gross. The line carries the net, not rounded: the invoice rounds
             # its net and its VAT to the grosz separately, and only from the unrounded net do the
             # two always add up to the gross. A net rounded here first would miss it by a grosz for
             # about a fifth of the amounts.
             unit_price: PlanCatalog.without_vat(StripeTerms.pln(invoice["amount_paid"])),
             vat_rate: Integer.to_string(PlanCatalog.vat_percent())
           }
         ]
       }}
    end
  end

  # The largest line is the one the invoice charges for: the new period of a renewal, or the
  # charge a plan switch was prorated for.
  defp line(invoice) do
    case Enum.max_by(invoice["lines"]["data"], & &1["amount"]) do
      %{"description" => description} = line when is_binary(description) -> {:ok, line}
      _line -> {:error, "Stripe invoice #{invoice["id"]} has no line description"}
    end
  end

  defp buyer_nip(invoice) do
    case invoice["customer_tax_ids"] do
      [%{"value" => value} | _rest] -> {:ok, String.replace_prefix(value, "PL", "")}
      _none -> {:error, "Stripe invoice #{invoice["id"]} has no buyer tax id"}
    end
  end

  defp address(%{"line1" => line1, "line2" => line2, "postal_code" => postal_code, "city" => city}) do
    street = if line2, do: "#{line1} #{line2}", else: line1

    "#{street}, #{postal_code} #{city}"
  end

  defp period(%{"start" => start, "end" => end_time}) do
    start_date = StripeTerms.warsaw_date(start)
    # Stripe's period ends at the moment the next one starts.
    end_date = end_time |> StripeTerms.warsaw_date() |> Date.add(-1)
    end_date = Enum.max([start_date, end_date], Date)

    "#{Calendar.strftime(start_date, "%d.%m.%Y")}–#{Calendar.strftime(end_date, "%d.%m.%Y")}"
  end
end
