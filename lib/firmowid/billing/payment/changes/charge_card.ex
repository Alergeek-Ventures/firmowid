defmodule Firmowid.Billing.Payment.Changes.ChargeCard do
  @moduledoc """
  Charges the subscription's saved card at Tpay for the attempt `:charge` claims.

  Before the claim it signs in to Tpay and builds the whole charge (card, payer, amount,
  description), so a failure there, such as Tpay being unreachable, leaves the payment as
  it was. The claim then commits on its own, and only after that Tpay is asked, once:
  whatever happens next, the payment says `:charging` and is never charged again for that
  attempt. Tpay's answer goes to `:record_outcome`. A request Tpay refuses as invalid
  (`{:rejected, ...}` from `Firmowid.Billing.Tpay.Client.charge/2`), such as for a card token
  it cannot use, is recorded there as a declined attempt without a transaction, so a permanent
  refusal runs out of attempts like a declined card, and the error is reported; any other
  failure leaves the payment `:charging` for reconciliation and is reported too.

  It refuses to run inside another transaction: the claim would join it and stay
  uncommitted while the card is charged.
  """

  use Ash.Resource.Change

  alias Ash.Resource.Change.Context
  alias Firmowid.Billing
  alias Firmowid.Billing.PlanCatalog
  alias Firmowid.Billing.Tpay.Client
  alias FirmowidWeb.Core.Endpoint

  @doc "Prepares the charge before the claim and charges the card after it commits."
  @spec change(Ash.Changeset.t(), keyword(), Context.t()) :: Ash.Changeset.t()
  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_transaction(changeset, &prepare_charge/1)
  end

  defp prepare_charge(changeset) do
    if Ash.DataLayer.in_transaction?(changeset.resource) do
      raise ArgumentError,
            "a payment must be charged outside any transaction, after its claim commits"
    end

    scope = Billing.scope(changeset.data.organization_id)

    with {:ok, payment} <-
           Ash.load(changeset.data, [:payer_email, :period_label, :organization, :subscription], scope: scope),
         {:ok, access_token} <- Client.access_token() do
      params = charge_params(payment)

      Ash.Changeset.after_transaction(changeset, fn _changeset, result ->
        charge(result, params, access_token, scope)
      end)
    else
      {:error, error} -> Ash.Changeset.add_error(changeset, error)
    end
  end

  defp charge_params(payment) do
    %{
      payment_id: payment.id,
      card_token: payment.subscription.card_token,
      amount: payment.gross_amount,
      description: description(payment),
      payer: %{email: to_string(payment.payer_email), name: payment.organization.display_name},
      notification_url: Endpoint.url() <> "/webhooks/tpay"
    }
  end

  # `claimed` is the payment as the claim left it, with the attempt it counts.
  defp charge({:ok, claimed}, params, access_token, scope) do
    case Client.charge(access_token, Map.put(params, :attempt, claimed.attempts)) do
      {:ok, transaction} ->
        Billing.record_payment_outcome(
          claimed,
          %{
            outcome: transaction.outcome,
            transaction_id: transaction.transaction_id,
            attempt: claimed.attempts,
            paid_at: transaction.paid_at
          },
          scope: scope
        )

      {:error, {:rejected, _status, _body} = error} ->
        with {:ok, _declined} <-
               Billing.record_payment_outcome(
                 claimed,
                 %{outcome: :declined, transaction_id: nil, attempt: claimed.attempts},
                 scope: scope
               ) do
          {:error, error}
        end

      {:error, error} ->
        {:error, error}
    end
  end

  # The claim failed: another caller claimed the attempt or the payment is not due.
  defp charge({:error, error}, _params, _access_token, _scope), do: {:error, error}

  defp description(payment), do: "Firmowid, plan #{PlanCatalog.name(payment.plan)}, #{payment.period_label}"
end
