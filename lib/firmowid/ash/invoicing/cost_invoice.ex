defmodule Firmowid.Ash.Invoicing.CostInvoice do
  @moduledoc """
  Ash resource for cost (purchase) invoices.

  ## Read Actions

    * `:read` — default read
    * `:by_id` — single record by ID
    * `:list_for_month` — by issue_date range, excludes linked corrections,
      merges corrections into originals, preloads transactions + corrections
    * `:list_unmatched` — unmatched (no transactions, not skipped) in due_date range,
      excludes linked corrections, merges corrections
    * `:list_by_sale_date` — by sale_date range, preloads transactions
    * `:list_by_ids` — filter by ID list with optional date range
    * `:list_invoices_in_date_range` — invoices with blobs in issue/sale date range
    * `:by_checksum` — find by blob checksum (join on blobs)
    * `:get_with_blob_url` — single record with blob_url, transactions, corrections, original_invoice

  ## Write Actions

    * `:create_from_metadata` — create from AI-extracted or KSeF-parsed metadata
    * `:toggle_skip` — toggle the skip_invoicing flag
    * `:update_blob_id` — attach a blob to an existing invoice

  ## Calculations

    * `:ksef_imported` — whether the invoice was imported from KSeF
    * `:deletable` — whether the invoice can be deleted (not KSeF-imported)

  ## Public Functions (orchestration)

    * `delete_cost_invoice/1` — destroy blob (cascades invoice) + billing decrement
    * `upload_cost_invoice/4` — validate content type, create blob, enqueue extraction job
    * `hydrate_invoice_with_fa3_blob/1` — fetch KSeF XML, create blob, update invoice
    * `subscribe_cost_invoice_broadcast/1` — subscribe to PubSub topic
    * `broadcast_cost_invoice_added/1` — broadcast new invoice event
    * `broadcast_cost_invoice_list_updated/1` — broadcast list refresh event
    * `broadcast_cost_invoice_failed_to_process/2` — broadcast processing failure
    * `broadcast_invalid_document_uploaded/2` — broadcast invalid document
    * `get_processing_cost_invoices_count/0` — count pending extraction jobs
  """
  use Ash.Resource,
    domain: Firmowid.Ash.Invoicing,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Ash.Billing.Limits, as: AshLimits
  alias Firmowid.Ash.Blobs
  alias Firmowid.Ash.Resource
  alias Firmowid.Ksef
  alias Firmowid.Repo

  require Ash.Query
  require Ecto.Query
  require Logger
  require Resource

  @correction_invoice_types [:kor, :kor_zal, :kor_roz]
  @cost_invoice_broadcast_topic "cost_invoice_broadcast_topic"

  postgres do
    table "cost_invoices"
    repo Repo
    migrate? false
  end

  code_interface do
    define :by_id, args: [:id], action: :by_id
    define :get, args: [:id], action: :by_id
    define :list_for_month, args: [:date_from, :date_to]
    define :list_unmatched, args: [:date_from, :date_to]
    define :list_by_sale_date, args: [:date_from, :date_to]
    define :list_by_ids, args: [:ids, {:optional, :date_from}, {:optional, :date_to}]
    define :list_invoices_in_date_range, args: [:date_from, :date_to]
    define :by_checksum, args: [:blob_checksum]
    define :get_with_blob_url, args: [:id], action: :get_with_blob_url
    define :create_from_metadata, args: [:metadata], action: :create_from_metadata
    define :toggle_skip, action: :toggle_skip
    define :update_blob_id, args: [:blob_id], action: :update_blob_id
  end

  actions do
    defaults [:read]

    read :by_id do
      get_by [:id]
    end

    read :list_for_month do
      argument :date_from, :date, allow_nil?: false
      argument :date_to, :date, allow_nil?: false

      filter expr(issue_date >= ^arg(:date_from) and issue_date <= ^arg(:date_to))
      prepare build(sort: [issue_date: :desc], load: [:transactions, :correction_invoices])
      prepare before_action(&exclude_linked_corrections/2)
      prepare after_action(&merge_corrections_after_read/3)
    end

    read :list_unmatched do
      argument :date_from, :date, allow_nil?: false
      argument :date_to, :date, allow_nil?: false

      filter expr(
               due_date >= ^arg(:date_from) and due_date <= ^arg(:date_to) and
                 skip_invoicing == false
             )

      prepare build(sort: [issue_date: :desc], load: [:transactions, :correction_invoices])
      prepare before_action(&exclude_linked_corrections/2)
      prepare before_action(&filter_unmatched/2)
      prepare after_action(&merge_corrections_after_read/3)
    end

    read :list_by_sale_date do
      argument :date_from, :date, allow_nil?: false
      argument :date_to, :date, allow_nil?: false

      filter expr(sale_date >= ^arg(:date_from) and sale_date <= ^arg(:date_to))
      prepare build(sort: [sale_date: :desc], load: [:transactions])
    end

    read :list_by_ids do
      argument :ids, {:array, :uuid_v7}, allow_nil?: false
      argument :date_from, :date
      argument :date_to, :date

      prepare fn query, _context ->
        ids = query.arguments.ids
        date_from = query.arguments[:date_from]
        date_to = query.arguments[:date_to]

        query = Ash.Query.filter_input(query, %{id: %{in: ids}})

        query =
          if date_from do
            Ash.Query.filter_input(query, %{issue_date: %{greater_than_or_equal: date_from}})
          else
            query
          end

        query =
          if date_to do
            Ash.Query.filter_input(query, %{issue_date: %{less_than_or_equal: date_to}})
          else
            query
          end

        query
        |> Ash.Query.sort(issue_date: :desc)
        |> Ash.Query.load(:transactions)
      end
    end

    read :list_invoices_in_date_range do
      argument :date_from, :date, allow_nil?: false
      argument :date_to, :date, allow_nil?: false

      filter expr(
               not is_nil(blob_id) and
                 ((issue_date >= ^arg(:date_from) and issue_date <= ^arg(:date_to)) or
                    (sale_date >= ^arg(:date_from) and sale_date <= ^arg(:date_to)))
             )

      prepare build(load: [blob: [:url]])
    end

    read :by_checksum do
      description "Find a cost invoice by its blob's SHA-256 checksum."
      get? true

      argument :blob_checksum, :string, allow_nil?: false

      filter expr(exists(blob, blob_checksum == ^arg(:blob_checksum)))

      prepare build(load: [:blob])
    end

    action :get_with_blob_url, :struct do
      constraints instance_of: __MODULE__
      argument :id, :uuid_v7, allow_nil?: false

      run fn input, context ->
        opts = Ash.Context.to_opts(context)

        invoice =
          __MODULE__
          |> Ash.Query.filter_input(%{id: %{eq: input.arguments.id}})
          |> Ash.Query.load([
            :transactions,
            :original_invoice,
            blob: [:url],
            correction_invoices: [blob: [:url]]
          ])
          |> Ash.read_one!(opts)

        {:ok, invoice}
      end
    end

    # -- Write actions --------------------------------------------------------

    action :create_from_metadata, :struct do
      constraints instance_of: __MODULE__
      argument :metadata, :map, allow_nil?: false

      run fn input, context ->
        metadata = input.arguments.metadata
        opts = Ash.Context.to_opts(context)

        cost_invoice =
          __MODULE__
          |> Ash.Changeset.for_create(:create_internal, metadata, opts)
          |> Ash.create!()

        {:ok, cost_invoice}
      end
    end

    create :create_internal do
      accept [
        :blob_id,
        :inbound_email_id,
        :seller,
        :seller_address,
        :seller_display_name,
        :account_number,
        :sale_date,
        :issue_date,
        :due_date,
        :total_amount,
        :currency,
        :description,
        :invoice_identifier,
        :skip_invoicing,
        :ksef_number,
        :ksef_permanent_storage_date,
        :ksef_downloaded_at,
        :seller_nip,
        :seller_country_code,
        :seller_email,
        :seller_phone,
        :invoice_type,
        :original_invoice_ksef_number,
        :payment_method
      ]

      validate present([
                 :seller,
                 :seller_display_name,
                 :sale_date,
                 :issue_date,
                 :total_amount,
                 :currency,
                 :description,
                 :invoice_identifier
               ])

      change fn changeset, _context ->
        validate_non_correction_total_amount_sign(changeset)
      end
    end

    update :toggle_skip do
      require_atomic? false

      change fn changeset, _context ->
        current = Ash.Changeset.get_attribute(changeset, :skip_invoicing)
        Ash.Changeset.force_change_attribute(changeset, :skip_invoicing, !current)
      end
    end

    update :update_blob_id do
      accept [:blob_id]
      require_atomic? false
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    policy action_type([:create, :update]) do
      authorize_if always()
    end
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :seller, :string, public?: true
    attribute :seller_address, :string, public?: true
    attribute :seller_display_name, :string, public?: true
    attribute :account_number, :string, public?: true

    attribute :sale_date, :date, public?: true
    attribute :issue_date, :date, public?: true
    attribute :due_date, :date, public?: true

    attribute :total_amount, :decimal, public?: true
    attribute :currency, :string, public?: true

    attribute :description, :string, public?: true
    attribute :invoice_identifier, :string, public?: true

    attribute :skip_invoicing, :boolean, default: false, public?: true

    attribute :ksef_number, :string, public?: true
    attribute :ksef_permanent_storage_date, :naive_datetime, public?: true
    attribute :ksef_downloaded_at, :utc_datetime_usec, public?: true

    attribute :seller_nip, :string, public?: true
    attribute :seller_country_code, :string, public?: true
    attribute :seller_email, :string, public?: true
    attribute :seller_phone, :string, public?: true

    attribute :invoice_type, :atom,
      public?: true,
      constraints: [one_of: ~w(vat kor zal roz upr kor_zal kor_roz)a]

    attribute :original_invoice_ksef_number, :string, public?: true

    attribute :payment_method, :atom,
      public?: true,
      constraints: [one_of: ~w(cash card voucher check loan bank_transfer mobile)a]

    attribute :blob_id, :uuid, public?: true
    attribute :inbound_email_id, :uuid, public?: true

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :organization, Firmowid.Ash.Core.Organization do
      allow_nil? false
    end

    belongs_to :blob, Firmowid.Ash.Blobs.Blob do
      attribute_writable? true
      define_attribute? false
      source_attribute :blob_id
    end

    belongs_to :inbound_email, Firmowid.Ash.Invoicing.InboundEmail do
      attribute_writable? true
      define_attribute? false
      source_attribute :inbound_email_id
    end

    many_to_many :transactions, Firmowid.Ash.Finances.Transaction do
      through Firmowid.Ash.Invoicing.CostInvoiceTransaction
      source_attribute_on_join_resource :cost_invoice_id
      destination_attribute_on_join_resource :transaction_id
    end

    has_many :correction_invoices, __MODULE__ do
      source_attribute :ksef_number
      destination_attribute :original_invoice_ksef_number
      sort ksef_permanent_storage_date: :asc
    end

    belongs_to :original_invoice, __MODULE__ do
      attribute_writable? true
      define_attribute? false
      source_attribute :original_invoice_ksef_number
      destination_attribute :ksef_number
    end

    has_many :entity_tags, Firmowid.Ash.Analysis.EntityTag do
      source_attribute :id
      destination_attribute :resource_id
    end
  end

  calculations do
    calculate :ksef_imported,
              :boolean,
              expr(
                not (is_nil(ksef_downloaded_at) and is_nil(ksef_permanent_storage_date) and
                       is_nil(ksef_number))
              )

    calculate :deletable,
              :boolean,
              expr(not ksef_imported)
  end

  identities do
    identity :ksef_number, [:ksef_number], nils_distinct?: true
  end

  # Public functions — predicates -----------------------------------------------

  @doc """
  Returns true when invoice data was imported from KSeF FA(3) XML.
  """
  @spec ksef_imported?(struct()) :: boolean()
  def ksef_imported?(%{ksef_downloaded_at: nil, ksef_permanent_storage_date: nil, ksef_number: nil}), do: false

  def ksef_imported?(%{}), do: true

  @doc """
  Returns true if the invoice can be deleted (not KSeF-imported).
  """
  @spec deletable?(struct()) :: boolean()
  def deletable?(invoice), do: not ksef_imported?(invoice)

  @doc """
  Returns true if the invoice is a correction type.
  """
  @spec correction_invoice?(struct()) :: boolean()
  def correction_invoice?(%{invoice_type: invoice_type}), do: invoice_type in @correction_invoice_types

  @doc """
  Folds correction invoice data into the original invoice struct.

  When an original invoice has correction invoices, the total amount is summed
  (unless currencies differ), and seller/date fields are taken from the latest
  correction snapshot.
  """
  @spec merge_corrections_into_original_invoice(struct()) :: struct()
  def merge_corrections_into_original_invoice(%{correction_invoices: []} = invoice), do: invoice

  def merge_corrections_into_original_invoice(%{correction_invoices: corrections} = invoice) when is_list(corrections) do
    currency_changed? = Enum.any?(corrections, &(&1.currency != invoice.currency))

    total_amount =
      if currency_changed? do
        invoice.total_amount
      else
        Enum.reduce(corrections, invoice.total_amount, fn correction, acc ->
          Decimal.add(acc, correction.total_amount)
        end)
      end

    latest_snapshot =
      Enum.max_by(corrections, & &1.ksef_permanent_storage_date, NaiveDateTime, fn -> invoice end)

    %{
      invoice
      | total_amount: total_amount,
        currency: latest_snapshot.currency,
        sale_date: latest_snapshot.sale_date,
        due_date: latest_snapshot.due_date,
        seller: latest_snapshot.seller,
        seller_address: latest_snapshot.seller_address,
        seller_display_name: latest_snapshot.seller_display_name,
        seller_nip: latest_snapshot.seller_nip,
        seller_country_code: latest_snapshot.seller_country_code,
        seller_email: latest_snapshot.seller_email,
        seller_phone: latest_snapshot.seller_phone,
        payment_method: latest_snapshot.payment_method,
        account_number: latest_snapshot.account_number
    }
  end

  def merge_corrections_into_original_invoice(invoice), do: invoice

  # Public functions — orchestration -------------------------------------------

  @doc """
  Deletes a cost invoice by ID.

  Destroys the associated blob (SQL cascade deletes the invoice row).
  Decrements the billing counter for non-correction invoices.

  Note: The billing counter decrement happens outside the delete transaction.
  This is intentional — billing limits are soft limits (informational only),
  so we prioritize successful invoice deletion over counter accuracy.
  """
  @spec delete_cost_invoice(Ash.UUID.t()) :: :ok
  def delete_cost_invoice(cost_invoice_id) do
    # TODO: replace authorize?: false + actor: %{} with system actor once available
    opts = [tenant: Repo.get_org_id(), authorize?: false, actor: %{}]

    cost_invoice =
      __MODULE__
      |> Ash.Query.filter_input(%{id: %{eq: cost_invoice_id}})
      |> Ash.Query.load([:blob])
      |> Ash.read_one!(opts)

    if ksef_imported?(cost_invoice) do
      raise "Cost invoice #{cost_invoice_id} is imported from KSeF and cannot be deleted"
    end

    organization_id = cost_invoice.organization_id

    if !correction_invoice?(cost_invoice) do
      case AshLimits.decrement(organization_id, :cost_invoices, authorize?: false, actor: %{}) do
        {:ok, _} ->
          :ok

        {:error, reason} ->
          Logger.warning("Failed to decrement cost_invoices limit: #{inspect(reason)}")
      end
    end

    Blobs.destroy_blob!(cost_invoice.blob, opts)

    broadcast_cost_invoice_list_updated(organization_id)
  end

  @doc """
  Toggles the `skip_invoicing` flag on a cost invoice.
  Returns the updated invoice and broadcasts a list update.
  """
  @spec toggle_skip_invoicing(Ash.UUID.t()) :: struct()
  def toggle_skip_invoicing(id) do
    # TODO: replace authorize?: false + actor: %{} with system actor once available
    opts = [tenant: Repo.get_org_id(), authorize?: false, actor: %{}]

    cost_invoice = Ash.get!(__MODULE__, id, opts)

    cost_invoice =
      cost_invoice
      |> Ash.Changeset.for_update(:toggle_skip, %{}, opts)
      |> Ash.update!()

    broadcast_cost_invoice_list_updated(cost_invoice.organization_id)

    cost_invoice
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

  Increments the billing counter for non-correction invoices,
  broadcasts the new invoice, and enqueues a matching job.
  """
  @spec create_cost_invoice(map()) :: Oban.Job.t()
  def create_cost_invoice(extracted_metadata) do
    # TODO: replace authorize?: false + actor: %{} with system actor once available
    organization_id = Map.get(extracted_metadata, "organization_id", Repo.get_org_id())
    opts = [tenant: organization_id, authorize?: false, actor: %{}]

    {:ok, cost_invoice} = create_from_metadata(extracted_metadata, opts)

    if !correction_invoice?(cost_invoice) do
      case AshLimits.increment(organization_id, :cost_invoices, authorize?: false, actor: %{}) do
        {:ok, _} ->
          :ok

        {:error, reason} ->
          Logger.warning("Failed to increment cost_invoices limit: #{inspect(reason)}")
      end
    end

    broadcast_cost_invoice_added(cost_invoice)

    %{
      name: "match_cost_invoice",
      cost_invoice_id: cost_invoice.id,
      organization_id: organization_id
    }
    |> Firmowid.Invoicing.Worker.new()
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
    # TODO: replace authorize?: false + actor: %{} with system actor once available
    opts = [tenant: invoice.organization_id, authorize?: false, actor: %{}]

    with {:ok, xml} <- Ksef.get_invoice_xml_by_ksef_number(ksef_number),
         {:ok, path} <- Briefly.create(extname: ".xml"),
         :ok <- File.write(path, xml),
         {:ok, blob} <- Blobs.create_blob(path, "application/xml", "#{ksef_number}.xml", opts) do
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
        Logger.error("Failed to fetch KSeF XML for cost invoice #{invoice.id}: #{inspect(reason)}")

        invoice
    end
  end

  def hydrate_invoice_with_fa3_blob(invoice), do: invoice

  # Public functions — PubSub --------------------------------------------------

  @doc "Subscribe to cost invoice broadcasts for the given organization."
  @spec subscribe_cost_invoice_broadcast(Ash.UUID.t()) :: :ok | {:error, term()}
  def subscribe_cost_invoice_broadcast(organization_id) do
    Phoenix.PubSub.subscribe(
      Firmowid.PubSub,
      "#{@cost_invoice_broadcast_topic}:#{organization_id}"
    )
  end

  @doc "Broadcast that a new cost invoice was added."
  @spec broadcast_cost_invoice_added(struct()) :: :ok | {:error, term()}
  def broadcast_cost_invoice_added(cost_invoice) do
    Phoenix.PubSub.broadcast(
      Firmowid.PubSub,
      "#{@cost_invoice_broadcast_topic}:#{cost_invoice.organization_id}",
      {:cost_invoice_added, cost_invoice}
    )
  end

  @doc "Broadcast that the cost invoice list should be refreshed."
  @spec broadcast_cost_invoice_list_updated(Ash.UUID.t()) :: :ok | {:error, term()}
  def broadcast_cost_invoice_list_updated(organization_id) do
    Phoenix.PubSub.broadcast(
      Firmowid.PubSub,
      "#{@cost_invoice_broadcast_topic}:#{organization_id}",
      :cost_invoice_list_updated
    )
  end

  @doc "Broadcast that a cost invoice failed to process."
  @spec broadcast_cost_invoice_failed_to_process(String.t(), Ash.UUID.t()) ::
          :ok | {:error, term()}
  def broadcast_cost_invoice_failed_to_process(original_filename, organization_id) do
    Phoenix.PubSub.broadcast(
      Firmowid.PubSub,
      "#{@cost_invoice_broadcast_topic}:#{organization_id}",
      {:cost_invoice_failed_to_process, original_filename}
    )
  end

  @doc "Broadcast that an invalid (non-invoice) document was uploaded."
  @spec broadcast_invalid_document_uploaded(String.t(), Ash.UUID.t()) :: :ok | {:error, term()}
  def broadcast_invalid_document_uploaded(original_filename, organization_id) do
    Phoenix.PubSub.broadcast(
      Firmowid.PubSub,
      "#{@cost_invoice_broadcast_topic}:#{organization_id}",
      {:invalid_document_uploaded, original_filename}
    )
  end

  # Public functions — utility -------------------------------------------------

  @doc "Returns the count of Oban jobs pending cost invoice extraction."
  @spec get_processing_cost_invoices_count() :: non_neg_integer()
  def get_processing_cost_invoices_count do
    import Ecto.Query

    Oban.Job
    |> where(
      [j],
      j.state in ["available", "scheduled", "executing"] and
        fragment("args->>'name' = ?", "extract_cost_invoice_metadata")
    )
    |> Repo.aggregate(:count, oban_jobs: true)
  end

  # Private helpers -----------------------------------------------------------

  defp create_cost_invoice_job(upload_path, content_type, original_filename, inbound_email_id) do
    # TODO: replace authorize?: false + actor: %{} with system actor once available
    blob_opts = [tenant: Repo.get_org_id(), authorize?: false, actor: %{}]

    result =
      Repo.transaction(fn ->
        case Blobs.create_blob(upload_path, content_type, original_filename, blob_opts) do
          {:ok, blob} ->
            enqueue_extraction_job(blob, inbound_email_id)
            broadcast_cost_invoice_list_updated(blob.organization_id)
            blob

          {:error, error} ->
            Repo.rollback(error)
        end
      end)

    case result do
      {:ok, blob} ->
        {:ok, blob}

      {:error, error} ->
        if blob_checksum_conflict?(error) do
          checksum = get_in(error, [Access.key(:attributes), :blob_checksum])
          {:error, {:blob_already_exists, checksum}}
        else
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

  defp enqueue_extraction_job(blob, inbound_email_id) do
    %{
      name: "extract_cost_invoice_metadata",
      blob_id: blob.id,
      organization_id: blob.organization_id
    }
    |> then(fn args ->
      if inbound_email_id, do: Map.put(args, :inbound_email_id, inbound_email_id), else: args
    end)
    |> Firmowid.CostInvoices.Worker.new()
    |> Firmowid.Oban.insert!()
  end

  # Excludes corrections whose original invoice exists in the system.
  # Orphaned corrections (original deleted) and standalone corrections
  # (nil original_invoice_ksef_number) remain visible.
  defp exclude_linked_corrections(query, _context) do
    Ash.Query.filter(
      query,
      is_nil(original_invoice_ksef_number) or is_nil(original_invoice.id)
    )
  end

  # Filters to invoices that have no linked transactions.
  defp filter_unmatched(query, _context) do
    Ash.Query.filter(query, count(transactions) == 0)
  end

  defp merge_corrections_after_read(_query, results, _context) do
    {:ok, Enum.map(results, &merge_corrections_into_original_invoice/1)}
  end

  defp validate_non_correction_total_amount_sign(changeset) do
    invoice_type = Ash.Changeset.get_attribute(changeset, :invoice_type)
    total_amount = Ash.Changeset.get_attribute(changeset, :total_amount)

    cond do
      invoice_type in @correction_invoice_types ->
        changeset

      is_nil(total_amount) or Decimal.gt?(total_amount, 0) ->
        Ash.Changeset.add_error(changeset,
          field: :total_amount,
          message: "must be <= 0 for non-correction invoices"
        )

      true ->
        changeset
    end
  end
end
