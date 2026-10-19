defmodule Firmowid.Ash.Invoicing do
  @moduledoc """
  Ash domain for invoicing — counterparties, sales invoices, cost invoices,
  and supporting resources.
  """
  use Ash.Domain, extensions: [AshAi]

  import Ash.Expr, only: [expr: 1]

  alias Firmowid.Ash.Blobs
  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Currencies.NbpApiClient
  alias Firmowid.Ash.Finances
  alias Firmowid.Ash.Finances.Transaction
  alias Firmowid.Ash.Invoicing.CostInvoice
  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Ash.Invoicing.Services.RecentMatchedEntries
  alias Firmowid.Ash.Ksef
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.SystemActor
  alias Firmowid.ErrorKind

  require Ash.Query

  tools do
    tool :list_sales_invoices, SalesInvoice, :list do
      annotations read_only_hint: true, destructive_hint: false, open_world_hint: false

      description "List sales invoices as data for questions, summaries, analysis and tables in the conversation." <>
                    " First check get_ksef_connection_status and propose connection if needed; stored invoices remain readable without it and may be out of date. Results belong to the authenticated organization. An absent invoice_number identifies a draft. Use after/before keyset cursors with the same filters to navigate pages."

      action_parameters [:limit]

      select [
        :id,
        :invoice_number,
        :issue_date,
        :due_date,
        :buyer_full_name,
        :buyer_given_name,
        :buyer_surname,
        :buyer_display_name,
        :currency,
        :ksef_number,
        :ksef_invoice_kind,
        :corrected_invoice_id
      ]

      load [:gross_value, :ksef_submission_status]
    end

    tool :list_cost_invoices, CostInvoice, :list do
      annotations read_only_hint: true, destructive_hint: false, open_world_hint: false

      description "List cost invoices as data for questions, summaries, analysis and tables in the conversation." <>
                    " First check get_ksef_connection_status and propose connection if needed; stored invoices remain readable without it and may be out of date. Results belong to the authenticated organization and retain signed Money amounts. Use after/before keyset cursors with the same filters to navigate pages."

      action_parameters [:limit]

      select [
        :id,
        :invoice_identifier,
        :issue_date,
        :due_date,
        :seller,
        :seller_display_name,
        :amount,
        :ksef_number,
        :invoice_type
      ]
    end

    tool :get_sales_invoice, SalesInvoice, :read do
      annotations read_only_hint: true, destructive_hint: false, open_world_hint: false

      description "Read a single authorized sales invoice, its items, effective correction snapshot and KSeF status. " <>
                    "Use this before preparing a correction or resuming a saved draft. This tool never changes the invoice."

      get_by [:id]
      action_parameters []

      load [
        :amount,
        :net_value,
        :vat_value,
        :gross_value,
        :ksef_submission_status,
        :effective_snapshot,
        sales_invoice_items: [:net_value, :vat_value, :gross_value],
        latest_correction: [:amount, sales_invoice_items: [:net_value, :vat_value, :gross_value]],
        corrections: [:amount, sales_invoice_items: [:net_value, :vat_value, :gross_value]]
      ]
    end

    tool :preview_sales_invoice, SalesInvoice, :preview_invoice do
      annotations read_only_hint: true, destructive_hint: false, open_world_hint: false

      description "Validate invoice data and open the mandatory user confirmation widget. " <>
                    "Creates nothing. The user selects a number and confirms issuance inside the widget; " <>
                    "an active KSeF connection is required to issue. Pass invoice_id to resume a saved draft, retaining its ID."

      load [
        :amount,
        :net_value,
        :vat_value,
        :gross_value,
        sales_invoice_items: [:net_value, :vat_value, :gross_value]
      ]
    end

    tool :preview_sales_invoice_correction, SalesInvoice, :preview_correction do
      annotations read_only_hint: true, destructive_hint: false, open_world_hint: false

      description "Preview a correction to an issued invoice and open the mandatory confirmation widget. " <>
                    "First read the source with get_sales_invoice. Supply original_invoice_id and the intended corrected items/fields. " <>
                    "Preserves buyer tax identity and the effective correction chain. Creates nothing until the user confirms in the widget."

      load [
        :amount,
        :net_value,
        :vat_value,
        :gross_value,
        sales_invoice_items: [:net_value, :vat_value, :gross_value],
        reference_invoice: [sales_invoice_items: [:net_value, :vat_value, :gross_value]]
      ]
    end

    tool :create_sales_invoice_draft, SalesInvoice, :draft do
      annotations read_only_hint: false, destructive_hint: false, open_world_hint: false

      description "Save a complete but unnumbered invoice only when the user explicitly asks to issue it later. " <>
                    "A draft requires the same data as issuance except the number; keep partial data in the chat instead. " <>
                    "Prefer calling preview_sales_invoice directly. Saving is available without KSeF and neither issues nor submits."

      load [:amount, sales_invoice_items: [:net_value, :vat_value, :gross_value]]
    end

    tool :update_sales_invoice_draft, SalesInvoice, :revise do
      annotations read_only_hint: false, destructive_hint: true, open_world_hint: false

      description "Revise a saved unnumbered invoice draft when the user asks to change it before issuing later. " <>
                    "To issue a draft, call preview_sales_invoice with its invoice_id instead."

      load [:amount, sales_invoice_items: [:net_value, :vat_value, :gross_value]]
    end
  end

  resources do
    resource Firmowid.Ash.Invoicing.Counterparty do
      define :list_counterparties, action: :list
      define :get_counterparty, action: :by_id, args: [:id]
      define :create_counterparty, action: :create
      define :update_counterparty, action: :update
      define :archive_counterparty, action: :archive
      define :unarchive_counterparty, action: :unarchive
      define :destroy_counterparty, action: :destroy
    end

    resource Firmowid.Ash.Invoicing.InboundEmail do
      define :list_inbound_emails, action: :list_all
      define :get_inbound_email, action: :by_id, args: [:id]
      define :create_inbound_email, action: :create

      define :mark_inbound_email_processed,
        action: :mark_processed,
        args: [{:optional, :failure_reason}]
    end

    resource CostInvoice do
      define :list_cost_invoices, action: :list
      define :get_cost_invoice, action: :by_id, args: [:id]
      define :get_cost_invoice_by_checksum, action: :by_checksum, args: [:blob_checksum]
      define :get_cost_invoice_by_blob_id, action: :read, get_by: [:blob_id]
      define :toggle_cost_invoice_skip, action: :toggle_skip

      define :update_cost_invoice_internal_note,
        action: :update_internal_note,
        args: [:internal_note]

      define :update_cost_invoice_blob, action: :update_blob_id, args: [:blob_id]

      define :connect_cost_invoice_transactions,
        action: :connect_transactions,
        args: [:transaction_ids]

      define :disconnect_cost_invoice_transactions,
        action: :disconnect_transactions,
        args: [:transaction_ids]

      define :disconnect_all_cost_invoice_transactions,
        action: :disconnect_all_transactions

      define :create_cost_invoice_dedup, action: :create_dedup
    end

    resource Firmowid.Ash.Invoicing.KsefInvoiceDigest
    resource Firmowid.Ash.Invoicing.KsefInvoiceDigestItem

    resource SalesInvoice do
      define :list_sales_invoices, action: :list
      define :get_sales_invoice, action: :by_id, args: [:id]
      define :get_sales_invoice_by_share_token, action: :by_share_token, args: [:token]
      define :draft_sales_invoice, action: :draft
      define :issue_sales_invoice, action: :issue
      define :correct_sales_invoice, action: :correct
      define :import_sales_invoice_from_ksef, action: :import_from_ksef
      define :revise_sales_invoice_draft, action: :revise
      define :finalize_sales_invoice_draft, action: :finalize
      define :preview_sales_invoice, action: :preview_invoice
      define :preview_sales_invoice_correction, action: :preview_correction

      define :attach_suggested_sales_invoice_counterparty,
        action: :attach_suggested_counterparty,
        args: [:counterparty_id]

      define :destroy_sales_invoice, action: :destroy
      define :cancel_sales_invoice, action: :cancel, args: [:invoice_id]
      define :toggle_sales_invoice_skip, action: :toggle_skip
      define :generate_sales_invoice_share_token, action: :generate_share_token
      define :start_sales_invoice_ksef_submission, action: :start_ksef_submission
      define :record_sales_invoice_ksef_submission, action: :record_ksef_submission
      define :confirm_sales_invoice_in_ksef, action: :confirm_in_ksef
      define :withdraw_sales_invoice_ksef_submission, action: :withdraw_ksef_submission

      define :get_next_sales_invoice_number,
        action: :get_next_number,
        args: [:date, {:optional, :series}, {:optional, :omit_invoice_id}]

      define :validate_sales_invoice_number,
        action: :validate_number,
        args: [:invoice_number, :issue_date, {:optional, :omit_invoice_id}]

      define :list_sales_invoice_series, action: :list_series

      define :connect_sales_invoice_transactions,
        action: :connect_transactions,
        args: [:transaction_ids]

      define :disconnect_sales_invoice_transactions,
        action: :disconnect_transactions,
        args: [:transaction_ids]

      define :disconnect_all_sales_invoice_transactions,
        action: :disconnect_all_transactions
    end

    resource Firmowid.Ash.Invoicing.SalesInvoiceTransaction
    resource Firmowid.Ash.Invoicing.CostInvoiceTransaction
    resource Firmowid.Ash.Invoicing.SalesInvoiceItem

    resource Firmowid.Ash.Invoicing.WizardState.Item

    resource Firmowid.Ash.Invoicing.WizardState do
      define :list_wizard_states, action: :read
      define :get_wizard_state, action: :read, get_by: [:id]
      define :create_wizard_state, action: :create
      define :update_wizard_state_counterparty, action: :update_counterparty
      define :update_wizard_state_items, action: :update_items
      define :update_wizard_state_payment, action: :update_payment
      define :reset_wizard_state_bank_account, action: :reset_bank_account
      define :populate_wizard_state_from_invoice, action: :populate_from_invoice
      define :destroy_wizard_state, action: :destroy
    end

    resource Firmowid.Ash.Invoicing.SkippedKsefSalesInvoice do
      define :list_skipped_ksef_sales_invoices, action: :list
      define :record_skipped_ksef_sales_invoice, action: :record
    end

    resource Firmowid.Ash.Invoicing.SalesInvoiceEmailDelivery do
      define :enqueue_sales_invoice_email,
        action: :enqueue_for_sales_invoice,
        args: [:sales_invoice_id, :delivery_type]
    end
  end

  authorization do
    authorize :by_default
    require_actor? true
  end

  # ── Orchestration functions ──────────────────────────────────────────

  @doc """
  Searches across cost and sales invoices, merging results by relevance.

  Calls the application `:list` actions on CostInvoice and SalesInvoice
  independently, then merges, sorts (by BM25 score when a query is present,
  by issue_date otherwise), and limits to 50 results.

  ## Parameters

    * `:query` — search term (BM25 full-text)
    * `:include_sales` — boolean, default `true`
    * `:include_cost` — boolean, default `true`
    * `:currency`, `:amount_from`, `:amount_to` — value filters (absolute amount, inclusive)
    * `:date_from`, `:date_to` — date range
    * `:only_unmatched` — only invoices without linked transactions
    * `:buyer_type`, `:is_cash`, `:is_reverse_charge` — sales-only filters
  """
  @spec search_invoices(map(), Scope.t()) :: [struct()]
  def search_invoices(params \\ %{}, scope) do
    opts = [scope: scope]

    has_sales_only_filter =
      not is_nil(Map.get(params, :buyer_type)) or
        not is_nil(Map.get(params, :is_cash)) or
        not is_nil(Map.get(params, :is_reverse_charge))

    include_cost = Map.get(params, :include_cost, true) and not has_sales_only_filter
    include_sales = Map.get(params, :include_sales, true)

    cost_results =
      if include_cost do
        list_cost_invoices!(search_args(params, :cost), Keyword.put(opts, :load, [:amount]))
      else
        []
      end

    sales_results =
      if include_sales do
        list_sales_invoices!(
          search_args(params, :sales),
          Keyword.put(opts, :load, [:amount, :sales_invoice_items])
        )
      else
        []
      end

    query = Map.get(params, :query)

    (cost_results ++ sales_results)
    |> sort_search_results(query)
    |> Enum.take(50)
  end

  defp search_args(params, :cost) do
    params
    |> Map.take([
      :query,
      :currency,
      :amount_from,
      :amount_to,
      :date_from,
      :date_to,
      :limit,
      :reconciliation,
      :only_unmatched
    ])
    |> map_only_unmatched()
  end

  defp search_args(params, :sales) do
    params
    |> Map.take([
      :query,
      :currency,
      :amount_from,
      :amount_to,
      :date_from,
      :date_to,
      :limit,
      :reconciliation,
      :only_unmatched,
      :buyer_type,
      :is_cash,
      :is_reverse_charge
    ])
    |> map_only_unmatched()
  end

  defp map_only_unmatched(%{only_unmatched: true} = params) do
    params
    |> Map.delete(:only_unmatched)
    |> Map.put_new(:reconciliation, :pending)
  end

  defp map_only_unmatched(params), do: Map.delete(params, :only_unmatched)

  defp sort_search_results(results, query) when query in [nil, ""] do
    Enum.sort_by(results, & &1.issue_date, {:desc, Date})
  end

  # When a search query is present, ParadeDBSearch sorts each resource's results
  # by pdb.score() descending. We interleave by preserving each list's internal
  # order (already score-sorted) using a simple round-robin merge.
  # This gives fair representation to both types while respecting relevance.
  defp sort_search_results(results, _query) do
    {cost, sales} = Enum.split_with(results, &(&1.__struct__ == CostInvoice))
    interleave(cost, sales)
  end

  defp interleave([], right), do: right
  defp interleave(left, []), do: left
  defp interleave([l | ls], [r | rs]), do: [l, r | interleave(ls, rs)]

  @doc """
  Returns recently matched invoice entries for the invoicing dashboard.
  """
  @spec list_recently_matched_entries(Date.t(), Date.t(), Scope.t(), keyword()) :: map()
  def list_recently_matched_entries(from, to, scope, opts \\ []) do
    RecentMatchedEntries.list(from, to, scope, opts)
  end

  @doc """
  Manually connects transactions to a cost invoice and records manual match metadata.
  """
  @spec connect_cost_invoice_transactions_manual(
          struct(),
          [Ash.UUID.t()],
          Scope.t()
        ) ::
          {:ok, struct()} | {:error, term()}
  def connect_cost_invoice_transactions_manual(cost_invoice, transaction_ids, scope) do
    connect_cost_invoice_transactions(cost_invoice, transaction_ids,
      scope: scope,
      context: manual_match_context(scope)
    )
  end

  @doc """
  Manually disconnects transactions from a cost invoice and records manual match metadata.
  """
  @spec disconnect_cost_invoice_transactions_manual(
          struct(),
          [Ash.UUID.t()],
          Scope.t()
        ) :: {:ok, struct()} | {:error, term()}
  def disconnect_cost_invoice_transactions_manual(cost_invoice, transaction_ids, scope) do
    disconnect_cost_invoice_transactions(
      cost_invoice,
      transaction_ids,
      scope: scope,
      context: manual_match_context(scope)
    )
  end

  @doc """
  Manually disconnects all transactions from a cost invoice and records manual match metadata.
  """
  @spec disconnect_all_cost_invoice_transactions_manual(struct(), Scope.t()) ::
          {:ok, struct()} | {:error, term()}
  def disconnect_all_cost_invoice_transactions_manual(cost_invoice, scope) do
    with {:ok, transaction_ids} <- current_transaction_ids(cost_invoice, scope) do
      disconnect_all_cost_invoice_transactions(
        cost_invoice,
        scope: scope,
        context: manual_match_context(scope, %{transaction_ids: transaction_ids})
      )
    end
  end

  @doc """
  Manually connects transactions to a sales invoice and records manual match metadata.
  """
  @spec connect_sales_invoice_transactions_manual(
          struct(),
          [Ash.UUID.t()],
          Scope.t()
        ) ::
          {:ok, struct()} | {:error, term()}
  def connect_sales_invoice_transactions_manual(sales_invoice, transaction_ids, scope) do
    connect_sales_invoice_transactions(sales_invoice, transaction_ids,
      scope: scope,
      context: manual_match_context(scope)
    )
  end

  @doc """
  Manually disconnects transactions from a sales invoice and records manual match metadata.
  """
  @spec disconnect_sales_invoice_transactions_manual(
          struct(),
          [Ash.UUID.t()],
          Scope.t()
        ) :: {:ok, struct()} | {:error, term()}
  def disconnect_sales_invoice_transactions_manual(sales_invoice, transaction_ids, scope) do
    disconnect_sales_invoice_transactions(
      sales_invoice,
      transaction_ids,
      scope: scope,
      context: manual_match_context(scope)
    )
  end

  @doc """
  Manually disconnects all transactions from a sales invoice and records manual match metadata.
  """
  @spec disconnect_all_sales_invoice_transactions_manual(struct(), Scope.t()) ::
          {:ok, struct()} | {:error, term()}
  def disconnect_all_sales_invoice_transactions_manual(sales_invoice, scope) do
    with {:ok, transaction_ids} <- current_transaction_ids(sales_invoice, scope) do
      disconnect_all_sales_invoice_transactions(
        sales_invoice,
        scope: scope,
        context: manual_match_context(scope, %{transaction_ids: transaction_ids})
      )
    end
  end

  @doc """
  Manually disconnects a transaction from every linked sales and cost invoice atomically.
  """
  @spec disconnect_transaction_from_all_invoices_manual(Transaction.t(), Scope.t()) ::
          {:ok, Transaction.t()} | {:error, term()}
  def disconnect_transaction_from_all_invoices_manual(%Transaction{id: transaction_id} = transaction, scope) do
    Ash.transact([Transaction, CostInvoice, SalesInvoice], fn ->
      with {:ok, loaded_transaction} <-
             load_transaction_with_linked_invoices(transaction_id, scope),
           {:ok, _results} <-
             disconnect_transaction_from_sales_invoices(loaded_transaction, scope),
           {:ok, _results} <- disconnect_transaction_from_cost_invoices(loaded_transaction, scope) do
        transaction
      end
    end)
  end

  @doc """
  Auto-connects transactions to a cost invoice and records auto-match metadata.
  """
  @spec connect_cost_invoice_transactions_auto_match!(
          struct(),
          [Ash.UUID.t()],
          float(),
          Scope.t()
        ) ::
          struct()
  def connect_cost_invoice_transactions_auto_match!(cost_invoice, transaction_ids, confidence_score, scope) do
    connect_cost_invoice_transactions!(cost_invoice, transaction_ids,
      scope: scope,
      context: auto_match_context(confidence_score)
    )
  end

  @doc """
  Auto-connects transactions to a sales invoice and records auto-match metadata.
  """
  @spec connect_sales_invoice_transactions_auto_match!(
          struct(),
          [Ash.UUID.t()],
          float(),
          Scope.t()
        ) ::
          struct()
  def connect_sales_invoice_transactions_auto_match!(sales_invoice, transaction_ids, confidence_score, scope) do
    connect_sales_invoice_transactions!(sales_invoice, transaction_ids,
      scope: scope,
      context: auto_match_context(confidence_score)
    )
  end

  defp manual_match_context(%Scope{} = scope, metadata \\ %{}) do
    matched_by = actor_matcher_id(scope.actor)

    %{
      ash_events_metadata:
        metadata
        |> Map.put(:source, :manual)
        |> Map.put(:matched_by, matched_by)
    }
  end

  defp auto_match_context(confidence_score) do
    %{ash_events_metadata: %{confidence_score: confidence_score, source: :auto_match}}
  end

  defp actor_matcher_id(nil), do: nil
  defp actor_matcher_id(%{id: id}) when is_binary(id), do: id
  defp actor_matcher_id(%{user_id: user_id}) when is_binary(user_id), do: user_id
  defp actor_matcher_id(_actor), do: nil

  defp load_transaction_with_linked_invoices(transaction_id, scope) do
    Finances.get_transaction(transaction_id,
      load: [:sales_invoices, :cost_invoices],
      scope: scope
    )
  end

  defp disconnect_transaction_from_sales_invoices(transaction, scope) do
    reduce_invoices(transaction.sales_invoices, fn invoice ->
      disconnect_sales_invoice_transactions_manual(invoice, [transaction.id], scope)
    end)
  end

  defp disconnect_transaction_from_cost_invoices(transaction, scope) do
    reduce_invoices(transaction.cost_invoices, fn invoice ->
      disconnect_cost_invoice_transactions_manual(invoice, [transaction.id], scope)
    end)
  end

  defp reduce_invoices(invoices, callback) do
    Enum.reduce_while(invoices, {:ok, []}, fn invoice, {:ok, results} ->
      case callback.(invoice) do
        {:ok, result} -> {:cont, {:ok, [result | results]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp current_transaction_ids(invoice, scope) do
    with {:ok, invoice} <- ensure_transactions_loaded(invoice, scope) do
      {:ok, Enum.map(invoice.transactions, & &1.id)}
    end
  end

  defp ensure_transactions_loaded(%{transactions: %Ash.NotLoaded{}} = invoice, scope) do
    Ash.load(invoice, [:transactions], scope: scope)
  end

  defp ensure_transactions_loaded(invoice, _scope), do: {:ok, invoice}

  # ── Cost invoice orchestration ──────────────────────────────────────

  @doc """
  Deletes a cost invoice by ID.

  Destroys the associated blob (SQL cascade deletes the invoice row).

  Note: The billing counter decrement happens outside the delete transaction.
  This is intentional — billing limits are soft limits (informational only),
  so we prioritize successful invoice deletion over counter accuracy.
  """
  @spec delete_cost_invoice(Ash.UUID.t(), Scope.t()) :: :ok
  def delete_cost_invoice(cost_invoice_id, scope) do
    opts = [scope: scope]

    cost_invoice =
      CostInvoice
      |> Ash.Query.filter_input(%{id: %{eq: cost_invoice_id}})
      |> Ash.Query.load([:blob])
      |> Ash.read_one!(opts)

    ksef_imported? =
      not (is_nil(cost_invoice.ksef_downloaded_at) and
             is_nil(cost_invoice.ksef_permanent_storage_date) and is_nil(cost_invoice.ksef_number))

    if ksef_imported? do
      raise "Cost invoice #{cost_invoice_id} is imported from KSeF and cannot be deleted"
    end

    Blobs.destroy_blob!(cost_invoice.blob, opts)
  end

  @doc """
  Returns the most recent KSeF permanent storage date across the organization's cost
  or sales invoices, or `nil` if none exist.
  """
  @spec last_ksef_permanent_storage_date(CostInvoice | SalesInvoice, Ash.UUID.t()) ::
          NaiveDateTime.t() | nil
  def last_ksef_permanent_storage_date(resource, org_id) do
    actor = %SystemActor{org_id: org_id, role: ksef_import_role(resource)}
    scope = %Scope{actor: actor, tenant: org_id}

    %{last_date: date} =
      Ash.aggregate!(
        resource,
        {:last_date, :max, field: :ksef_permanent_storage_date},
        scope: scope
      )

    date
  end

  defp ksef_import_role(CostInvoice), do: :ksef_session
  defp ksef_import_role(SalesInvoice), do: :sales_invoice_processor

  @doc """
  Creates a cost invoice from extracted metadata (AI or KSeF parser).

  The `:create` action emits `cost_invoice_created`, which matches the invoice
  to bank transactions in a job committed together with the invoice.
  """
  @spec create_cost_invoice(map()) :: {:ok, CostInvoice.t()} | {:error, term()}
  def create_cost_invoice(extracted_metadata), do: create_cost_invoice(extracted_metadata, &CostInvoice.create/2)

  @doc """
  Creates a cost invoice from a KSeF import like `create_cost_invoice/1`, but
  leaves the seller display name and description to background jobs.
  """
  @spec create_cost_invoice_from_ksef(map()) :: {:ok, CostInvoice.t()} | {:error, term()}
  def create_cost_invoice_from_ksef(extracted_metadata),
    do: create_cost_invoice(extracted_metadata, &CostInvoice.create_from_ksef/2)

  defp create_cost_invoice(extracted_metadata, create) do
    organization_id =
      Map.get(extracted_metadata, "organization_id") ||
        Map.get(extracted_metadata, :organization_id) ||
        raise "organization_id is required in extracted_metadata"

    sanitized_metadata =
      Map.drop(extracted_metadata, [
        "organization_id",
        :organization_id
      ])

    actor = %SystemActor{org_id: organization_id, role: :cost_invoice_processor}
    scope = %Scope{actor: actor, tenant: organization_id}

    create.(sanitized_metadata, scope: scope)
  end

  @doc """
  Creates a cost invoice with KSeF-number deduplication.

  Uses an upsert action to atomically detect duplicate KSeF numbers.
  Returns `{:error, {:duplicate_ksef_invoice, id}}` when a cost invoice
  with the same KSeF number already exists.
  """
  @spec create_cost_invoice_with_ksef_dedup(map()) ::
          {:ok, CostInvoice.t()}
          | {:error, {:duplicate_ksef_invoice, Ash.UUID.t()}}
          | {:error, term()}
  def create_cost_invoice_with_ksef_dedup(extracted_metadata) do
    ksef_number =
      Map.get(extracted_metadata, "ksef_number") ||
        Map.get(extracted_metadata, :ksef_number)

    if is_binary(ksef_number) and ksef_number != "" do
      do_create_cost_invoice_dedup(extracted_metadata)
    else
      create_cost_invoice(extracted_metadata)
    end
  end

  defp do_create_cost_invoice_dedup(extracted_metadata) do
    organization_id =
      Map.get(extracted_metadata, "organization_id") ||
        Map.get(extracted_metadata, :organization_id) ||
        raise "organization_id is required in extracted_metadata"

    ksef_number =
      Map.get(extracted_metadata, "ksef_number") ||
        Map.get(extracted_metadata, :ksef_number)

    sanitized_metadata =
      Map.drop(extracted_metadata, [
        "organization_id",
        :organization_id
      ])

    actor = %SystemActor{org_id: organization_id, role: :cost_invoice_processor}
    scope = %Scope{actor: actor, tenant: organization_id}

    case find_duplicate_ksef_invoice(ksef_number, scope) do
      {:ok, %CostInvoice{id: existing_id}} ->
        {:error, {:duplicate_ksef_invoice, existing_id}}

      _ ->
        __MODULE__.create_cost_invoice_dedup(sanitized_metadata, scope: scope)
    end
  end

  defp find_duplicate_ksef_invoice(nil, _scope), do: nil
  defp find_duplicate_ksef_invoice("", _scope), do: nil

  defp find_duplicate_ksef_invoice(ksef_number, scope) do
    CostInvoice
    |> Ash.Query.new()
    |> Ash.Query.filter(expr(ksef_number == ^ksef_number))
    |> Ash.Query.select([:id])
    |> Ash.Query.limit(1)
    |> Ash.read_one(scope: scope)
  end

  @doc """
  Fetches the KSeF FA(3) XML for a cost invoice missing a blob, creates a blob
  from it, and attaches it to the invoice.
  """
  # sobelow_skip ["Traversal.FileModule"]
  # Path comes from Briefly.create/1 (OS-managed temp directory), not user input.
  @spec hydrate_invoice_with_fa3_blob(struct()) :: struct()
  def hydrate_invoice_with_fa3_blob(%{ksef_number: ksef_number, blob_id: blob_id} = invoice)
      when not is_nil(ksef_number) and is_nil(blob_id) do
    org_id = invoice.organization_id
    actor = %SystemActor{org_id: org_id, role: :cost_invoice_processor}
    scope = %Scope{actor: actor, tenant: org_id}
    opts = [scope: scope]

    with {:ok, xml} <- Ksef.get_invoice_xml_by_ksef_number(ksef_number, org_id),
         {:ok, path} <- Briefly.create(extname: ".xml"),
         :ok <- File.write(path, xml),
         {:ok, blob} <-
           Blobs.create_blob(path, "application/xml", "#{ksef_number}.xml", opts) do
      try do
        invoice
        |> Ash.Changeset.for_update(:update_blob_id, %{blob_id: blob.id}, opts)
        |> Ash.update!()

        # Return with blob loaded
        Ash.load!(invoice, [blob: [:url]], opts)
      rescue
        error ->
          Blobs.destroy_blob!(blob, opts)
          reraise error, __STACKTRACE__
      end
    else
      {:error, reason} ->
        require Logger

        Logger.error("Failed to fetch KSeF XML for cost invoice",
          invoice_id: invoice.id,
          error_kind: ErrorKind.classify(reason)
        )

        invoice
    end
  end

  def hydrate_invoice_with_fa3_blob(invoice), do: invoice

  # ---------------------------------------------------------------------------
  # Logo / currency / numbering orchestration
  # (moved from SalesInvoice — crosses context boundaries)
  # ---------------------------------------------------------------------------

  @doc """
  Returns the organization's logo URL for the given organization ID.
  """
  @spec get_logo_url(Ash.UUID.t(), keyword()) :: String.t() | nil
  def get_logo_url(organization_id, opts \\ [])

  def get_logo_url(organization_id, opts) when is_binary(organization_id) do
    ash_opts = Keyword.take(opts, [:scope])

    organization =
      organization_id
      |> Core.get_organization!(ash_opts)
      |> Ash.load!([avatar_blob: [:url]], Keyword.put(ash_opts, :tenant, organization_id))

    case organization.avatar_blob do
      %{url: url} -> url
      _ -> nil
    end
  end

  def get_logo_url(_organization_id, _opts), do: nil

  @doc """
  Returns the currency exchange rate for a sales invoice.

  For PLN invoices, returns nil (no conversion needed).
  For other currencies, fetches the NBP exchange rate for the currency conversion date.
  """
  @spec get_currency_rate(map()) :: map() | nil
  def get_currency_rate(%{currency: "PLN"}), do: nil

  def get_currency_rate(%{currency: currency, issue_date: %Date{} = issue_date, sale_date: %Date{} = sale_date}) do
    conversion_date = get_currency_conversion_date(issue_date, sale_date)

    case NbpApiClient.get_exchange_rate(currency, conversion_date) do
      {:ok, rate} -> rate
      {:error, _reason} -> nil
    end
  end

  def get_currency_rate(%{currency: currency, issue_date: %Date{} = issue_date, sale_date: nil}) do
    case NbpApiClient.get_exchange_rate(currency, issue_date) do
      {:ok, rate} -> rate
      {:error, _reason} -> nil
    end
  end

  def get_currency_rate(_), do: nil

  @doc """
  Returns the currency conversion date for a sales invoice.
  Uses the earlier of issue_date and sale_date.
  """
  @spec get_currency_conversion_date(Date.t(), Date.t()) :: Date.t()
  def get_currency_conversion_date(issue_date, sale_date) do
    if Date.before?(issue_date, sale_date), do: issue_date, else: sale_date
  end

  @doc """
  Returns a map of `{format, series}` => next invoice number for every
  numbering sequence worth suggesting on `date`.

  Always includes the monthly `NN/MM/YYYY` and `NN/MM/YYYY/A`, the yearly
  `N/YYYY` and, when the organization name yields initials, the yearly
  `INITIALS/N/YYYY` (see `SalesInvoice.organization_initials/1`), plus every
  monthly series already used by the organization's invoices (such as `FK`).
  Yearly prefixes other than the current initials are not suggested, because a
  number like `ABC/10/2026` may equally be a monthly one. Fans out multiple
  `:get_next_number` action calls.
  """
  @spec get_next_numbers_for_series(Date.t(), keyword(), keyword()) :: %{
          {:monthly | :yearly, String.t() | nil} => String.t()
        }
  def get_next_numbers_for_series(date, opts, extra_opts \\ []) do
    existing_monthly_sequences =
      opts
      |> SalesInvoice.read_all_invoice_numbers()
      |> Enum.map(&SalesInvoice.parse_invoice_number/1)
      |> Enum.flat_map(fn
        {:ok, %{format: :monthly, series: series}} -> [{:monthly, series}]
        _yearly_or_unparsed -> []
      end)

    initials_sequences =
      case opts |> organization_name() |> SalesInvoice.organization_initials() do
        nil -> []
        initials -> [{:yearly, initials}]
      end

    ([{:monthly, nil}, {:monthly, "A"}, {:yearly, nil}] ++
       initials_sequences ++ existing_monthly_sequences)
    |> Enum.uniq()
    |> Map.new(fn {format, series} = sequence ->
      {:ok, number} =
        SalesInvoice.get_next_number(
          date,
          series,
          extra_opts[:omit_invoice_id],
          %{format: format},
          opts
        )

      {sequence, number}
    end)
  end

  # Callers pass either `scope:` or the `actor:`/`tenant:` options of an action context.
  defp organization_name(opts) do
    tenant =
      case Keyword.fetch(opts, :scope) do
        {:ok, scope} -> Ash.Scope.to_opts(scope)[:tenant]
        :error -> Keyword.fetch!(opts, :tenant)
      end

    Core.get_organization!(tenant, opts).name
  end
end
