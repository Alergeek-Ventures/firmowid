defmodule Firmowid.Ash.Events.Decoder do
  @moduledoc """
  Decodes persisted Ash event rows into typed embedded event payloads.
  """

  alias Ash.Union
  alias Firmowid.Ash.Events.Payloads.BankAccountSyncFailed
  alias Firmowid.Ash.Events.Payloads.BankAccountSyncSucceeded
  alias Firmowid.Ash.Events.Payloads.InvoiceTransactionsConnected
  alias Firmowid.Ash.Events.Payloads.InvoiceTransactionsDisconnected
  alias Firmowid.Ash.Events.TypedEvent
  alias Firmowid.Ash.Finances.BankAccount
  alias Firmowid.Ash.Invoicing.CostInvoice
  alias Firmowid.Ash.Invoicing.SalesInvoice

  @type raw_event :: map() | struct()

  @doc """
  Decodes a raw event row or `%Firmowid.Ash.Events.Event{}` into a typed event.
  """
  @spec decode(raw_event()) :: {:ok, TypedEvent.t()} | {:error, term()}
  def decode(event) do
    with {:ok, normalized} <- normalize_event(event),
         {:ok, payload} <- decode_payload(normalized) do
      cast_typed_event(normalized, payload)
    end
  end

  @doc """
  Same as `decode/1`, but raises on unsupported or invalid data.
  """
  @spec decode!(raw_event()) :: TypedEvent.t()
  def decode!(event) do
    case decode(event) do
      {:ok, typed_event} -> typed_event
      {:error, reason} -> raise ArgumentError, "failed to decode event: #{inspect(reason)}"
    end
  end

  defp normalize_event(event) do
    resource = event |> field(:resource) |> normalize_resource()
    action = event |> field(:action) |> normalize_action()

    normalized = %{
      event_id: field(event, :id) || field(event, :event_id),
      record_id: field(event, :record_id),
      occurred_at: field(event, :occurred_at),
      resource: resource,
      action: action,
      data: normalize_map(field(event, :data)),
      metadata: normalize_map(field(event, :metadata))
    }

    case normalized do
      %{event_id: nil} -> {:error, {:missing_field, :event_id}}
      %{record_id: nil} -> {:error, {:missing_field, :record_id}}
      %{occurred_at: nil} -> {:error, {:missing_field, :occurred_at}}
      %{resource: nil} -> {:error, {:unsupported_resource, field(event, :resource)}}
      %{action: nil} -> {:error, {:unsupported_action, field(event, :action)}}
      _ -> {:ok, normalized}
    end
  end

  defp decode_payload(%{resource: BankAccount, action: :sync_from_gocardless}) do
    cast_payload(:bank_account_sync_succeeded, BankAccountSyncSucceeded, %{})
  end

  defp decode_payload(%{resource: BankAccount, action: :mark_sync_failed}) do
    cast_payload(:bank_account_sync_failed, BankAccountSyncFailed, %{})
  end

  defp decode_payload(%{resource: CostInvoice, action: :connect_transactions} = event) do
    cast_payload(
      :cost_invoice_transactions_connected,
      InvoiceTransactionsConnected,
      invoice_transaction_payload(event)
    )
  end

  defp decode_payload(%{resource: CostInvoice, action: :disconnect_transactions} = event) do
    cast_payload(
      :cost_invoice_transactions_disconnected,
      InvoiceTransactionsDisconnected,
      invoice_transaction_payload(event)
    )
  end

  defp decode_payload(%{resource: CostInvoice, action: :disconnect_all_transactions} = event) do
    cast_payload(
      :cost_invoice_transactions_disconnected,
      InvoiceTransactionsDisconnected,
      invoice_transaction_payload(event)
    )
  end

  defp decode_payload(%{resource: SalesInvoice, action: :connect_transactions} = event) do
    cast_payload(
      :sales_invoice_transactions_connected,
      InvoiceTransactionsConnected,
      invoice_transaction_payload(event)
    )
  end

  defp decode_payload(%{resource: SalesInvoice, action: :disconnect_transactions} = event) do
    cast_payload(
      :sales_invoice_transactions_disconnected,
      InvoiceTransactionsDisconnected,
      invoice_transaction_payload(event)
    )
  end

  defp decode_payload(%{resource: SalesInvoice, action: :disconnect_all_transactions} = event) do
    cast_payload(
      :sales_invoice_transactions_disconnected,
      InvoiceTransactionsDisconnected,
      invoice_transaction_payload(event)
    )
  end

  defp decode_payload(%{resource: resource, action: action}) do
    {:error, {:unsupported_event_family, resource, action}}
  end

  defp cast_payload(union_type, resource, attrs) do
    case Ash.Type.cast_input(resource, attrs, []) do
      {:ok, payload} -> {:ok, %Union{type: union_type, value: payload}}
      {:error, error} -> {:error, {:invalid_payload, union_type, error}}
    end
  end

  defp cast_typed_event(event, payload) do
    attrs = %{
      event_id: event.event_id,
      record_id: event.record_id,
      occurred_at: event.occurred_at,
      resource: resource_name(event.resource),
      action: event.action,
      payload: payload
    }

    Ash.Type.cast_input(TypedEvent, attrs, [])
  end

  defp invoice_transaction_payload(event) do
    %{
      transaction_ids: Map.get(event.data, :transaction_ids) || Map.get(event.metadata, :transaction_ids, []),
      source: normalize_source(Map.get(event.metadata, :source)),
      confidence_score: normalize_confidence_score(Map.get(event.metadata, :confidence_score)),
      matched_by: Map.get(event.metadata, :matched_by)
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp normalize_confidence_score(score) when is_float(score), do: score
  defp normalize_confidence_score(score) when is_integer(score), do: score / 1
  defp normalize_confidence_score(_score), do: nil

  defp normalize_source(source) when source in [:manual, :auto_match], do: source
  defp normalize_source("manual"), do: :manual
  defp normalize_source("auto_match"), do: :auto_match
  defp normalize_source(_source), do: nil

  defp normalize_resource(BankAccount), do: BankAccount
  defp normalize_resource(CostInvoice), do: CostInvoice
  defp normalize_resource(SalesInvoice), do: SalesInvoice

  defp normalize_resource("Elixir.Firmowid.Ash.Finances.BankAccount"), do: BankAccount
  defp normalize_resource("Elixir.Firmowid.Ash.Invoicing.CostInvoice"), do: CostInvoice
  defp normalize_resource("Elixir.Firmowid.Ash.Invoicing.SalesInvoice"), do: SalesInvoice

  defp normalize_resource(:bank_account), do: BankAccount
  defp normalize_resource(:cost_invoice), do: CostInvoice
  defp normalize_resource(:sales_invoice), do: SalesInvoice
  defp normalize_resource(_resource), do: nil

  defp normalize_action(action) when is_atom(action), do: action

  defp normalize_action(action) when is_binary(action) do
    case action do
      "sync_from_gocardless" -> :sync_from_gocardless
      "mark_sync_failed" -> :mark_sync_failed
      "connect_transactions" -> :connect_transactions
      "disconnect_transactions" -> :disconnect_transactions
      "disconnect_all_transactions" -> :disconnect_all_transactions
      _ -> nil
    end
  end

  defp normalize_action(_action), do: nil

  defp resource_name(BankAccount), do: :bank_account
  defp resource_name(CostInvoice), do: :cost_invoice
  defp resource_name(SalesInvoice), do: :sales_invoice

  defp normalize_map(nil), do: %{}

  defp normalize_map(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {normalize_key(key), value} end)
  end

  defp normalize_map(_other), do: %{}

  defp normalize_key(key) when is_atom(key), do: key

  defp normalize_key(key) when is_binary(key) do
    case key do
      "transaction_ids" -> :transaction_ids
      "source" -> :source
      "confidence_score" -> :confidence_score
      "matched_by" -> :matched_by
      _ -> key
    end
  end

  defp normalize_key(key), do: key

  defp field(event, key) when is_map(event) do
    Map.get(event, key) || Map.get(event, Atom.to_string(key))
  end
end
