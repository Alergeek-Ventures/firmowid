# credo:disable-for-this-file AshCredo.Check.Refactor.UseCodeInterface
# PendingMatch is embedded, so its code interface does not generate a create function.
defmodule Firmowid.Ash.Assistant.InvoiceMatching.PendingMatches do
  @moduledoc """
  Validates, loads, and atomically applies typed pending assistant matches.
  """

  alias Ash.Error.Query.NotFound
  alias Firmowid.Ash.Assistant.PendingMatch
  alias Firmowid.Ash.Assistant.PendingMatch.InvoiceRef
  alias Firmowid.Ash.Finances
  alias Firmowid.Ash.Invoicing
  alias Firmowid.Ash.Scope

  @type build_params :: %{
          optional(:message) => String.t(),
          optional(:transaction_ids) => [String.t()],
          optional(:cost_invoice_ids) => [String.t()],
          optional(:sales_invoice_ids) => [String.t()]
        }

  @doc """
  Builds a validated pending match proposal for the current tenant.
  """
  @spec build(build_params(), Scope.t()) :: {:ok, PendingMatch.t()} | {:error, String.t()}
  def build(params, %Scope{} = scope) do
    message = params |> Map.get(:message) |> normalize_message()
    transaction_ids = normalize_ids(Map.get(params, :transaction_ids, []))

    invoice_refs =
      params
      |> Map.get(:cost_invoice_ids, [])
      |> build_invoice_refs(:cost_invoice)
      |> Kernel.++(build_invoice_refs(Map.get(params, :sales_invoice_ids, []), :sales_invoice))

    with :ok <- validate_presence(transaction_ids, invoice_refs),
         :ok <- validate_message(message),
         :ok <- ensure_transactions_exist(transaction_ids, scope),
         :ok <- ensure_invoices_exist(invoice_refs, scope) do
      cast_pending_match(message, transaction_ids, invoice_refs)
    end
  end

  @doc """
  Loads transactions for a pending proposal without raising on stale references.
  """
  @spec load_transactions(PendingMatch.t() | nil, struct()) ::
          {:ok, [struct()]} | {:error, term()}
  def load_transactions(nil, _current_user), do: {:ok, []}

  def load_transactions(%PendingMatch{transaction_ids: transaction_ids}, current_user) do
    scope = %Scope{actor: current_user, tenant: current_user.organization_id}

    transaction_ids
    |> Enum.reduce_while({:ok, []}, fn transaction_id, {:ok, transactions} ->
      case Finances.get_transaction(transaction_id, scope: scope) do
        {:ok, transaction} -> {:cont, {:ok, [transaction | transactions]}}
        {:error, %NotFound{}} -> {:halt, {:error, :stale_pending_match}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, transactions} -> {:ok, Enum.reverse(transactions)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Loads invoices for a pending proposal without raising on stale references.
  """
  @spec load_invoices(PendingMatch.t() | nil, struct()) ::
          {:ok, [struct()]} | {:error, term()}
  def load_invoices(nil, _current_user), do: {:ok, []}

  def load_invoices(%PendingMatch{invoice_refs: invoice_refs}, current_user) do
    scope = %Scope{actor: current_user, tenant: current_user.organization_id}

    invoice_refs
    |> Enum.reduce_while({:ok, []}, fn invoice_ref, {:ok, invoices} ->
      case fetch_invoice_for_preview(invoice_ref, scope) do
        {:ok, invoice} -> {:cont, {:ok, [invoice | invoices]}}
        {:error, %NotFound{}} -> {:halt, {:error, :stale_pending_match}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, invoices} -> {:ok, Enum.reverse(invoices)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Revalidates and applies a pending match proposal inside caller-managed transaction scope.
  """
  @spec apply(PendingMatch.t(), Scope.t()) :: {:ok, [struct()]} | {:error, term()}
  def apply(%PendingMatch{} = pending_match, %Scope{} = scope) do
    with :ok <- ensure_transactions_exist(pending_match.transaction_ids, scope),
         :ok <- ensure_invoices_exist(pending_match.invoice_refs, scope) do
      pending_match.invoice_refs
      |> Enum.reduce_while({:ok, []}, fn invoice_ref, {:ok, results} ->
        case connect_invoice(invoice_ref, pending_match.transaction_ids, scope) do
          {:ok, result} -> {:cont, {:ok, [result | results]}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
      |> case do
        {:ok, results} -> {:ok, Enum.reverse(results)}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp cast_pending_match(message, transaction_ids, invoice_refs) do
    PendingMatch
    |> Ash.Changeset.for_create(:create, %{
      message: message,
      transaction_ids: transaction_ids,
      invoice_refs: invoice_refs
    })
    |> Ash.create([])
    |> case do
      {:ok, pending_match} -> {:ok, pending_match}
      {:error, _error} -> {:error, "Nie udało się zbudować propozycji dopasowania."}
    end
  end

  defp build_invoice_refs(invoice_ids, type) do
    invoice_ids
    |> normalize_ids()
    |> Enum.map(&%{type: type, id: &1})
  end

  defp normalize_ids(ids) when is_list(ids) do
    ids
    |> Enum.map(&(&1 |> to_string() |> String.trim()))
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp normalize_ids(_ids), do: []

  defp normalize_message(nil), do: ""
  defp normalize_message(message), do: message |> to_string() |> String.trim()

  defp validate_presence([], []), do: {:error, "Propozycja musi zawierać co najmniej jedną fakturę i jedną transakcję."}

  defp validate_presence([], _invoice_refs), do: {:error, "Propozycja musi zawierać co najmniej jedną transakcję."}

  defp validate_presence(_transaction_ids, []), do: {:error, "Propozycja musi zawierać co najmniej jedną fakturę."}

  defp validate_presence(_transaction_ids, _invoice_refs), do: :ok

  defp validate_message(""), do: {:error, "Propozycja musi zawierać wiadomość dla użytkownika."}
  defp validate_message(_message), do: :ok

  defp ensure_transactions_exist(transaction_ids, scope) do
    Enum.reduce_while(transaction_ids, :ok, fn transaction_id, :ok ->
      case Finances.get_transaction(transaction_id, scope: scope) do
        {:ok, _transaction} ->
          {:cont, :ok}

        {:error, _reason} ->
          {:halt, {:error, "Nie udało się odnaleźć wszystkich wskazanych transakcji."}}
      end
    end)
  end

  defp ensure_invoices_exist(invoice_refs, scope) do
    Enum.reduce_while(invoice_refs, :ok, fn invoice_ref, :ok ->
      case fetch_invoice(invoice_ref, scope) do
        {:ok, _invoice} ->
          {:cont, :ok}

        {:error, _reason} ->
          {:halt, {:error, "Nie udało się odnaleźć wszystkich wskazanych faktur."}}
      end
    end)
  end

  defp fetch_invoice(%{type: :cost_invoice, id: id}, scope), do: Invoicing.get_cost_invoice(id, scope: scope)

  defp fetch_invoice(%{type: :sales_invoice, id: id}, scope), do: Invoicing.get_sales_invoice(id, scope: scope)

  defp fetch_invoice_for_preview(%{type: :cost_invoice, id: id}, scope) do
    Invoicing.get_cost_invoice(id,
      load: [:effective_total_amount, :effective_currency, :effective_seller_display_name],
      scope: scope
    )
  end

  defp fetch_invoice_for_preview(%{type: :sales_invoice, id: id}, scope) do
    Invoicing.get_sales_invoice(id,
      load: [:gross_value, :buyer_display_name_label],
      scope: scope
    )
  end

  defp connect_invoice(%InvoiceRef{type: :cost_invoice, id: id}, transaction_ids, scope) do
    with {:ok, invoice} <- Invoicing.get_cost_invoice(id, scope: scope) do
      Invoicing.connect_cost_invoice_transactions_manual(invoice, transaction_ids, scope)
    end
  end

  defp connect_invoice(%InvoiceRef{type: :sales_invoice, id: id}, transaction_ids, scope) do
    with {:ok, invoice} <- Invoicing.get_sales_invoice(id, scope: scope) do
      Invoicing.connect_sales_invoice_transactions_manual(invoice, transaction_ids, scope)
    end
  end
end
