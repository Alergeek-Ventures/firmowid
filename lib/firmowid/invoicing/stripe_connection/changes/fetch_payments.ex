defmodule Firmowid.Invoicing.StripeConnection.Changes.FetchPayments do
  @moduledoc """
  Records the payments Stripe reported since the connection's last check and moves the check on.

  Stripe's `payment_intent.succeeded` events since `events_since` are read, every page, before
  the transaction, and each payment is recorded (`StripePayment :record`, which issues its
  invoice). The next check starts at the newest event read, not at the time of this one, so an
  event Stripe lists a moment late is still read; the payment it reports again is recorded only
  once. A failed check moves nothing, so the next one reads the same events again.
  """

  use Ash.Resource.Change

  alias Firmowid.Billing.StripeTerms
  alias Firmowid.Invoicing
  alias Firmowid.Scope
  alias Firmowid.SystemActor

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_transaction(changeset, fn %{data: connection} = changeset ->
      with {:ok, events} <- events(connection),
           :ok <- record(events, connection.organization_id) do
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

  defp events(connection, starting_after \\ nil, acc \\ []) do
    params = %{
      type: "payment_intent.succeeded",
      created: %{gte: DateTime.to_unix(connection.events_since)},
      limit: 100
    }

    params = if starting_after, do: Map.put(params, :starting_after, starting_after), else: params

    case StripeTerms.request(:get, "/v1/events", params, api_key: connection.api_key) do
      {:ok, %{"data" => data, "has_more" => true}} ->
        events(connection, List.last(data)["id"], acc ++ data)

      {:ok, %{"data" => data}} ->
        {:ok, acc ++ data}

      {:error, error} ->
        {:error, error}
    end
  end

  defp record(events, organization_id) do
    scope =
      Scope.new!(%SystemActor{org_id: organization_id, role: :stripe_invoicing}, organization_id)

    Enum.reduce_while(events, :ok, fn %{"created" => created, "data" => %{"object" => payment}}, :ok ->
      %{
        payment_intent_id: payment["id"],
        paid_at: DateTime.from_unix!(created),
        amount: StripeTerms.pln(payment["amount_received"]),
        currency: String.upcase(payment["currency"])
      }
      |> Invoicing.record_stripe_payment(scope: scope)
      |> case do
        {:ok, _payment} -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp events_since([], connection), do: connection.events_since

  defp events_since(events, _connection), do: events |> Enum.map(& &1["created"]) |> Enum.max() |> DateTime.from_unix!()
end
