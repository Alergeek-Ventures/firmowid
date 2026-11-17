defmodule FirmowidWeb.Billing.Controllers.TpayNotification do
  @moduledoc """
  Receives Tpay notifications (https://docs-api.tpay.com/en/webhooks/).

  Every notification must carry a valid detached JWS of its raw body. A card tokenization
  activates the subscription awaiting that card; a transaction notification makes the payment
  attempt it names record what Tpay states about that transaction when asked with our
  credentials, since the signature proves only that Tpay sent it, not that the transaction is
  ours (see `Firmowid.Billing.Payment.Changes.FetchOutcome`); a refund is logged as an error for
  a human; a card token update and other notifications are only acknowledged, an unknown type
  with a warning. A transaction that is not the named attempt's is acknowledged with a warning.
  Tpay resends a notification until it gets the expected answer: `{"result":true}` for JSON
  and `TRUE` for form-encoded transaction notifications.
  """
  use FirmowidWeb, :controller

  alias Ash.Error.Changes.InvalidArgument
  alias Firmowid.Billing
  alias Firmowid.Billing.Tpay.Client
  alias Firmowid.Billing.Tpay.Signature

  require Logger

  @doc "Verifies the notification's signature, handles it and answers Tpay."
  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, _params) do
    # Only the signed body is dispatched: query parameters are not covered by the signature.
    # A body that is neither JSON nor a form is not parsed, so it has no raw body and is rejected.
    with %{raw_body: raw_body} <- conn.private,
         [jws] <- get_req_header(conn, "x-jws-signature"),
         :ok <- Signature.verify(raw_body, jws) do
      handle(conn, conn.body_params)
    else
      _invalid ->
        Logger.warning("Rejected a Tpay notification without a valid signature")
        send_resp(conn, 400, "")
    end
  end

  defp handle(conn, %{"type" => "tokenization", "data" => data}) do
    save_card(data)
    json(conn, %{result: true})
  end

  # A card token update needs no action yet.
  defp handle(conn, %{"type" => "token_update"}), do: json(conn, %{result: true})

  # Acknowledged so Tpay stops resending it; the type alone, since the body may carry card data.
  defp handle(conn, %{"type" => type}) do
    Logger.warning("Acknowledged a Tpay notification of an unhandled type: #{inspect(type)}")
    json(conn, %{result: true})
  end

  defp handle(conn, %{"tr_id" => _transaction_id} = params) do
    case Client.transaction_notification(params) do
      {:ok, %{refunded?: true, payment_id: payment_id}} ->
        Logger.error("Tpay refunded the transaction of payment #{payment_id}; check it in the Tpay panel")

      {:ok, notification} ->
        record_outcome(notification)

      :error ->
        Logger.warning("Acknowledged a Tpay transaction notification that names no payment attempt")
    end

    text(conn, "TRUE")
  end

  defp record_outcome(%{payment_id: payment_id} = notification) do
    lookup_scope = Billing.scope(nil)

    # A payment of another environment sharing the Tpay account is not here.
    case Billing.get_payment_global!(payment_id, scope: lookup_scope, not_found_error?: false) do
      nil ->
        :ok

      payment ->
        org_id = payment.organization_id
        scope = Billing.scope(org_id)

        case Billing.record_payment_outcome(
               payment,
               Map.take(notification, [:transaction_id, :attempt]),
               scope: scope
             ) do
          {:ok, _payment} ->
            :ok

          {:error, error} ->
            if foreign_transaction?(error) do
              Logger.warning(
                "Acknowledged a Tpay notification about a transaction that is not attempt " <>
                  "#{notification.attempt} of payment #{payment_id}"
              )
            else
              raise error
            end
        end
    end
  end

  # Tpay does not know the transaction as ours, or it charges another attempt or amount.
  defp foreign_transaction?(%Ash.Error.Invalid{errors: errors}),
    do: Enum.any?(errors, &match?(%InvalidArgument{field: :transaction_id}, &1))

  defp foreign_transaction?(_error), do: false

  defp save_card(%{"tokenizationId" => tokenization_id, "token" => card_token} = data) do
    lookup_scope = Billing.scope(nil)

    # Nothing awaits this tokenization's card when the notification repeats or is not ours.
    case Billing.get_subscription_by_tokenization_id!(tokenization_id,
           scope: lookup_scope,
           not_found_error?: false
         ) do
      nil ->
        :ok

      subscription ->
        org_id = subscription.organization_id
        scope = Billing.scope(org_id)

        Billing.save_subscription_card!(
          subscription,
          %{
            tokenization_id: tokenization_id,
            card_token: card_token,
            card_brand: data["cardBrand"],
            card_tail: data["cardTail"],
            card_expires: data["tokenExpiryDate"]
          },
          scope: scope
        )
    end
  end
end
