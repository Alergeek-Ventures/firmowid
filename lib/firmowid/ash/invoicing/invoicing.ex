defmodule Firmowid.Ash.Invoicing do
  @moduledoc """
  Ash domain for invoicing — counterparties, sales invoices, cost invoices,
  and supporting resources.
  """
  use Ash.Domain

  alias Firmowid.Ash.Blobs
  alias Firmowid.Ash.Currencies.NbpApiClient
  alias Firmowid.Ash.Finances
  alias Firmowid.Ash.Finances.Transaction
  alias Firmowid.Ash.Invoicing.CostInvoice
  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Ash.Invoicing.Services.RecentMatchedEntries
  alias Firmowid.Ash.Invoicing.Workers.MatchingWorker
  alias Firmowid.Ash.Ksef
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.SystemActor

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
      define :list_cost_invoices, action: :read
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
    end

    resource Firmowid.Ash.Invoicing.KsefInvoiceDigest
    resource Firmowid.Ash.Invoicing.KsefInvoiceDigestItem

    resource SalesInvoice do
      define :list_sales_invoices, action: :read
      define :get_sales_invoice, action: :by_id, args: [:id]
      define :get_sales_invoice_by_share_token, action: :by_share_token, args: [:token]
      define :create_sales_invoice, action: :create
      define :update_sales_invoice, action: :update

      define :attach_suggested_sales_invoice_counterparty,
        action: :attach_suggested_counterparty,
        args: [:counterparty_id]

      define :destroy_sales_invoice, action: :destroy
      define :create_sales_invoice_correction, action: :create_correction
      define :cancel_sales_invoice, action: :cancel, args: [:invoice_id]
      define :toggle_sales_invoice_skip, action: :toggle_skip
      define :generate_sales_invoice_share_token, action: :generate_share_token
      define :lock_sales_invoice_for_ksef, action: :lock_for_ksef
      define :unlock_sales_invoice_for_ksef, action: :unlock_for_ksef
      define :update_sales_invoice_ksef_fields, action: :update_ksef_fields

      define :confirm_sales_invoice_from_draft,
        action: :confirm_from_draft,
        args: [
          :draft_id,
          {:optional, :invoice_number},
          :organization,
          {:optional, :should_send_emails}
        ]

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

    resource Firmowid.Ash.Invoicing.WizardDraft.Item

    resource Firmowid.Ash.Invoicing.WizardDraft do
      define :list_wizard_drafts, action: :read
      define :get_wizard_draft, action: :read, get_by: [:id]
      define :create_wizard_draft, action: :create
      define :update_wizard_draft_counterparty, action: :update_counterparty
      define :update_wizard_draft_items, action: :update_items
      define :update_wizard_draft_payment, action: :update_payment
      define :reset_wizard_draft_bank_account, action: :reset_bank_account
      define :populate_wizard_draft_from_invoice, action: :populate_from_invoice
      define :destroy_wizard_draft, action: :destroy
    end

    resource Firmowid.Ash.Invoicing.SalesInvoiceEmailDelivery do
      define :send_sales_invoice_email,
        action: :send_for_invoice,
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

  Calls the primary `:read` actions on CostInvoice and SalesInvoice
  independently, then merges, sorts (by BM25 score when a query is present,
  by issue_date otherwise), and limits to 50 results.

  ## Parameters

    * `:query` — search term (BM25 full-text)
    * `:include_sales` — boolean, default `true`
    * `:include_cost` — boolean, default `true`
    * `:currency`, `:amount_gt`, `:amount_lt` — value filters
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
        list_cost_invoices!(search_args(params, :cost), opts)
      else
        []
      end

    sales_results =
      if include_sales do
        list_sales_invoices!(
          search_args(params, :sales),
          Keyword.put(opts, :load, [:gross_value, :sales_invoice_items])
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
      :amount_gt,
      :amount_lt,
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
      :amount_gt,
      :amount_lt,
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
  Returns the most recent KSeF permanent storage date across all cost invoices
  for the given organization, or `nil` if none exist.
  """
  @spec last_ksef_permanent_storage_date(Ash.UUID.t()) :: NaiveDateTime.t() | nil
  def last_ksef_permanent_storage_date(org_id) do
    actor = %SystemActor{org_id: org_id, role: :ksef_session}
    scope = %Scope{actor: actor, tenant: org_id}

    %{last_date: date} =
      Ash.aggregate!(
        CostInvoice,
        {:last_date, :max, field: :ksef_permanent_storage_date},
        scope: scope
      )

    date
  end

  @doc """
  Creates a cost invoice from extracted metadata (AI or KSeF parser).

  Increments the billing counter for non-correction invoices and enqueues
  a matching job. PubSub notification is sent automatically via the `pub_sub`
  block on `:create`.
  """
  @spec create_cost_invoice(map()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def create_cost_invoice(extracted_metadata) do
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

    with {:ok, cost_invoice} <- CostInvoice.create(sanitized_metadata, scope: scope) do
      %{
        name: "match_cost_invoice",
        cost_invoice_id: cost_invoice.id,
        organization_id: organization_id
      }
      |> MatchingWorker.new()
      |> Firmowid.Oban.insert(skip_organization_id: true)
    end
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

        Logger.error("Failed to fetch KSeF XML for cost invoice #{invoice.id}: #{inspect(reason)}")

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
    alias Firmowid.Ash.Core

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
  Returns a map of series => next_invoice_number for all known series.
  Fans out multiple `:get_next_number` action calls.
  """
  @spec get_next_numbers_for_series(Date.t(), keyword(), keyword()) :: %{
          (String.t() | nil) => String.t()
        }
  def get_next_numbers_for_series(date, opts, extra_opts \\ []) do
    existing_series =
      opts
      |> SalesInvoice.read_all_invoice_numbers()
      |> Enum.map(&SalesInvoice.parse_invoice_number/1)
      |> Enum.filter(&match?({:ok, _}, &1))
      |> Enum.map(fn {:ok, %{series: s}} -> s end)
      |> Enum.uniq()

    all_series = Enum.uniq([nil, "A"] ++ existing_series)

    Map.new(all_series, fn series ->
      {:ok, number} =
        SalesInvoice
        |> Ash.ActionInput.for_action(
          :get_next_number,
          %{
            date: date,
            series: series,
            omit_invoice_id: extra_opts[:omit_invoice_id]
          },
          opts
        )
        |> Ash.run_action(opts)

      {series, number}
    end)
  end
end
