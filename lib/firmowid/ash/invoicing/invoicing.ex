defmodule Firmowid.Ash.Invoicing do
  @moduledoc """
  Ash domain for invoicing — counterparties, sales invoices, cost invoices,
  and supporting resources.

  All public API goes through this domain's code interfaces. LiveViews and
  controllers call the domain, not resource modules directly. Follows the
  same pattern as `Firmowid.Ash.Finances`.

  ## Orchestration functions

  Some operations combine multiple Ash calls with side effects (Oban jobs,
  external APIs, billing counters). These live as regular functions on this
  module because they can't be expressed as single Ash actions:

    * `search_invoices/1` — cross-resource search (CostInvoice + SalesInvoice)
    * `delete_cost_invoice/1` — destroy blob (cascades invoice) + billing
    * `upload_cost_invoice/4` — validate type, create blob, enqueue extraction
    * `create_cost_invoice/1` — create from metadata + enqueue matching job
    * `hydrate_invoice_with_fa3_blob/1` — fetch KSeF XML, create blob, attach
    * `get_processing_cost_invoices_count/0` — pending extraction job count
  """
  use Ash.Domain

  alias Firmowid.Ash.Blobs
  alias Firmowid.Ash.Invoicing.CostInvoice
  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Ash.Invoicing.Workers.CostInvoiceWorker
  alias Firmowid.Ash.Invoicing.Workers.MatchingWorker
  alias Firmowid.Nbp.ApiClient

  require Ash.Query

  # TODO: replace authorize?: false + actor: %{} with system actor once available
  @bridge_opts [authorize?: false, actor: %{}]

  resources do
    resource Firmowid.Ash.Invoicing.Counterparty do
      define :list_counterparties, action: :list_all
      define :get_counterparty, action: :by_id, args: [:id]
      define :create_counterparty, action: :create
      define :update_counterparty, action: :update
      define :destroy_counterparty, action: :destroy

      define :search_counterparties,
        action: :search,
        args: [:search_term, {:optional, :type}, {:optional, :sort_by}, {:optional, :sort_order}]
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
      define :search_cost_invoices, action: :search
      define :create_cost_invoice_from_metadata, action: :create_from_metadata, args: [:metadata]
      define :toggle_cost_invoice_skip, action: :toggle_skip
      define :update_cost_invoice_blob, action: :update_blob_id, args: [:blob_id]

      define :connect_cost_invoice_transactions,
        action: :connect_transactions,
        args: [:transaction_ids]

      define :disconnect_cost_invoice_transactions,
        action: :disconnect_transactions
    end

    resource SalesInvoice do
      define :list_sales_invoices, action: :read
      define :get_sales_invoice, action: :by_id, args: [:id]
      define :get_sales_invoice_by_share_token, action: :by_share_token, args: [:token]
      define :create_sales_invoice, action: :create
      define :update_sales_invoice, action: :update
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
        args: [:draft_id, {:optional, :invoice_number}, :organization]

      define :get_next_sales_invoice_number,
        action: :get_next_number,
        args: [:date, {:optional, :series}, {:optional, :omit_invoice_id}]

      define :validate_sales_invoice_number,
        action: :validate_number,
        args: [:invoice_number, :issue_date, {:optional, :omit_invoice_id}]

      define :list_sales_invoice_series, action: :list_series
      define :search_sales_invoices, action: :search

      define :connect_sales_invoice_transactions,
        action: :connect_transactions,
        args: [:transaction_ids]

      define :disconnect_sales_invoice_transactions,
        action: :disconnect_transactions
    end

    resource Firmowid.Ash.Invoicing.SalesInvoiceTransaction
    resource Firmowid.Ash.Invoicing.CostInvoiceTransaction
    resource Firmowid.Ash.Invoicing.SalesInvoiceItem

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
  end

  authorization do
    authorize :by_default
    require_actor? true
  end

  # ── Orchestration functions ──────────────────────────────────────────

  @doc """
  Searches across cost and sales invoices, merging results by relevance.

  Calls the `:search` read actions on CostInvoice and SalesInvoice
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
  @spec search_invoices(map()) :: [struct()]
  def search_invoices(params \\ %{}) do
    opts = [tenant: Firmowid.Repo.get_org_id()] ++ @bridge_opts

    has_sales_only_filter =
      not is_nil(Map.get(params, :buyer_type)) or
        not is_nil(Map.get(params, :is_cash)) or
        not is_nil(Map.get(params, :is_reverse_charge))

    include_cost = Map.get(params, :include_cost, true) and not has_sales_only_filter
    include_sales = Map.get(params, :include_sales, true)

    cost_results =
      if include_cost do
        search_cost_invoices!(search_args(params, :cost), opts)
      else
        []
      end

    sales_results =
      if include_sales do
        search_sales_invoices!(
          search_args(params, :sales),
          Keyword.put(opts, :load, [:sales_invoice_items])
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
    Map.take(params, [
      :query,
      :currency,
      :amount_gt,
      :amount_lt,
      :date_from,
      :date_to,
      :only_unmatched
    ])
  end

  defp search_args(params, :sales) do
    Map.take(params, [
      :query,
      :currency,
      :amount_gt,
      :amount_lt,
      :date_from,
      :date_to,
      :only_unmatched,
      :buyer_type,
      :is_cash,
      :is_reverse_charge
    ])
  end

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

  # ── Cost invoice orchestration ──────────────────────────────────────

  @doc """
  Deletes a cost invoice by ID.

  Destroys the associated blob (SQL cascade deletes the invoice row).

  Note: The billing counter decrement happens outside the delete transaction.
  This is intentional — billing limits are soft limits (informational only),
  so we prioritize successful invoice deletion over counter accuracy.
  """
  @spec delete_cost_invoice(Ash.UUID.t()) :: :ok
  def delete_cost_invoice(cost_invoice_id) do
    opts = [tenant: Firmowid.Repo.get_org_id()] ++ @bridge_opts

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
  Uploads a cost invoice file. Validates content type, creates a blob,
  and enqueues an extraction job.

  Returns `{:ok, blob}` wrapped in a transaction result, or
  `{:error, :unsupported_content_type}`.
  """
  @spec upload_cost_invoice(String.t(), String.t(), String.t(), Ash.UUID.t() | nil) ::
          {:ok, struct()} | {:error, term()}
  def upload_cost_invoice(upload_path, content_type, original_filename, inbound_email_id \\ nil)

  def upload_cost_invoice(upload_path, "image/" <> _ext = content_type, original_filename, inbound_email_id) do
    create_cost_invoice_job(upload_path, content_type, original_filename, inbound_email_id)
  end

  def upload_cost_invoice(upload_path, "application/pdf" = content_type, original_filename, inbound_email_id) do
    create_cost_invoice_job(upload_path, content_type, original_filename, inbound_email_id)
  end

  def upload_cost_invoice(_upload_path, _content_type, _original_filename, _inbound_email_id) do
    {:error, :unsupported_content_type}
  end

  @doc """
  Creates a cost invoice from extracted metadata (AI or KSeF parser).

  Increments the billing counter for non-correction invoices and enqueues
  a matching job. PubSub notification is sent automatically via the `pub_sub`
  block on `:create_internal` (triggered by `:create_from_metadata`).
  """
  @spec create_cost_invoice(map()) :: Oban.Job.t()
  def create_cost_invoice(extracted_metadata) do
    organization_id = Map.get(extracted_metadata, "organization_id", Firmowid.Repo.get_org_id())
    opts = [tenant: organization_id] ++ @bridge_opts

    {:ok, cost_invoice} = CostInvoice.create_from_metadata(extracted_metadata, opts)

    %{
      name: "match_cost_invoice",
      cost_invoice_id: cost_invoice.id,
      organization_id: organization_id
    }
    |> MatchingWorker.new()
    |> Firmowid.Oban.insert!()
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
    opts = [tenant: invoice.organization_id] ++ @bridge_opts

    with {:ok, xml} <- Firmowid.Ksef.get_invoice_xml_by_ksef_number(ksef_number),
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

  @doc """
  Returns the count of Oban jobs pending cost invoice extraction.

  Uses raw Ecto query on `Oban.Job` because Oban provides no public count API.
  This is the only justified raw Ecto usage remaining in the invoicing domain.
  """
  @spec get_processing_cost_invoices_count() :: non_neg_integer()
  def get_processing_cost_invoices_count do
    import Ecto.Query

    Oban.Job
    |> where(
      [j],
      j.state in ["available", "scheduled", "executing"] and
        fragment("args->>'name' = ?", "extract_cost_invoice_metadata")
    )
    |> Firmowid.Repo.aggregate(:count, oban_jobs: true)
  end

  # ── Private helpers ─────────────────────────────────────────────────

  defp create_cost_invoice_job(upload_path, content_type, original_filename, inbound_email_id) do
    blob_opts =
      [
        tenant: Firmowid.Repo.get_org_id(),
        return_notifications?: true
      ] ++ @bridge_opts

    result =
      Firmowid.Repo.transaction(fn ->
        case Blobs.create_blob(
               upload_path,
               content_type,
               original_filename,
               blob_opts
             ) do
          {:ok, blob, notifications} ->
            enqueue_extraction_job(blob, inbound_email_id)
            {blob, notifications}

          {:error, error} ->
            Firmowid.Repo.rollback(error)
        end
      end)

    case result do
      {:ok, {blob, notifications}} ->
        Ash.Notifier.notify(notifications)
        {:ok, blob}

      {:error, error} ->
        if blob_checksum_conflict?(error) do
          checksum = get_in(error, [Access.key(:attributes), :blob_checksum])
          {:error, {:blob_already_exists, checksum}}
        else
          require Logger

          Logger.error("Failed to upload cost invoice: #{inspect(error)}")
          {:error, error}
        end
    end
  end

  defp blob_checksum_conflict?(%{errors: errors}) do
    Enum.any?(errors, fn
      %Ash.Error.Changes.InvalidChanges{fields: fields} when is_list(fields) ->
        :blob_checksum in fields

      %{error: error} when is_binary(error) ->
        String.contains?(error, "blob_checksum") and
          String.contains?(error, "unique_constraint")

      %{error: %Ecto.ConstraintError{constraint: constraint}} ->
        String.contains?(constraint, "blob_checksum")

      _ ->
        false
    end)
  end

  defp blob_checksum_conflict?(_), do: false

  # ---------------------------------------------------------------------------
  # Logo / currency / numbering orchestration
  # (moved from SalesInvoice — crosses context boundaries)
  # ---------------------------------------------------------------------------

  @doc """
  Returns the organization's logo URL for the given organization ID.
  """
  @spec get_logo_url(Ash.UUID.t()) :: String.t() | nil
  def get_logo_url(organization_id) when is_binary(organization_id) do
    alias Firmowid.Accounts

    {:ok, ecto_org} = Accounts.get_organization(organization_id)
    organization = Accounts.get_organization_with_avatar(ecto_org)
    organization.avatar_url
  end

  def get_logo_url(_), do: nil

  @doc """
  Returns the currency exchange rate for a sales invoice.

  For PLN invoices, returns nil (no conversion needed).
  For other currencies, fetches the NBP exchange rate for the currency conversion date.
  """
  @spec get_currency_rate(struct()) :: map() | nil
  def get_currency_rate(%{currency: "PLN"}), do: nil

  def get_currency_rate(%{currency: currency, issue_date: issue_date, sale_date: sale_date}) do
    conversion_date = get_currency_conversion_date(issue_date, sale_date)
    ApiClient.get_exchange_rate(currency, conversion_date)
  end

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

  defp enqueue_extraction_job(blob, inbound_email_id) do
    %{
      name: "extract_cost_invoice_metadata",
      blob_id: blob.id,
      organization_id: blob.organization_id
    }
    |> then(fn args ->
      if inbound_email_id, do: Map.put(args, :inbound_email_id, inbound_email_id), else: args
    end)
    |> CostInvoiceWorker.new()
    |> Firmowid.Oban.insert!()
  end
end
