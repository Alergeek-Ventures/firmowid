defmodule FirmowidWeb.Billing.Controllers.StripeWebhook do
  @moduledoc """
  Receives Stripe events (https://docs.stripe.com/webhooks).

  Every event must carry a valid `Stripe-Signature` of its raw body, made with the endpoint's
  secret (`STRIPE_WEBHOOK_SECRET`); `Stripe.Webhook.construct_event/4` checks it and its age.
  A verified event is applied by `Firmowid.Billing.StripeEvents` and answered with 200; one
  that fails raises, so Stripe sends it again and the error reaches Sentry.
  """
  use FirmowidWeb, :controller

  alias Firmowid.Billing.StripeEvents

  require Logger

  @doc "Verifies the event's signature, applies it and answers Stripe."
  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, _params) do
    # A body that is not JSON is not parsed, so it has no raw body and is rejected.
    with %{raw_body: raw_body} <- conn.private,
         [signature] <- get_req_header(conn, "stripe-signature"),
         {:ok, event} <-
           Stripe.Webhook.construct_event(raw_body, signature, secret(), response_as: :map) do
      case StripeEvents.handle(event) do
        :ok -> send_resp(conn, 200, "")
        {:error, error} -> raise "Stripe event #{event["id"]} failed: #{inspect(error)}"
      end
    else
      _invalid ->
        Logger.warning("Rejected a Stripe event without a valid signature")
        send_resp(conn, 400, "")
    end
  end

  defp secret, do: :firmowid |> Application.fetch_env!(:stripe) |> Keyword.fetch!(:webhook_secret)
end
