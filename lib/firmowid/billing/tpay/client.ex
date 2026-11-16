defmodule Firmowid.Billing.Tpay.Client do
  @moduledoc """
  HTTP client for the Tpay Open API, the boundary between billing and Tpay.

  Tpay field names and statuses stay in this module; callers pass and receive plain
  Elixir maps, and a charge comes back as one outcome: `:paid`, `:declined`, or `:pending`
  while Tpay has not decided yet. A transaction is named by its title (`TR-…`), which
  `GET /transactions/{id}` accepts and transaction notifications send as `tr_id`.
  A charge carries `"<payment id>:<attempt>"` in `hiddenDescription`, which comes back
  in notifications as `tr_crc`; a transaction read from Tpay names that payment and attempt,
  its amount and when it was paid. Tpay states times in Polish time.

  Every operation signs in with `POST /oauth/auth` first: there are a few calls per
  organization per month, so the two-hour token is not kept. A charge takes the token
  from the caller instead, so a sign-in failure stops it before anything is recorded.
  The base URL and credentials come from `Application.get_env(:firmowid, :tpay)`.
  """

  @typedoc "What a card charge came to."
  @type outcome :: :paid | :declined | :pending

  @type card_token_params :: %{
          payer: %{name: String.t(), email: String.t()},
          callback_url: String.t(),
          success_url: String.t(),
          error_url: String.t()
        }

  @type charge_params :: %{
          payment_id: String.t(),
          attempt: pos_integer(),
          card_token: String.t(),
          amount: Decimal.t(),
          description: String.t(),
          payer: %{name: String.t(), email: String.t()},
          notification_url: String.t()
        }

  @typedoc """
  A transaction as Tpay states it. `payment_id` and `attempt` are `nil` when it does not
  carry a reference to a payment's attempt; `paid_at` is `nil` until it is paid.
  """
  @type transaction :: %{
          transaction_id: String.t(),
          outcome: outcome(),
          payment_id: String.t() | nil,
          attempt: pos_integer() | nil,
          amount: Decimal.t(),
          paid_at: DateTime.t() | nil
        }

  @type transaction_notification :: %{
          payment_id: String.t(),
          attempt: pos_integer(),
          transaction_id: String.t(),
          refunded?: boolean()
        }

  # Tpay's bank group of card payments.
  @card_group_id 103

  @doc """
  Starts saving a card without a charge. Returns Tpay's tokenization id and the
  hosted card page to send the payer to; the card token itself arrives later in
  the tokenization notification sent to `callback_url`.
  """
  @spec create_card_token(card_token_params()) ::
          {:ok, %{id: String.t(), url: String.t()}} | {:error, term()}
  def create_card_token(%{
        payer: %{name: name, email: email},
        callback_url: callback_url,
        success_url: success_url,
        error_url: error_url
      }) do
    body = %{
      payer: %{name: name, email: email},
      callbackUrl: callback_url,
      redirectUrl: %{success: success_url, error: error_url}
    }

    with {:ok, access_token} <- access_token() do
      case Req.post(request(), url: "/tokens", auth: {:bearer, access_token}, json: body) do
        {:ok, %{status: 200, body: %{"id" => id, "url" => url}}} -> {:ok, %{id: id, url: url}}
        response -> handle_error(response)
      end
    end
  end

  @doc "Signs in to Tpay and returns an access token valid for two hours."
  @spec access_token() :: {:ok, String.t()} | {:error, term()}
  def access_token do
    config = Application.fetch_env!(:firmowid, :tpay)

    form = [
      client_id: config[:client_id] || raise("TPAY_CLIENT_ID is not set"),
      client_secret: config[:client_secret] || raise("TPAY_CLIENT_SECRET is not set")
    ]

    case Req.post(request(), url: "/oauth/auth", form_multipart: form) do
      {:ok, %{status: 200, body: %{"access_token" => access_token}}} -> {:ok, access_token}
      response -> handle_error(response)
    end
  end

  @doc """
  Charges a saved card with no customer present, once: the request is never retried.

  `{:error, {:rejected, status, body}}` means Tpay refused the request as invalid or about
  something it does not know (400, 404, 422), so nothing was charged. Any other error leaves
  it unknown whether Tpay charged the card: a timeout or throttling (408, 429), and also an
  authorization failure (401, 403), which is ours to fix rather than the customer's decline.
  """
  @spec charge(String.t(), charge_params()) ::
          {:ok, transaction()} | {:error, {:rejected, pos_integer(), term()}} | {:error, term()}
  def charge(access_token, params) do
    body = %{
      amount: Decimal.to_float(params.amount),
      currency: "PLN",
      description: params.description,
      hiddenDescription: reference(params.payment_id, params.attempt),
      lang: "pl",
      payer: params.payer,
      pay: %{
        groupId: @card_group_id,
        cardPaymentData: %{token: params.card_token},
        cof: "recurring"
      },
      callbacks: %{notification: %{url: params.notification_url}}
    }

    request = [url: "/transactions", auth: {:bearer, access_token}, json: body, retry: false]

    case Req.post(request(), request) do
      {:ok, %{status: 200, body: transaction}} ->
        with {:ok, outcome} <- charge_outcome(transaction),
             do: {:ok, transaction(transaction, outcome)}

      {:ok, %{status: status, body: body}} when status in [400, 404, 422] ->
        {:error, {:rejected, status, body}}

      response ->
        handle_error(response)
    end
  end

  @doc """
  Asks Tpay what became of a transaction, by its title. Returns `{:ok, nil}` when Tpay
  knows no such transaction of ours, such as one of another merchant.
  """
  @spec transaction_outcome(String.t()) :: {:ok, transaction() | nil} | {:error, term()}
  def transaction_outcome(transaction_id) do
    with {:ok, access_token} <- access_token() do
      case Req.get(request(),
             url: "/transactions/#{transaction_id}",
             auth: {:bearer, access_token}
           ) do
        {:ok, %{status: 200, body: transaction}} -> transaction_result(transaction)
        {:ok, %{status: 404}} -> {:ok, nil}
        response -> handle_error(response)
      end
    end
  end

  @doc """
  Cancels a transaction nobody has paid, so it can no longer be paid. Tpay refuses
  to cancel a paid transaction.
  """
  @spec cancel_transaction(String.t()) :: :ok | {:error, term()}
  def cancel_transaction(transaction_id) do
    with {:ok, access_token} <- access_token() do
      request = [
        url: "/transactions/#{transaction_id}/cancel",
        auth: {:bearer, access_token},
        retry: false
      ]

      case Req.post(request(), request) do
        {:ok, %{status: 200, body: %{"result" => "success"}}} -> :ok
        response -> handle_error(response)
      end
    end
  end

  @doc """
  Finds the transaction of a payment's attempt among the transactions created since
  `since`, for a charge whose answer never arrived. Returns `{:ok, nil}` when there is
  none; Tpay's list can lag a few seconds behind a new transaction.
  """
  @spec find_transaction(String.t(), pos_integer(), DateTime.t()) ::
          {:ok, transaction() | nil} | {:error, term()}
  def find_transaction(payment_id, attempt, since) do
    with {:ok, access_token} <- access_token() do
      find_transaction(access_token, reference(payment_id, attempt), since, 1)
    end
  end

  @page_size 100

  defp find_transaction(access_token, reference, since, page) do
    # Tpay reads the time in Polish time.
    from =
      since |> DateTime.shift_zone!("Europe/Warsaw") |> Calendar.strftime("%Y-%m-%d %H:%M:%S")

    params = [from: from, page: page, limit: @page_size]

    case Req.get(request(), url: "/transactions", auth: {:bearer, access_token}, params: params) do
      {:ok, %{status: 200, body: %{"transactions" => transactions, "total" => total}}} ->
        case Enum.find(transactions, &(&1["hiddenDescription"] == reference)) do
          nil when page * @page_size < total ->
            find_transaction(access_token, reference, since, page + 1)

          nil ->
            {:ok, nil}

          transaction ->
            transaction_result(transaction)
        end

      response ->
        handle_error(response)
    end
  end

  @doc """
  Reads a form-encoded transaction notification: the transaction and the payment's attempt
  it names, and whether it reports a full refund (`chargeback`). Its status says nothing
  else to rely on: what the transaction came to is read from Tpay (`transaction_outcome/1`).
  Returns `:error` when it does not name an attempt of a payment or carries a status this
  client does not know.
  """
  @spec transaction_notification(map()) :: {:ok, transaction_notification()} | :error
  def transaction_notification(%{"tr_id" => transaction_id, "tr_crc" => reference, "tr_status" => status}) do
    with {:ok, payment_id, attempt} <- parse_reference(reference),
         {:ok, refunded?} <- refund_status(String.upcase(status)) do
      {:ok,
       %{
         payment_id: payment_id,
         attempt: attempt,
         transaction_id: transaction_id,
         refunded?: refunded?
       }}
    end
  end

  def transaction_notification(_params), do: :error

  defp refund_status(status) when status in ["TRUE", "PAID", "FALSE"], do: {:ok, false}
  defp refund_status("CHARGEBACK"), do: {:ok, true}
  defp refund_status(_status), do: :error

  defp reference(payment_id, attempt), do: "#{payment_id}:#{attempt}"

  defp parse_reference(reference) do
    with [payment_id, attempt] <- String.split(reference, ":"),
         {:ok, payment_id} <- Ecto.UUID.cast(payment_id),
         {attempt, ""} when attempt >= 1 <- Integer.parse(attempt) do
      {:ok, payment_id, attempt}
    else
      _other -> :error
    end
  end

  # The answer to `POST /transactions`: a declined card still answers 200 with a pending transaction.
  defp charge_outcome(%{"status" => status}) when status in ["paid", "correct"], do: {:ok, :paid}
  defp charge_outcome(%{"payments" => %{"status" => "declined"}}), do: {:ok, :declined}
  defp charge_outcome(%{"status" => "pending"}), do: {:ok, :pending}

  defp charge_outcome(%{"status" => status}), do: {:error, {:unexpected_status, status}}

  # A transaction from `GET /transactions`: a declined card leaves it pending with an error code on its latest attempt.
  defp transaction_result(transaction) do
    with {:ok, outcome} <- transaction_outcome_of(transaction),
         do: {:ok, transaction(transaction, outcome)}
  end

  defp transaction(%{"title" => title, "amount" => amount} = transaction, outcome) do
    {payment_id, attempt} =
      case parse_reference(transaction["hiddenDescription"] || "") do
        {:ok, payment_id, attempt} -> {payment_id, attempt}
        :error -> {nil, nil}
      end

    {:ok, amount} = Decimal.cast(amount)

    %{
      transaction_id: title,
      outcome: outcome,
      payment_id: payment_id,
      attempt: attempt,
      amount: amount,
      paid_at: paid_at(outcome, transaction["date"]["realization"])
    }
  end

  defp paid_at(:paid, realization) when is_binary(realization) do
    naive = NaiveDateTime.from_iso8601!(realization)

    case DateTime.from_naive(naive, "Europe/Warsaw") do
      {:ok, paid_at} -> DateTime.shift_zone!(paid_at, "Etc/UTC")
      # The hour repeated or skipped when the clocks change.
      {:ambiguous, paid_at, _later} -> DateTime.shift_zone!(paid_at, "Etc/UTC")
      {:gap, _before, paid_at} -> DateTime.shift_zone!(paid_at, "Etc/UTC")
    end
  end

  defp paid_at(_outcome, _realization), do: nil

  defp transaction_outcome_of(%{"status" => status}) when status in ["paid", "correct"], do: {:ok, :paid}

  defp transaction_outcome_of(%{"status" => "canceled"}), do: {:ok, :declined}

  defp transaction_outcome_of(%{"status" => "pending", "payments" => %{"attempts" => [_attempt | _rest] = attempts}}) do
    case Enum.max_by(attempts, & &1["date"]) do
      %{"paymentErrorCode" => code} when is_binary(code) -> {:ok, :declined}
      _succeeded -> {:ok, :pending}
    end
  end

  defp transaction_outcome_of(%{"status" => "pending"}), do: {:ok, :pending}
  defp transaction_outcome_of(%{"status" => status}), do: {:error, {:unexpected_status, status}}

  defp request do
    config = Application.fetch_env!(:firmowid, :tpay)

    [base_url: config[:base_url], user_agent: "Firmowid"]
    |> Req.new()
    |> Req.merge(config[:request_options] || [])
  end

  defp handle_error({:ok, %{status: status, body: body}}), do: {:error, {:unexpected_response, status, body}}

  defp handle_error({:error, reason}), do: {:error, reason}
end
