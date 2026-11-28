defmodule Firmowid.Invoicing.StripePayment.InvoiceInput do
  @moduledoc """
  What a successful Stripe payment puts on its invoice, read from the company's Stripe account.

  A payment comes from one of three places, tried in this order:

  - a Stripe invoice it paid (also a Checkout that creates invoices): its lines and buyer;
  - a Checkout Session: its line items, its shipping and the details the buyer typed;
  - neither: one line named by the payment's description, and the buyer of its customer or of
    the card's billing details.

  Every line carries what the buyer paid for it. Its VAT rate is the one Stripe charged (the KSeF
  rate nearest to Stripe's tax over the taxed amount). Firmowid does not guess a rate: a VAT
  payer's payment with a line Stripe charged no tax on (a zero tax included, which can be 0%, an
  exemption or a reverse charge) gets no invoice (`:untaxed`), so the company sets the tax in
  Stripe; a company outside VAT invoices every line `zw`. `Changes.IssueInvoice` checks that the
  invoice adds up to what Stripe took.

  A buyer with a tax ID is a company; one without is a private person, invoiced only when the
  company chose so (`:skip` otherwise). The invoice is issued as paid by card on the day of the
  payment, and KSeF delivers it, so no invoice email is sent.
  """

  alias Firmowid.Billing.StripeTerms

  @rates [23, 8, 5]

  @doc """
  Returns the `:issue` input (without the invoice number) for the payment intent, `:skip` for a
  buyer without a tax ID when private persons are not invoiced, `:untaxed` for a VAT payer's
  payment with a line Stripe charged no tax on, or an error.
  """
  @spec build(String.t(), String.t(), %{invoice_consumers: boolean(), is_vat_payer: boolean()}) ::
          {:ok, map() | :skip | :untaxed} | {:error, term()}
  def build(payment_intent_id, api_key, settings) do
    request = &StripeTerms.request(:get, &1, &2, api_key: api_key)

    with {:ok, payment} <-
           request.("/v1/payment_intents/#{payment_intent_id}", %{
             expand: ["customer", "customer.tax_ids", "latest_charge"]
           }),
         {:ok, {lines, buyer}} <- source(payment, request) do
      cond do
        buyer.tax_ids == [] and not settings.invoice_consumers ->
          {:ok, :skip}

        settings.is_vat_payer and Enum.any?(lines, &is_nil(&1.tax)) ->
          {:ok, :untaxed}

        true ->
          with {:ok, items} <- items(lines), do: {:ok, input(payment, items, buyer)}
      end
    end
  end

  defp source(payment, request) do
    with {:ok, %{"data" => invoice_payments}} <-
           request.("/v1/invoice_payments", %{
             payment: %{type: "payment_intent", payment_intent: payment["id"]},
             expand: ["data.invoice"]
           }),
         {:ok, %{"data" => sessions}} <-
           request.("/v1/checkout/sessions", %{payment_intent: payment["id"]}) do
      case {invoice_payments, sessions} do
        {[%{"invoice" => invoice} | _rest], _sessions} -> invoice_source(invoice, request)
        {[], [session | _rest]} -> session_source(session, request)
        {[], []} -> {:ok, {[payment_line(payment)], payment_buyer(payment)}}
      end
    end
  end

  defp invoice_source(invoice, request) do
    with {:ok, lines} <- list(request, "/v1/invoices/#{invoice["id"]}/lines") do
      buyer = %{
        name: invoice["customer_name"],
        email: invoice["customer_email"],
        address: invoice["customer_address"],
        tax_ids: invoice["customer_tax_ids"] || []
      }

      {:ok, {Enum.map(lines, &invoice_line/1) ++ shipping_line(invoice["shipping_cost"]), buyer}}
    end
  end

  # The tax Stripe charged on a line is given with the amount it was charged on; a line without
  # tax charges its amount less its discounts. A zero tax is no tax charged; a credit line of a
  # plan change carries a negative one.
  defp invoice_line(line) do
    case line["taxes"] do
      [%{"amount" => tax, "taxable_amount" => taxed} | _rest] when tax != 0 ->
        %{
          name: line["description"],
          quantity: line["quantity"] || 1,
          gross: taxed + tax,
          tax: {tax, taxed}
        }

      _none ->
        discounts = Enum.sum_by(line["discount_amounts"] || [], & &1["amount"])

        %{
          name: line["description"],
          quantity: line["quantity"] || 1,
          gross: line["amount"] - discounts,
          tax: nil
        }
    end
  end

  defp session_source(session, request) do
    with {:ok, items} <- list(request, "/v1/checkout/sessions/#{session["id"]}/line_items") do
      details = session["customer_details"] || %{}

      buyer = %{
        name: details["business_name"] || details["name"],
        email: details["email"],
        address: details["address"],
        tax_ids: details["tax_ids"] || []
      }

      {:ok, {Enum.map(items, &session_line/1) ++ shipping_line(session["shipping_cost"]), buyer}}
    end
  end

  defp session_line(item) do
    %{
      name: item["description"],
      quantity: item["quantity"] || 1,
      gross: item["amount_total"],
      tax: tax(item)
    }
  end

  defp shipping_line(%{"amount_total" => gross} = shipping) when gross > 0,
    do: [%{name: "Wysyłka", quantity: 1, gross: gross, tax: tax(shipping)}]

  defp shipping_line(_none), do: []

  defp tax(%{"amount_tax" => tax, "amount_total" => gross}) when tax > 0, do: {tax, gross - tax}
  defp tax(_untaxed), do: nil

  defp payment_line(payment) do
    %{
      name: payment["description"] || "Płatność #{payment["id"]}",
      quantity: 1,
      gross: payment["amount_received"],
      tax: nil
    }
  end

  defp payment_buyer(%{"customer" => %{"name" => name} = customer}) when is_binary(name) do
    %{
      name: name,
      email: customer["email"],
      address: customer["address"],
      tax_ids: get_in(customer, ["tax_ids", "data"]) || []
    }
  end

  defp payment_buyer(payment) do
    details = payment["latest_charge"]["billing_details"]
    %{name: details["name"], email: details["email"], address: details["address"], tax_ids: []}
  end

  # Every page of a list of at most a hundred lines a page.
  defp list(request, path, params \\ %{limit: 100}, acc \\ []) do
    case request.(path, params) do
      {:ok, %{"data" => data, "has_more" => true}} ->
        list(request, path, Map.put(params, :starting_after, List.last(data)["id"]), acc ++ data)

      {:ok, %{"data" => data}} ->
        {:ok, acc ++ data}

      {:error, error} ->
        {:error, error}
    end
  end

  defp items(lines) do
    Enum.reduce_while(lines, {:ok, []}, fn line, {:ok, items} ->
      case item(line) do
        {:ok, item} -> {:cont, {:ok, items ++ [item]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp item(%{name: name}) when name in [nil, ""], do: {:error, "a Stripe line has no description"}

  # Only a company outside VAT gets here with an untaxed line.
  defp item(%{tax: nil} = line), do: {:ok, item(line, StripeTerms.pln(line.gross), "zw")}

  # Stripe gives the net it charged its tax on, so the line keeps it. Stripe rounds the tax to
  # the grosz, so the rate is the one nearest to it.
  defp item(%{tax: {tax, taxed}} = line) do
    rate = Enum.min_by(@rates, &abs(taxed * &1 - tax * 100))
    {:ok, item(line, StripeTerms.pln(taxed), Integer.to_string(rate))}
  end

  defp item(line, net, vat_rate) do
    %{
      name: line.name,
      quantity: Decimal.new(line.quantity),
      unit: "szt.",
      unit_price: Decimal.div(net, line.quantity),
      vat_rate: vat_rate
    }
  end

  defp input(payment, items, buyer) do
    case buyer.tax_ids do
      [] -> Map.merge(common(payment, items, buyer), individual(buyer.name))
      [tax_id | _rest] -> Map.merge(common(payment, items, buyer), company(buyer, tax_id))
    end
  end

  # The payment of a Stripe invoice can be made long after its payment intent was created; the
  # charge is the moment the buyer paid.
  defp common(payment, items, buyer) do
    paid_on = StripeTerms.warsaw_date(payment["latest_charge"]["created"])

    %{
      currency: String.upcase(payment["currency"]),
      sale_date: paid_on,
      paid_on: paid_on,
      payment_method: :card,
      buyer_address: address(buyer.address),
      buyer_country: (buyer.address || %{})["country"] || "PL",
      buyer_email: buyer.email,
      should_send_emails: false,
      sales_invoice_items: items
    }
  end

  defp company(buyer, %{"value" => value}) do
    %{
      buyer_type: :company,
      buyer_id: String.replace_prefix(value, "PL", ""),
      buyer_full_name: buyer.name,
      buyer_display_name: buyer.name
    }
  end

  # Stripe keeps one name; its last word is the surname.
  defp individual(name) do
    {given_name, surname} =
      case name |> to_string() |> String.split() do
        [] -> {nil, nil}
        [surname] -> {nil, surname}
        words -> {words |> Enum.drop(-1) |> Enum.join(" "), List.last(words)}
      end

    %{
      buyer_type: :individual,
      buyer_given_name: given_name,
      buyer_surname: surname,
      buyer_display_name: name
    }
  end

  defp address(%{"line1" => line1, "postal_code" => postal_code, "city" => city} = address) when is_binary(line1) do
    street = if address["line2"], do: "#{line1} #{address["line2"]}", else: line1
    "#{street}, #{postal_code} #{city}"
  end

  defp address(_none), do: nil
end
