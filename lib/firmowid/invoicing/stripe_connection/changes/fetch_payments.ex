defmodule Firmowid.Invoicing.StripeConnection.Changes.FetchPayments do
  @moduledoc """
  Records the payments and refunds Stripe reported since the connection's last check and moves
  the check on.

  Stripe's `payment_intent.succeeded` and `charge.refunded` events since `events_since` are
  read, every page, before the transaction. Each payment is recorded (`StripePayment :record`,
  which issues its invoice), then each succeeded refund of a charge whose payment is recorded
  (`StripeRefund :record`, which corrects the invoice); a refund of a payment from before the
  connection is not the integration's. The next check starts at the newest event read, not at
  the time of this one, so an event Stripe lists a moment late is still read; the payment or
  refund it reports again is recorded only once. A failed check moves nothing, so the next one
  reads the same events again.
  """

  use Ash.Resource.Change

  alias Firmowid.Billing.StripeTerms
  alias Firmowid.Invoicing
  alias Firmowid.Invoicing.StripePayment
  alias Firmowid.Scope
  alias Firmowid.SystemActor

  require Ash.Query

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_transaction(changeset, fn %{data: connection} = changeset ->
      scope =
        Scope.new!(
          %SystemActor{org_id: connection.organization_id, role: :stripe_invoicing},
          connection.organization_id
        )

      with {:ok, events} <- events(connection),
           :ok <- record_payments(events, scope),
           :ok <- record_refunds(events, connection, scope) do
        Ash.Changeset.force_change_attribute(
          changeset,
          :events_since,
          events_since(events, connection)
        )
      else
        {:error, error} -> Ash.Changeset.add_error(changeset, error)
      end
    end)
  end

  defp events(connection) do
    StripeTerms.list(request(connection), "/v1/events", %{
      types: ["payment_intent.succeeded", "charge.refunded"],
      created: %{gte: DateTime.to_unix(connection.events_since)}
    })
  end

  defp record_payments(events, scope) do
    events
    |> Enum.filter(&(&1["type"] == "payment_intent.succeeded"))
    |> each(fn %{"created" => created, "data" => %{"object" => payment}} ->
      Invoicing.record_stripe_payment(
        %{
          payment_intent_id: payment["id"],
          paid_at: DateTime.from_unix!(created),
          amount: StripeTerms.pln(payment["amount_received"]),
          currency: String.upcase(payment["currency"])
        },
        scope: scope
      )
    end)
  end

  # A charge's event lists no refunds, so they are read from Stripe; the ones already recorded
  # are recorded only once.
  defp record_refunds(events, connection, scope) do
    charges =
      for %{"type" => "charge.refunded", "data" => %{"object" => charge}} <- events,
          uniq: true,
          do: {charge["id"], charge["payment_intent"]}

    with {:ok, recorded} <- recorded_payments(Enum.map(charges, &elem(&1, 1)), scope) do
      charges
      |> Enum.filter(fn {_charge_id, payment_intent_id} -> payment_intent_id in recorded end)
      |> each(fn {charge_id, _payment_intent_id} ->
        record_charge_refunds(charge_id, connection, scope)
      end)
    end
  end

  defp recorded_payments([], _scope), do: {:ok, []}

  defp recorded_payments(payment_intent_ids, scope) do
    StripePayment
    |> Ash.Query.filter(payment_intent_id in ^payment_intent_ids)
    |> Ash.Query.select([:payment_intent_id])
    |> Ash.read(scope: scope)
    |> case do
      {:ok, payments} -> {:ok, Enum.map(payments, & &1.payment_intent_id)}
      {:error, error} -> {:error, error}
    end
  end

  defp record_charge_refunds(charge_id, connection, scope) do
    with {:ok, refunds} <-
           StripeTerms.list(request(connection), "/v1/refunds", %{charge: charge_id}) do
      # Oldest first, so each correction follows the ones before it.
      refunds
      |> Enum.filter(&(&1["status"] == "succeeded"))
      |> Enum.reverse()
      |> each(fn refund ->
        Invoicing.record_stripe_refund(
          %{
            refund_id: refund["id"],
            payment_intent_id: refund["payment_intent"],
            refunded_at: DateTime.from_unix!(refund["created"]),
            amount: StripeTerms.pln(refund["amount"]),
            currency: String.upcase(refund["currency"])
          },
          scope: scope
        )
      end)
    end
  end

  defp each(items, fun) do
    Enum.reduce_while(items, :ok, fn item, :ok ->
      case fun.(item) do
        {:ok, _recorded} -> {:cont, :ok}
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp request(connection), do: &StripeTerms.request(:get, &1, &2, api_key: connection.api_key)

  defp events_since([], connection), do: connection.events_since

  defp events_since(events, _connection), do: events |> Enum.map(& &1["created"]) |> Enum.max() |> DateTime.from_unix!()
end
