defmodule Firmowid.Repo.Migrations.BaselineSchema do
  @moduledoc """
  Baseline migration that reproduces the production database schema exactly 1:1.

  On production, this migration is skipped by pre-inserting its timestamp
  into `schema_migrations`. All type normalization (varchar→text, integer→bigint,
  etc.) happens in a subsequent migration.

  Strategy:
  1. Create enum types
  2. Create all tables (columns, PKs, defaults, NOT NULL — NO foreign keys)
  3. Add all foreign key constraints via ALTER TABLE
  4. Create indexes
  5. Create functions, triggers, and check constraints
  6. Run Oban migration
  """

  use Ecto.Migration

  # ─────────────────────────────────────────────────────────────────────────────
  # UP
  # ─────────────────────────────────────────────────────────────────────────────

  def up do
    # ── 1. Enum types ─────────────────────────────────────────────────────────

    execute("""
    DO $$ BEGIN
      CREATE TYPE employment_contract_type AS ENUM (
        'umowa_o_prace', 'umowa_zlecenie', 'umowa_o_dzielo', 'b2b'
      );
    EXCEPTION WHEN duplicate_object THEN null;
    END $$;
    """)

    execute("""
    DO $$ BEGIN
      CREATE TYPE entity_tag_kind AS ENUM ('project', 'company', 'internal');
    EXCEPTION WHEN duplicate_object THEN null;
    END $$;
    """)

    execute("""
    DO $$ BEGIN
      CREATE TYPE payment_method_type AS ENUM (
        'cash', 'card', 'voucher', 'check', 'credit', 'transfer', 'mobile'
      );
    EXCEPTION WHEN duplicate_object THEN null;
    END $$;
    """)

    execute("""
    DO $$ BEGIN
      CREATE TYPE requisition_status AS ENUM ('pending', 'accepted', 'rejected');
    EXCEPTION WHEN duplicate_object THEN null;
    END $$;
    """)

    # ── 2. Tables ─────────────────────────────────────────────────────────────
    # All FK columns are plain :uuid — foreign key constraints added in step 3.

    create_ash_events()
    create_bank_accounts()
    create_blobs()
    create_cost_invoice_entity_tags()
    create_cost_invoices()
    create_cost_invoices_transactions()
    create_counterparties()
    create_exchange_rates_cache()
    create_fun_with_flags_toggles()
    create_hours_records()
    create_inbound_emails()
    create_ksef_credentials()
    create_organization_invites()
    create_organizations()
    create_projects()
    create_projects_users()
    create_requisitions()
    create_sales_invoice_entity_tags()
    create_sales_invoice_items()
    create_sales_invoices()
    create_sales_invoices_transactions()
    create_sessions()
    create_tag_definitions()
    create_tokens()
    create_transaction_entity_tags()
    create_transactions()
    create_user_identities()
    create_user_salaries()
    create_users()

    # ── 3. Foreign keys ───────────────────────────────────────────────────────

    add_all_foreign_keys()

    # ── 4. Indexes ────────────────────────────────────────────────────────────

    add_all_indexes()

    # ── 5. Functions, triggers, check constraints ─────────────────────────────

    add_functions()
    add_triggers()
    add_check_constraints()

    # ── 6. Oban ───────────────────────────────────────────────────────────────

    Oban.Migration.up(version: 14, prefix: "oban")
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # DOWN
  # ─────────────────────────────────────────────────────────────────────────────

  def down do
    Oban.Migration.down(version: 14, prefix: "oban")

    # Drop triggers first
    for {trigger, table} <- [
          {"transaction_entity_tags_category_exclusivity_trigger", "transaction_entity_tags"},
          {"transaction_entity_tag_taggable_trigger", "transaction_entity_tags"},
          {"sales_invoice_entity_tags_category_exclusivity_trigger", "sales_invoice_entity_tags"},
          {"sales_invoice_entity_tag_taggable_trigger", "sales_invoice_entity_tags"},
          {"cost_invoice_entity_tags_category_exclusivity_trigger", "cost_invoice_entity_tags"},
          {"cost_invoice_entity_tag_taggable_trigger", "cost_invoice_entity_tags"},
          {"no_session_overlap_trigger", "sessions"},
          {"sales_invoice_items_update_names", "sales_invoice_items"},
          {"locked_sales_invoice_trigger", "sales_invoices"},
          {"ksef_cost_invoice_trigger", "cost_invoices"}
        ] do
      execute("DROP TRIGGER IF EXISTS #{trigger} ON #{table}")
    end

    # Drop functions
    for func <- [
          "check_transaction_entity_tags_category_exclusivity()",
          "check_transaction_entity_tag_taggable()",
          "check_sales_invoice_entity_tags_category_exclusivity()",
          "check_sales_invoice_entity_tag_taggable()",
          "check_cost_invoice_entity_tags_category_exclusivity()",
          "check_cost_invoice_entity_tag_taggable()",
          "prevent_session_overlap()",
          "update_sales_invoice_item_names()",
          "prevent_locked_sales_invoice_modification()",
          "prevent_ksef_cost_invoice_modification()"
        ] do
      execute("DROP FUNCTION IF EXISTS #{func}")
    end

    # Drop tables (CASCADE handles FKs, indexes, triggers, check constraints)
    for t <- [
          :transaction_entity_tags,
          :sales_invoice_entity_tags,
          :cost_invoice_entity_tags,
          :sales_invoices_transactions,
          :cost_invoices_transactions,
          :sales_invoice_items,
          :cost_invoices,
          :sales_invoices,
          :sessions,
          :projects_users,
          :projects,
          :hours_records,
          :user_salaries,
          :organization_invites,
          :ksef_credentials,
          :inbound_emails,
          :transactions,
          :bank_accounts,
          :requisitions,
          :counterparties,
          :tag_definitions,
          :blobs,
          :user_identities,
          :tokens,
          :exchange_rates_cache,
          :fun_with_flags_toggles,
          :ash_events,
          :organizations,
          :users
        ] do
      execute("DROP TABLE IF EXISTS #{t} CASCADE")
    end

    # Drop enum types
    execute("DROP TYPE IF EXISTS requisition_status")
    execute("DROP TYPE IF EXISTS payment_method_type")
    execute("DROP TYPE IF EXISTS entity_tag_kind")
    execute("DROP TYPE IF EXISTS employment_contract_type")
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # TABLE DEFINITIONS
  # ═══════════════════════════════════════════════════════════════════════════

  defp create_ash_events do
    create table(:ash_events, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :record_id, :uuid, null: false
      add :version, :bigint, null: false, default: 1
      add :metadata, :map, null: false, default: %{}
      add :data, :map, null: false, default: %{}
      add :changed_attributes, :map, null: false, default: %{}
      add :occurred_at, :naive_datetime_usec, null: false
      add :resource, :text, null: false
      add :action, :text, null: false
      add :action_type, :text, null: false
    end
  end

  defp create_bank_accounts do
    create table(:bank_accounts, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :iban, :string, null: false
      add :institution_id, :string
      add :institution_name, :string
      add :owner_name, :string
      add :gocardless_id, :string, default: fragment("NULL::character varying")
      add :currency, :string
      add :name, :string
      add :organization_id, :uuid, null: false
      add :requisition_id, :uuid
      add :inserted_at, :naive_datetime, null: false
      add :updated_at, :naive_datetime, null: false
      add :is_default, :boolean, null: false, default: false
    end
  end

  defp create_blobs do
    create table(:blobs, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :blob_path, :string, null: false
      add :blob_checksum, :string, null: false
      add :original_filename, :string, null: false
      add :organization_id, :uuid, null: false
      add :inserted_at, :naive_datetime, null: false
      add :updated_at, :naive_datetime, null: false
      add :processing_target, :string, null: false, default: "none"
      add :processing_state, :string, null: false, default: "succeeded"
      add :processing_metadata, :map, null: false, default: %{}
    end
  end

  defp create_cost_invoice_entity_tags do
    create table(:cost_invoice_entity_tags, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :kind, :entity_tag_kind, null: false, default: fragment("'project'::entity_tag_kind")
      add :resource_id, :uuid, null: false
      add :tag_definition_id, :uuid
      add :organization_id, :uuid, null: false
      add :inserted_at, :naive_datetime, null: false
      add :updated_at, :naive_datetime, null: false
    end
  end

  defp create_cost_invoices do
    create table(:cost_invoices, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :blob_id, :uuid
      add :seller, :string, null: false
      add :seller_display_name, :string, null: false
      add :sale_date, :date, null: false
      add :issue_date, :date, null: false
      add :due_date, :date, null: false
      add :total_amount, :decimal, null: false, precision: 10, scale: 2
      add :currency, :string, null: false
      add :invoice_identifier, :string, null: false
      add :description, :text, null: false, default: ""
      add :skip_invoicing, :boolean, null: false, default: false
      add :organization_id, :uuid, null: false
      add :inserted_at, :naive_datetime, null: false
      add :updated_at, :naive_datetime, null: false
      add :account_number, :string
      add :seller_address, :string
      add :inbound_email_id, :uuid
      add :ksef_number, :string
      add :ksef_permanent_storage_date, :naive_datetime_usec
      add :ksef_downloaded_at, :naive_datetime_usec
      add :seller_nip, :string, size: 10
      add :seller_country_code, :string, size: 2
      add :seller_email, :string
      add :seller_phone, :string
      add :invoice_type, :string
      add :original_invoice_ksef_number, :string
      add :payment_method, :string
      add :items_list, :map, null: false, default: fragment("'[]'::jsonb")
    end
  end

  defp create_cost_invoices_transactions do
    create table(:cost_invoices_transactions, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :cost_invoice_id, :uuid, null: false
      add :transaction_id, :uuid, null: false
      add :organization_id, :uuid, null: false
      add :inserted_at, :naive_datetime, null: false
      add :updated_at, :naive_datetime, null: false
    end
  end

  defp create_counterparties do
    create table(:counterparties, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :type, :string, null: false
      add :tax_id, :string
      add :full_name, :string
      add :given_name, :string
      add :surname, :string
      add :pesel, :string
      add :address, :string
      add :country, :string
      add :is_different_mail_address, :boolean, null: false, default: false
      add :mail_address, :string
      add :mail_country, :string
      add :email, :string
      add :phone, :string
      add :description, :string
      add :organization_id, :uuid, null: false
      add :inserted_at, :naive_datetime, null: false
      add :updated_at, :naive_datetime, null: false
      add :display_name, :string
    end
  end

  defp create_exchange_rates_cache do
    create table(:exchange_rates_cache, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :cache_date, :date
      add :rates, :map, null: false
      add :retrieved_at, :naive_datetime, null: false

      add :expires_at, :naive_datetime,
        null: false,
        default: fragment("(now() + '30 days'::interval)")

      add :inserted_at, :naive_datetime, null: false
      add :updated_at, :naive_datetime, null: false
    end
  end

  defp create_fun_with_flags_toggles do
    create table(:fun_with_flags_toggles, primary_key: false) do
      add :id, :bigserial, primary_key: true
      add :flag_name, :string, null: false
      add :gate_type, :string, null: false
      add :target, :string, null: false
      add :enabled, :boolean, null: false
    end
  end

  defp create_hours_records do
    create table(:hours_records, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :month, :integer, null: false
      add :year, :integer, null: false
      add :number_of_hours, :integer, null: false
      add :blob_id, :uuid
      add :organization_id, :uuid, null: false
      add :user_id, :uuid, null: false
      add :inserted_at, :naive_datetime, null: false
      add :updated_at, :naive_datetime, null: false
    end
  end

  defp create_inbound_emails do
    create table(:inbound_emails, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :organization_id, :uuid, null: false
      add :resend_email_id, :string, null: false
      add :sender_email, :string, null: false
      add :subject, :text
      add :body, :text
      add :received_at, :naive_datetime, null: false
      add :processed_at, :naive_datetime
      add :failure_reason, :string
      add :inserted_at, :naive_datetime, null: false
      add :updated_at, :naive_datetime, null: false
    end
  end

  defp create_ksef_credentials do
    create table(:ksef_credentials, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :organization_id, :uuid, null: false
      add :auth_type, :string, null: false
      add :credentials, :binary, null: false
      add :inserted_at, :naive_datetime, null: false
      add :updated_at, :naive_datetime, null: false
    end
  end

  defp create_organization_invites do
    create table(:organization_invites, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :expires_at, :naive_datetime, null: false
      add :consumed_at, :naive_datetime
      add :invite_code, :string, null: false
      add :organization_id, :uuid, null: false
      add :issued_by_id, :uuid, null: false
      add :consumed_by_id, :uuid
      add :inserted_at, :naive_datetime, null: false
      add :updated_at, :naive_datetime, null: false
    end
  end

  defp create_organizations do
    create table(:organizations, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :nip, :string, null: false
      add :address, :string
      add :name, :string, null: false
      add :phone_number, :string
      add :organization_type, :string
      add :correspondence_name, :string
      add :correspondence_address, :string
      add :inserted_at, :naive_datetime, null: false
      add :updated_at, :naive_datetime, null: false
      add :owner_id, :uuid, null: false
      add :avatar_blob_id, :uuid
      add :is_vat_payer, :boolean, default: true
      add :allowed_sender_emails, {:array, :text}, default: []
      add :inbound_email_nickname, :text, null: false
    end
  end

  defp create_projects do
    create table(:projects, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :name, :string
      add :organization_id, :uuid, null: false
      add :inserted_at, :naive_datetime, null: false
      add :updated_at, :naive_datetime, null: false
      add :tag_definition_id, :uuid
      add :archived_at, :date
      add :counterparty_id, :uuid
    end
  end

  defp create_projects_users do
    create table(:projects_users, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :project_id, :uuid, null: false
      add :user_id, :uuid, null: false
      add :organization_id, :uuid, null: false
      add :inserted_at, :naive_datetime, null: false
      add :updated_at, :naive_datetime, null: false
    end
  end

  defp create_requisitions do
    create table(:requisitions, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :status, :requisition_status, null: false
      add :organization_id, :uuid, null: false
      add :inserted_at, :naive_datetime, null: false
      add :updated_at, :naive_datetime, null: false
      add :remote_deleted_at, :naive_datetime
    end
  end

  defp create_sales_invoice_entity_tags do
    create table(:sales_invoice_entity_tags, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :kind, :entity_tag_kind, null: false, default: fragment("'project'::entity_tag_kind")
      add :resource_id, :uuid, null: false
      add :tag_definition_id, :uuid
      add :organization_id, :uuid, null: false
      add :inserted_at, :naive_datetime, null: false
      add :updated_at, :naive_datetime, null: false
    end
  end

  defp create_sales_invoice_items do
    create table(:sales_invoice_items, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :name, :string, null: false
      add :quantity, :decimal, null: false
      add :unit, :string, null: false
      add :unit_price, :decimal, null: false
      add :sales_invoice_id, :uuid, null: false
      add :organization_id, :uuid, null: false
      add :inserted_at, :naive_datetime, null: false
      add :updated_at, :naive_datetime, null: false
      add :index, :integer, null: false
      add :vat_rate, :string
    end
  end

  defp create_sales_invoices do
    create table(:sales_invoices, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :invoice_type, :string, null: false
      add :invoice_number, :string
      add :sale_date, :date
      add :issue_date, :date
      add :due_date, :date
      add :currency, :string, null: false
      add :seller_nip, :string
      add :seller_display_name, :string
      add :seller_address, :string
      add :seller_account_number, :string
      add :seller_name, :string
      add :seller_surname, :string
      add :buyer_type, :string, null: false
      add :buyer_id, :string
      add :buyer_pesel, :string
      add :buyer_full_name, :string
      add :buyer_given_name, :string
      add :buyer_surname, :string
      add :buyer_address, :string
      add :buyer_country, :string
      add :buyer_email, :string
      add :buyer_phone, :string
      add :buyer_description, :string
      add :buyer_is_different_mail_address, :boolean, null: false, default: false
      add :buyer_mail_address, :string
      add :buyer_mail_country, :string
      add :is_cash_account, :boolean, null: false, default: false
      add :is_reverse_charge, :boolean, null: false, default: false
      add :organization_id, :uuid, null: false
      add :inserted_at, :naive_datetime, null: false
      add :updated_at, :naive_datetime, null: false
      add :skip_invoicing, :boolean, null: false, default: false
      add :item_names, :text
      add :ksef_number, :string
      add :ksef_session_reference_number, :string
      add :locked_at, :naive_datetime
      add :ksef_invoice_kind, :string, default: "vat"
      add :corrected_invoice_id, :uuid
      add :counterparty_id, :uuid
      add :payment_method, :payment_method_type
      add :buyer_display_name, :string
      add :correction_reason, :string, size: 256
      add :share_token, :string
      add :ksef_invoice_checksum, :string
    end
  end

  defp create_sales_invoices_transactions do
    create table(:sales_invoices_transactions, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :sales_invoice_id, :uuid, null: false
      add :transaction_id, :uuid, null: false
      add :organization_id, :uuid, null: false
      add :inserted_at, :naive_datetime, null: false
      add :updated_at, :naive_datetime, null: false
    end
  end

  defp create_sessions do
    create table(:sessions, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :user_id, :uuid, null: false
      add :title, :string, null: false
      add :start_datetime, :naive_datetime, null: false
      add :end_datetime, :naive_datetime
      add :project_id, :uuid
      add :organization_id, :uuid, null: false
      add :inserted_at, :naive_datetime, null: false
      add :updated_at, :naive_datetime, null: false
      add :is_remote, :boolean, default: false
    end
  end

  defp create_tag_definitions do
    create table(:tag_definitions, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :name, :string, null: false
      add :color, :string, default: "#6B7280"
      add :organization_id, :uuid, null: false
      add :inserted_at, :naive_datetime, null: false
      add :updated_at, :naive_datetime, null: false
    end
  end

  defp create_tokens do
    create table(:tokens, primary_key: false) do
      add :jti, :text, null: false, primary_key: true
      add :subject, :text, null: false
      add :expires_at, :naive_datetime, null: false
      add :purpose, :text, null: false
      add :extra_data, :map
      add :inserted_at, :naive_datetime_usec, null: false
      add :updated_at, :naive_datetime_usec, null: false
    end
  end

  defp create_transaction_entity_tags do
    create table(:transaction_entity_tags, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :kind, :entity_tag_kind, null: false, default: fragment("'project'::entity_tag_kind")
      add :resource_id, :uuid, null: false
      add :tag_definition_id, :uuid
      add :organization_id, :uuid, null: false
      add :inserted_at, :naive_datetime, null: false
      add :updated_at, :naive_datetime, null: false
    end
  end

  defp create_transactions do
    create table(:transactions, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :transaction_id, :string
      add :internal_transaction_id, :string
      add :creditor_name, :string
      add :creditor_account, :string
      add :debtor_name, :string
      add :debtor_account, :string
      add :transaction_amount, :decimal, precision: 10, scale: 2
      add :transaction_currency, :string
      add :booking_date, :date
      add :value_date, :date
      add :remittance_information_unstructured, :text
      add :skip_invoicing, :boolean, default: false
      add :bank_account_id, :uuid
      add :organization_id, :uuid, null: false
      add :inserted_at, :naive_datetime, null: false
      add :updated_at, :naive_datetime, null: false
    end
  end

  defp create_user_identities do
    create table(:user_identities, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :user_id, :uuid, null: false
      add :strategy, :text, null: false
      add :uid, :text, null: false
      add :access_token, :text
      add :access_token_expires_at, :naive_datetime
      add :refresh_token, :text
      add :inserted_at, :naive_datetime_usec, null: false
      add :updated_at, :naive_datetime_usec, null: false
    end
  end

  defp create_user_salaries do
    create table(:user_salaries, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :hourly_rate, :decimal, null: false, precision: 10, scale: 2
      add :deleted_at, :date
      add :user_id, :uuid, null: false
      add :organization_id, :uuid, null: false
      add :inserted_at, :naive_datetime, null: false
      add :updated_at, :naive_datetime, null: false
    end
  end

  defp create_users do
    create table(:users, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :email, :citext, null: false
      add :hashed_password, :string
      add :confirmed_at, :naive_datetime
      add :system_role, :string, default: "user"
      add :marketing_consent, :boolean, null: false, default: false
      add :organization_id, :uuid
      add :inserted_at, :naive_datetime, null: false
      add :updated_at, :naive_datetime, null: false
      add :avatar_blob_id, :uuid
      add :role, :string, default: "employee"
      add :name, :string
      add :employment_date, :date
      add :phone, :string
      add :slack_url, :string
      add :slack_id, :string
      add :birthday, :date
      add :student_status_until, :date
      add :bank_account_number, :string
      add :position, :string
      add :employment_contract_type, :employment_contract_type
      add :correspondence_street, :string
      add :correspondence_city, :string
      add :correspondence_code, :string
      add :residence_street, :string
      add :residence_city, :string
      add :residence_code, :string
      add :email_change_confirmed_at, :naive_datetime
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # FOREIGN KEYS
  # ═══════════════════════════════════════════════════════════════════════════

  # sobelow_skip ["SQL.Query"]
  # All SQL here is static/hardcoded DDL, not user-controlled input.
  defp add_all_foreign_keys do
    fks = [
      # bank_accounts
      {"bank_accounts", "bank_accounts_organization_id_fkey", "organization_id",
       "organizations(id)", "CASCADE"},
      {"bank_accounts", "bank_accounts_requisition_id_fkey", "requisition_id", "requisitions(id)",
       "SET NULL"},

      # blobs
      {"blobs", "blobs_organization_id_fkey", "organization_id", "organizations(id)", "CASCADE"},

      # cost_invoice_entity_tags
      {"cost_invoice_entity_tags", "cost_invoice_entity_tags_organization_id_fkey",
       "organization_id", "organizations(id)", "CASCADE"},
      {"cost_invoice_entity_tags", "cost_invoice_entity_tags_resource_id_fkey", "resource_id",
       "cost_invoices(id)", "CASCADE"},
      {"cost_invoice_entity_tags", "cost_invoice_entity_tags_tag_definition_id_fkey",
       "tag_definition_id", "tag_definitions(id)", "CASCADE"},

      # cost_invoices
      {"cost_invoices", "cost_invoices_blob_id_fkey", "blob_id", "blobs(id)", "CASCADE"},
      {"cost_invoices", "cost_invoices_inbound_email_id_fkey", "inbound_email_id",
       "inbound_emails(id)", "SET NULL"},
      {"cost_invoices", "cost_invoices_organization_id_fkey", "organization_id",
       "organizations(id)", "CASCADE"},

      # cost_invoices_transactions
      {"cost_invoices_transactions", "cost_invoices_transactions_cost_invoice_id_fkey",
       "cost_invoice_id", "cost_invoices(id)", "CASCADE"},
      {"cost_invoices_transactions", "cost_invoices_transactions_organization_id_fkey",
       "organization_id", "organizations(id)", "CASCADE"},
      {"cost_invoices_transactions", "cost_invoices_transactions_transaction_id_fkey",
       "transaction_id", "transactions(id)", "CASCADE"},

      # counterparties
      {"counterparties", "counterparties_organization_id_fkey", "organization_id",
       "organizations(id)", "CASCADE"},

      # hours_records
      {"hours_records", "hours_records_blob_id_fkey", "blob_id", "blobs(id)", "SET NULL"},
      {"hours_records", "hours_records_organization_id_fkey", "organization_id",
       "organizations(id)", "CASCADE"},
      {"hours_records", "hours_records_user_id_fkey", "user_id", "users(id)", "SET NULL"},

      # inbound_emails
      {"inbound_emails", "inbound_emails_organization_id_fkey", "organization_id",
       "organizations(id)", "CASCADE"},

      # ksef_credentials
      {"ksef_credentials", "ksef_credentials_organization_id_fkey", "organization_id",
       "organizations(id)", "CASCADE"},

      # organization_invites
      {"organization_invites", "organization_invites_consumed_by_id_fkey", "consumed_by_id",
       "users(id)", "CASCADE"},
      {"organization_invites", "organization_invites_issued_by_id_fkey", "issued_by_id",
       "users(id)", "CASCADE"},
      {"organization_invites", "organization_invites_organization_id_fkey", "organization_id",
       "organizations(id)", "CASCADE"},

      # organizations
      {"organizations", "organizations_avatar_blob_id_fkey", "avatar_blob_id", "blobs(id)",
       "SET NULL"},
      {"organizations", "organizations_owner_id_fkey", "owner_id", "users(id)", "CASCADE"},

      # projects
      {"projects", "projects_counterparty_id_fkey", "counterparty_id", "counterparties(id)",
       "SET NULL"},
      {"projects", "projects_organization_id_fkey", "organization_id", "organizations(id)",
       "CASCADE"},
      {"projects", "projects_tag_id_fkey", "tag_definition_id", "tag_definitions(id)",
       "NO ACTION"},

      # projects_users
      {"projects_users", "projects_users_organization_id_fkey", "organization_id",
       "organizations(id)", "CASCADE"},
      {"projects_users", "projects_users_project_id_fkey", "project_id", "projects(id)",
       "CASCADE"},
      {"projects_users", "projects_users_user_id_fkey", "user_id", "users(id)", "CASCADE"},

      # requisitions
      {"requisitions", "requisitions_organization_id_fkey", "organization_id",
       "organizations(id)", "CASCADE"},

      # sales_invoice_entity_tags
      {"sales_invoice_entity_tags", "sales_invoice_entity_tags_organization_id_fkey",
       "organization_id", "organizations(id)", "CASCADE"},
      {"sales_invoice_entity_tags", "sales_invoice_entity_tags_resource_id_fkey", "resource_id",
       "sales_invoices(id)", "CASCADE"},
      {"sales_invoice_entity_tags", "sales_invoice_entity_tags_tag_definition_id_fkey",
       "tag_definition_id", "tag_definitions(id)", "CASCADE"},

      # sales_invoice_items
      {"sales_invoice_items", "sales_invoice_items_organization_id_fkey", "organization_id",
       "organizations(id)", "CASCADE"},
      {"sales_invoice_items", "sales_invoice_items_sales_invoice_id_fkey", "sales_invoice_id",
       "sales_invoices(id)", "CASCADE"},

      # sales_invoices
      {"sales_invoices", "sales_invoices_corrected_invoice_id_fkey", "corrected_invoice_id",
       "sales_invoices(id)", "RESTRICT"},
      {"sales_invoices", "sales_invoices_counterparty_id_fkey", "counterparty_id",
       "counterparties(id)", "SET NULL"},
      {"sales_invoices", "sales_invoices_organization_id_fkey", "organization_id",
       "organizations(id)", "CASCADE"},

      # sales_invoices_transactions
      {"sales_invoices_transactions", "sales_invoices_transactions_organization_id_fkey",
       "organization_id", "organizations(id)", "CASCADE"},
      {"sales_invoices_transactions", "sales_invoices_transactions_sales_invoice_id_fkey",
       "sales_invoice_id", "sales_invoices(id)", "CASCADE"},
      {"sales_invoices_transactions", "sales_invoices_transactions_transaction_id_fkey",
       "transaction_id", "transactions(id)", "CASCADE"},

      # sessions
      {"sessions", "sessions_organization_id_fkey", "organization_id", "organizations(id)",
       "CASCADE"},
      {"sessions", "sessions_project_id_fkey", "project_id", "projects(id)", "SET NULL"},
      {"sessions", "sessions_user_id_fkey", "user_id", "users(id)", "NO ACTION"},

      # tag_definitions
      {"tag_definitions", "tags_organization_id_fkey", "organization_id", "organizations(id)",
       "NO ACTION"},

      # transaction_entity_tags
      {"transaction_entity_tags", "transaction_entity_tags_organization_id_fkey",
       "organization_id", "organizations(id)", "CASCADE"},
      {"transaction_entity_tags", "transaction_entity_tags_resource_id_fkey", "resource_id",
       "transactions(id)", "CASCADE"},
      {"transaction_entity_tags", "transaction_entity_tags_tag_definition_id_fkey",
       "tag_definition_id", "tag_definitions(id)", "CASCADE"},

      # transactions
      {"transactions", "transactions_bank_account_id_fkey", "bank_account_id",
       "bank_accounts(id)", "CASCADE"},
      {"transactions", "transactions_organization_id_fkey", "organization_id",
       "organizations(id)", "CASCADE"},

      # user_identities
      {"user_identities", "user_identities_user_id_fkey", "user_id", "users(id)", "CASCADE"},

      # user_salaries
      {"user_salaries", "user_salaries_organization_id_fkey", "organization_id",
       "organizations(id)", "CASCADE"},
      {"user_salaries", "user_salaries_user_id_fkey", "user_id", "users(id)", "CASCADE"},

      # users
      {"users", "users_avatar_blob_id_fkey", "avatar_blob_id", "blobs(id)", "SET NULL"},
      {"users", "users_organization_id_fkey", "organization_id", "organizations(id)", "CASCADE"}
    ]

    for {table, name, col, ref, on_delete} <- fks do
      execute("""
      ALTER TABLE #{table}
        ADD CONSTRAINT #{name}
        FOREIGN KEY (#{col}) REFERENCES #{ref} ON DELETE #{on_delete}
      """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # INDEXES
  # ═══════════════════════════════════════════════════════════════════════════

  # sobelow_skip ["SQL.Query"]
  # All SQL here is static/hardcoded DDL, not user-controlled input.
  defp add_all_indexes do
    # ── ash_events ──
    create index(:ash_events, [:record_id], name: "ash_events_record_id_index")
    create index(:ash_events, [:resource, :action], name: "ash_events_resource_action_index")

    # ── bank_accounts ──
    execute(
      "CREATE UNIQUE INDEX bank_accounts_iban_organization_id_index ON bank_accounts (iban, organization_id)"
    )

    execute(
      "CREATE UNIQUE INDEX bank_accounts_organization_id_currency_is_default_index ON bank_accounts (organization_id, currency, is_default) WHERE is_default = true"
    )

    execute("CREATE INDEX bank_accounts_requisition_id_index ON bank_accounts (requisition_id)")

    # ── blobs ──
    execute("CREATE INDEX blobs_organization_id_index ON blobs (organization_id)")

    execute(
      "CREATE UNIQUE INDEX blobs_unique_checksum_per_org_index ON blobs (blob_checksum, organization_id)"
    )

    # ── cost_invoice_entity_tags ──
    execute(
      "CREATE UNIQUE INDEX cost_invoice_entity_tags_builtin_kind_unique ON cost_invoice_entity_tags (resource_id, kind) WHERE kind <> 'project'::entity_tag_kind"
    )

    execute(
      "CREATE INDEX cost_invoice_entity_tags_organization_id_index ON cost_invoice_entity_tags (organization_id)"
    )

    execute(
      "CREATE UNIQUE INDEX cost_invoice_entity_tags_project_unique ON cost_invoice_entity_tags (resource_id, tag_definition_id) WHERE tag_definition_id IS NOT NULL"
    )

    # ── cost_invoices ──
    execute("CREATE UNIQUE INDEX cost_invoices_blob_id_index ON cost_invoices (blob_id)")

    execute(
      "CREATE INDEX cost_invoices_inbound_email_id_index ON cost_invoices (inbound_email_id)"
    )

    execute(
      "CREATE INDEX cost_invoices_invoice_identifier_index ON cost_invoices (invoice_identifier)"
    )

    execute("CREATE UNIQUE INDEX cost_invoices_ksef_number_idx ON cost_invoices (ksef_number)")

    execute("CREATE INDEX cost_invoices_organization_id_index ON cost_invoices (organization_id)")

    # ── cost_invoices_transactions ──
    execute(
      "CREATE INDEX cost_invoices_transactions_organization_id_index ON cost_invoices_transactions (organization_id)"
    )

    execute(
      "CREATE INDEX cost_invoices_transactions_transaction_id_index ON cost_invoices_transactions (transaction_id)"
    )

    # ── counterparties ──
    execute(
      "CREATE INDEX counterparties_organization_id_index ON counterparties (organization_id)"
    )

    execute("CREATE INDEX counterparties_tax_id_index ON counterparties (tax_id)")
    execute("CREATE INDEX counterparties_type_index ON counterparties (type)")

    # ── exchange_rates_cache ──
    execute(
      "CREATE UNIQUE INDEX exchange_rates_cache_cache_date_index ON exchange_rates_cache (cache_date)"
    )

    execute(
      "CREATE INDEX exchange_rates_cache_expires_at_index ON exchange_rates_cache (expires_at)"
    )

    # ── fun_with_flags_toggles ──
    create index(:fun_with_flags_toggles, [:flag_name],
             name: "fun_with_flags_toggles_flag_name_index"
           )

    create unique_index(:fun_with_flags_toggles, [:flag_name, :gate_type, :target],
             name: "fun_with_flags_toggles_flag_name_gate_type_target_index"
           )

    # ── hours_records ──
    execute("CREATE INDEX hours_records_blob_id_index ON hours_records (blob_id)")

    execute(
      "CREATE UNIQUE INDEX hours_records_month_year_organization_id_user_id_index ON hours_records (month, year, organization_id, user_id)"
    )

    execute("CREATE INDEX hours_records_organization_id_index ON hours_records (organization_id)")

    execute("CREATE INDEX hours_records_user_id_index ON hours_records (user_id)")

    # ── inbound_emails ──
    execute(
      "CREATE INDEX inbound_emails_organization_id_index ON inbound_emails (organization_id)"
    )

    execute(
      "CREATE UNIQUE INDEX inbound_emails_resend_email_id_index ON inbound_emails (resend_email_id)"
    )

    # ── ksef_credentials ──
    execute(
      "CREATE UNIQUE INDEX ksef_credentials_organization_id_index ON ksef_credentials (organization_id)"
    )

    # ── organization_invites ──
    execute(
      "CREATE INDEX organization_invites_organization_id_index ON organization_invites (organization_id)"
    )

    # ── organizations ──
    execute(
      "CREATE UNIQUE INDEX organizations_inbound_email_nickname_index ON organizations (inbound_email_nickname)"
    )

    # ── projects ──
    execute("CREATE INDEX projects_archived_at_index ON projects (archived_at)")
    execute("CREATE INDEX projects_counterparty_id_index ON projects (counterparty_id)")
    execute("CREATE INDEX projects_organization_id_index ON projects (organization_id)")
    execute("CREATE INDEX projects_tag_id_index ON projects (tag_definition_id)")

    # ── projects_users ──
    execute(
      "CREATE INDEX projects_users_organization_id_index ON projects_users (organization_id)"
    )

    execute("CREATE INDEX projects_users_project_id_index ON projects_users (project_id)")

    execute(
      "CREATE UNIQUE INDEX projects_users_project_id_user_id_index ON projects_users (project_id, user_id)"
    )

    execute("CREATE INDEX projects_users_user_id_index ON projects_users (user_id)")

    # ── requisitions ──
    execute("CREATE INDEX requisitions_organization_id_index ON requisitions (organization_id)")

    # ── sales_invoice_entity_tags ──
    execute(
      "CREATE UNIQUE INDEX sales_invoice_entity_tags_builtin_kind_unique ON sales_invoice_entity_tags (resource_id, kind) WHERE kind <> 'project'::entity_tag_kind"
    )

    execute(
      "CREATE INDEX sales_invoice_entity_tags_organization_id_index ON sales_invoice_entity_tags (organization_id)"
    )

    execute(
      "CREATE UNIQUE INDEX sales_invoice_entity_tags_project_unique ON sales_invoice_entity_tags (resource_id, tag_definition_id) WHERE tag_definition_id IS NOT NULL"
    )

    # ── sales_invoice_items ──
    execute(
      "CREATE INDEX sales_invoice_items_organization_id_index ON sales_invoice_items (organization_id)"
    )

    execute(
      "CREATE UNIQUE INDEX sales_invoice_items_sales_invoice_id_index_index ON sales_invoice_items (sales_invoice_id, \"index\")"
    )

    # ── sales_invoices ──
    execute(
      "CREATE INDEX sales_invoices_corrected_invoice_id_index ON sales_invoices (corrected_invoice_id)"
    )

    execute(
      "CREATE INDEX sales_invoices_counterparty_id_index ON sales_invoices (counterparty_id)"
    )

    execute(
      "CREATE UNIQUE INDEX sales_invoices_invoice_number_organization_id_index ON sales_invoices (invoice_number, organization_id)"
    )

    execute(
      "CREATE UNIQUE INDEX sales_invoices_ksef_number_idx ON sales_invoices (ksef_number) WHERE ksef_number IS NOT NULL"
    )

    execute(
      "CREATE INDEX sales_invoices_locked_at_idx ON sales_invoices (locked_at) WHERE locked_at IS NOT NULL"
    )

    execute(
      "CREATE INDEX sales_invoices_organization_id_index ON sales_invoices (organization_id)"
    )

    execute(
      "CREATE UNIQUE INDEX sales_invoices_share_token_index ON sales_invoices (share_token) WHERE share_token IS NOT NULL"
    )

    # ── sales_invoices_transactions ──
    execute(
      "CREATE INDEX sales_invoices_transactions_organization_id_index ON sales_invoices_transactions (organization_id)"
    )

    execute(
      "CREATE INDEX sales_invoices_transactions_transaction_id_index ON sales_invoices_transactions (transaction_id)"
    )

    # ── sessions ──
    execute("CREATE INDEX sessions_organization_id_index ON sessions (organization_id)")
    execute("CREATE INDEX sessions_project_id_index ON sessions (project_id)")
    execute("CREATE INDEX sessions_user_id_index ON sessions (user_id)")

    # ── tag_definitions ──
    execute(
      "CREATE UNIQUE INDEX tags_organization_id_name_index ON tag_definitions (organization_id, name)"
    )

    # ── transaction_entity_tags ──
    execute(
      "CREATE UNIQUE INDEX transaction_entity_tags_builtin_kind_unique ON transaction_entity_tags (resource_id, kind) WHERE kind <> 'project'::entity_tag_kind"
    )

    execute(
      "CREATE INDEX transaction_entity_tags_organization_id_index ON transaction_entity_tags (organization_id)"
    )

    execute(
      "CREATE UNIQUE INDEX transaction_entity_tags_project_unique ON transaction_entity_tags (resource_id, tag_definition_id) WHERE tag_definition_id IS NOT NULL"
    )

    # ── transactions ──
    execute(
      "CREATE UNIQUE INDEX transactions_internal_transaction_id_organization_id_index ON transactions (internal_transaction_id, organization_id)"
    )

    execute("CREATE INDEX transactions_organization_id_index ON transactions (organization_id)")

    execute("CREATE INDEX transactions_transaction_id_index ON transactions (transaction_id)")

    # ── user_identities ──
    create unique_index(:user_identities, [:strategy, :uid, :user_id],
             name: "user_identities_unique_on_strategy_and_uid_and_user_id_index"
           )

    execute("CREATE INDEX user_identities_user_id_index ON user_identities (user_id)")

    # ── user_salaries ──
    execute(
      "CREATE UNIQUE INDEX user_salaries_active_unique_index ON user_salaries (user_id, organization_id) WHERE deleted_at IS NULL"
    )

    execute("CREATE INDEX user_salaries_organization_id_index ON user_salaries (organization_id)")

    execute("CREATE INDEX user_salaries_user_id_index ON user_salaries (user_id)")

    # ── users ──
    create unique_index(:users, [:email], name: "users_unique_email_index")
    execute("CREATE INDEX users_organization_id_index ON users (organization_id)")

    # ── BM25 search indexes (ParadeDB) ──

    execute("""
    CREATE INDEX cost_invoices_search_idx
    ON cost_invoices
    USING bm25 (id, seller, seller_display_name, description, invoice_identifier)
    WITH (key_field='id', text_fields='{
      "seller": {"tokenizer": {"type": "ngram", "min_gram": 2, "max_gram": 3, "prefix_only": false}},
      "seller_display_name": {"tokenizer": {"type": "ngram", "min_gram": 2, "max_gram": 3, "prefix_only": false}},
      "description": {"tokenizer": {"type": "ngram", "min_gram": 2, "max_gram": 3, "prefix_only": false}},
      "invoice_identifier": {"tokenizer": {"type": "ngram", "min_gram": 2, "max_gram": 6, "prefix_only": true}}
    }')
    """)

    execute("""
    CREATE INDEX counterparties_search_idx
    ON counterparties
    USING bm25 (id, full_name, given_name, surname, tax_id, email, display_name)
    WITH (key_field='id', text_fields='{
      "full_name": {"tokenizer": {"type": "ngram", "min_gram": 2, "max_gram": 4, "prefix_only": false}},
      "given_name": {"tokenizer": {"type": "ngram", "min_gram": 2, "max_gram": 4, "prefix_only": false}},
      "surname": {"tokenizer": {"type": "ngram", "min_gram": 2, "max_gram": 4, "prefix_only": false}},
      "tax_id": {"tokenizer": {"type": "keyword"}},
      "email": {"tokenizer": {"type": "default"}},
      "display_name": {"tokenizer": {"type": "ngram", "min_gram": 2, "max_gram": 4, "prefix_only": false}}
    }')
    """)

    execute("""
    CREATE INDEX projects_search_idx
    ON projects
    USING bm25 (id, name)
    WITH (key_field='id', text_fields='{
      "name": {"tokenizer": {"type": "ngram", "min_gram": 2, "max_gram": 4, "prefix_only": false}}
    }')
    """)

    execute("""
    CREATE INDEX sales_invoices_search_idx
    ON sales_invoices
    USING bm25 (id, buyer_full_name, buyer_given_name, buyer_surname, buyer_email, buyer_description, item_names, invoice_number, buyer_id)
    WITH (key_field='id', text_fields='{
      "buyer_full_name": {"tokenizer": {"type": "ngram", "min_gram": 2, "max_gram": 4, "prefix_only": false}},
      "buyer_given_name": {"tokenizer": {"type": "ngram", "min_gram": 2, "max_gram": 4, "prefix_only": false}},
      "buyer_surname": {"tokenizer": {"type": "ngram", "min_gram": 2, "max_gram": 4, "prefix_only": false}},
      "buyer_email": {"tokenizer": {"type": "default"}},
      "buyer_description": {"tokenizer": {"type": "default"}},
      "item_names": {"tokenizer": {"type": "ngram", "min_gram": 2, "max_gram": 4, "prefix_only": false}},
      "invoice_number": {"tokenizer": {"type": "ngram", "min_gram": 2, "max_gram": 6, "prefix_only": true}},
      "buyer_id": {"tokenizer": {"type": "keyword"}}
    }')
    """)

    execute("""
    CREATE INDEX transactions_search_idx
    ON transactions
    USING bm25 (id, debtor_name, creditor_name, remittance_information_unstructured, transaction_currency)
    WITH (key_field='id', text_fields='{
      "debtor_name": {"tokenizer": {"type": "ngram", "min_gram": 2, "max_gram": 3, "prefix_only": false}},
      "creditor_name": {"tokenizer": {"type": "ngram", "min_gram": 2, "max_gram": 3, "prefix_only": false}},
      "remittance_information_unstructured": {"tokenizer": {"type": "ngram", "min_gram": 2, "max_gram": 3, "prefix_only": false}},
      "transaction_currency": {"tokenizer": {"type": "ngram", "min_gram": 2, "max_gram": 3, "prefix_only": false}}
    }')
    """)
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # FUNCTIONS
  # ═══════════════════════════════════════════════════════════════════════════

  defp add_functions do
    execute("""
    CREATE OR REPLACE FUNCTION prevent_session_overlap()
    RETURNS TRIGGER AS $$
    DECLARE
      new_start timestamp := NEW.start_datetime;
      new_end timestamp := NEW.end_datetime;
    BEGIN
      IF EXISTS (
        SELECT 1 FROM sessions
        WHERE user_id = NEW.user_id
          AND id <> COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000')
          AND (
            start_datetime < COALESCE(new_end, 'infinity') AND COALESCE(end_datetime, 'infinity') > new_start
          )
      ) THEN
        RAISE EXCEPTION 'Session for this user overlaps with an existing session.';
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """)

    execute("""
    CREATE OR REPLACE FUNCTION update_sales_invoice_item_names()
    RETURNS TRIGGER AS $$
    DECLARE
      sid UUID;
    BEGIN
      IF (TG_OP = 'DELETE') THEN
        sid := OLD.sales_invoice_id;
      ELSE
        sid := NEW.sales_invoice_id;
      END IF;

      UPDATE sales_invoices
      SET item_names = COALESCE((
        SELECT string_agg(name, ' ')
        FROM sales_invoice_items
        WHERE sales_invoice_id = sid
      ), '')
      WHERE id = sid;

      RETURN NULL;
    END;
    $$ LANGUAGE plpgsql;
    """)

    execute("""
    CREATE OR REPLACE FUNCTION prevent_locked_sales_invoice_modification()
    RETURNS TRIGGER AS $$
    BEGIN
      IF TG_OP = 'DELETE' THEN
        IF OLD.locked_at IS NOT NULL THEN
          RAISE EXCEPTION 'Cannot delete a locked sales invoice (locked_at is set)';
        END IF;
        RETURN OLD;
      END IF;

      IF TG_OP = 'UPDATE' AND OLD.locked_at IS NOT NULL THEN
        IF ROW(
          OLD.id, OLD.invoice_type, OLD.invoice_number, OLD.sale_date, OLD.issue_date,
          OLD.due_date, OLD.payment_method, OLD.currency,
          OLD.seller_nip, OLD.seller_display_name, OLD.seller_address, OLD.seller_name,
          OLD.seller_surname, OLD.seller_account_number,
          OLD.buyer_type, OLD.buyer_id, OLD.buyer_display_name, OLD.buyer_full_name,
          OLD.buyer_given_name, OLD.buyer_surname, OLD.buyer_pesel, OLD.buyer_address,
          OLD.buyer_country, OLD.buyer_is_different_mail_address, OLD.buyer_mail_address,
          OLD.buyer_mail_country, OLD.buyer_email, OLD.buyer_phone, OLD.buyer_description,
          OLD.is_cash_account, OLD.is_reverse_charge, OLD.item_names,
          OLD.ksef_invoice_kind, OLD.corrected_invoice_id, OLD.counterparty_id,
          OLD.organization_id, OLD.inserted_at
        ) IS DISTINCT FROM ROW(
          NEW.id, NEW.invoice_type, NEW.invoice_number, NEW.sale_date, NEW.issue_date,
          NEW.due_date, NEW.payment_method, NEW.currency,
          NEW.seller_nip, NEW.seller_display_name, NEW.seller_address, NEW.seller_name,
          NEW.seller_surname, NEW.seller_account_number,
          NEW.buyer_type, NEW.buyer_id, NEW.buyer_display_name, NEW.buyer_full_name,
          NEW.buyer_given_name, NEW.buyer_surname, NEW.buyer_pesel, NEW.buyer_address,
          NEW.buyer_country, NEW.buyer_is_different_mail_address, NEW.buyer_mail_address,
          NEW.buyer_mail_country, NEW.buyer_email, NEW.buyer_phone, NEW.buyer_description,
          NEW.is_cash_account, NEW.is_reverse_charge, NEW.item_names,
          NEW.ksef_invoice_kind, NEW.corrected_invoice_id, NEW.counterparty_id,
          NEW.organization_id, NEW.inserted_at
        ) THEN
          RAISE EXCEPTION 'Cannot modify a locked sales invoice. Only ksef_number, ksef_session_reference_number, ksef_invoice_checksum, locked_at, and skip_invoicing may be updated.';
        END IF;
      END IF;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """)

    execute("""
    CREATE OR REPLACE FUNCTION prevent_ksef_cost_invoice_modification()
    RETURNS TRIGGER AS $$
    BEGIN
      IF OLD.ksef_number IS NOT NULL THEN
        IF TG_OP = 'DELETE' THEN
          RAISE EXCEPTION 'Cannot delete a KSeF-imported cost invoice';
        END IF;
      END IF;

      RETURN OLD;
    END;
    $$ LANGUAGE plpgsql;
    """)

    # ── Entity tag functions ──

    execute("""
    CREATE OR REPLACE FUNCTION check_cost_invoice_entity_tag_taggable()
    RETURNS TRIGGER AS $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM cost_invoices ci WHERE ci.id = NEW.resource_id AND ci.skip_invoicing = true
      ) AND NOT EXISTS (
        SELECT 1 FROM cost_invoices_transactions cit WHERE cit.cost_invoice_id = NEW.resource_id
      ) THEN
        RAISE EXCEPTION 'Cannot tag a cost invoice that is neither matched nor skipped';
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """)

    execute("""
    CREATE OR REPLACE FUNCTION check_cost_invoice_entity_tags_category_exclusivity()
    RETURNS TRIGGER AS $$
    BEGIN
      IF NEW.kind = 'project' THEN
        IF EXISTS (
          SELECT 1 FROM cost_invoice_entity_tags et
          WHERE et.resource_id = NEW.resource_id AND et.kind != 'project'
        ) THEN
          RAISE EXCEPTION 'Cannot add project tag: entity already has a built-in category (company or internal)';
        END IF;
      ELSE
        IF EXISTS (
          SELECT 1 FROM cost_invoice_entity_tags et
          WHERE et.resource_id = NEW.resource_id
        ) THEN
          RAISE EXCEPTION 'Cannot set built-in category: entity already has tags assigned';
        END IF;
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """)

    execute("""
    CREATE OR REPLACE FUNCTION check_sales_invoice_entity_tag_taggable()
    RETURNS TRIGGER AS $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM sales_invoices si WHERE si.id = NEW.resource_id AND si.skip_invoicing = true
      ) AND NOT EXISTS (
        SELECT 1 FROM sales_invoices_transactions sit WHERE sit.sales_invoice_id = NEW.resource_id
      ) THEN
        RAISE EXCEPTION 'Cannot tag a sales invoice that is neither matched nor skipped';
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """)

    execute("""
    CREATE OR REPLACE FUNCTION check_sales_invoice_entity_tags_category_exclusivity()
    RETURNS TRIGGER AS $$
    BEGIN
      IF NEW.kind = 'project' THEN
        IF EXISTS (
          SELECT 1 FROM sales_invoice_entity_tags et
          WHERE et.resource_id = NEW.resource_id AND et.kind != 'project'
        ) THEN
          RAISE EXCEPTION 'Cannot add project tag: entity already has a built-in category (company or internal)';
        END IF;
      ELSE
        IF EXISTS (
          SELECT 1 FROM sales_invoice_entity_tags et
          WHERE et.resource_id = NEW.resource_id
        ) THEN
          RAISE EXCEPTION 'Cannot set built-in category: entity already has tags assigned';
        END IF;
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """)

    execute("""
    CREATE OR REPLACE FUNCTION check_transaction_entity_tag_taggable()
    RETURNS TRIGGER AS $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM transactions t WHERE t.id = NEW.resource_id AND t.skip_invoicing = true
      ) AND NOT EXISTS (
        SELECT 1 FROM cost_invoices_transactions cit WHERE cit.transaction_id = NEW.resource_id
      ) AND NOT EXISTS (
        SELECT 1 FROM sales_invoices_transactions sit WHERE sit.transaction_id = NEW.resource_id
      ) THEN
        RAISE EXCEPTION 'Cannot tag a transaction that is neither matched nor skipped';
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """)

    execute("""
    CREATE OR REPLACE FUNCTION check_transaction_entity_tags_category_exclusivity()
    RETURNS TRIGGER AS $$
    BEGIN
      IF NEW.kind = 'project' THEN
        IF EXISTS (
          SELECT 1 FROM transaction_entity_tags et
          WHERE et.resource_id = NEW.resource_id AND et.kind != 'project'
        ) THEN
          RAISE EXCEPTION 'Cannot add project tag: entity already has a built-in category (company or internal)';
        END IF;
      ELSE
        IF EXISTS (
          SELECT 1 FROM transaction_entity_tags et
          WHERE et.resource_id = NEW.resource_id
        ) THEN
          RAISE EXCEPTION 'Cannot set built-in category: entity already has tags assigned';
        END IF;
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """)
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # TRIGGERS
  # ═══════════════════════════════════════════════════════════════════════════

  defp add_triggers do
    # Session overlap — fires on INSERT OR UPDATE (matches production)
    execute("""
    CREATE TRIGGER no_session_overlap_trigger
    BEFORE INSERT OR UPDATE ON sessions
    FOR EACH ROW EXECUTE FUNCTION prevent_session_overlap();
    """)

    # Sales invoice item names — fires on INSERT, UPDATE, DELETE (matches production)
    execute("""
    CREATE TRIGGER sales_invoice_items_update_names
    AFTER INSERT OR DELETE OR UPDATE ON sales_invoice_items
    FOR EACH ROW EXECUTE FUNCTION update_sales_invoice_item_names();
    """)

    # Locked sales invoice — fires on DELETE OR UPDATE (matches production)
    execute("""
    CREATE TRIGGER locked_sales_invoice_trigger
    BEFORE DELETE OR UPDATE ON sales_invoices
    FOR EACH ROW EXECUTE FUNCTION prevent_locked_sales_invoice_modification();
    """)

    # KSeF cost invoice — fires on DELETE only (matches production)
    execute("""
    CREATE TRIGGER ksef_cost_invoice_trigger
    BEFORE DELETE ON cost_invoices
    FOR EACH ROW EXECUTE FUNCTION prevent_ksef_cost_invoice_modification();
    """)

    # Entity tag triggers — BEFORE INSERT only (matches production exactly)
    for {table, prefix} <- [
          {"cost_invoice_entity_tags", "cost_invoice"},
          {"sales_invoice_entity_tags", "sales_invoice"},
          {"transaction_entity_tags", "transaction"}
        ] do
      execute("""
      CREATE TRIGGER #{prefix}_entity_tag_taggable_trigger
      BEFORE INSERT ON #{table}
      FOR EACH ROW EXECUTE FUNCTION check_#{prefix}_entity_tag_taggable();
      """)

      execute("""
      CREATE TRIGGER #{prefix}_entity_tags_category_exclusivity_trigger
      BEFORE INSERT ON #{table}
      FOR EACH ROW EXECUTE FUNCTION check_#{prefix}_entity_tags_category_exclusivity();
      """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # CHECK CONSTRAINTS
  # ═══════════════════════════════════════════════════════════════════════════

  defp add_check_constraints do
    # counterparties_fields_by_type — matches production's CASE/WHEN + COALESCE form
    execute("""
    ALTER TABLE counterparties
      ADD CONSTRAINT counterparties_fields_by_type
      CHECK (
        CASE type
          WHEN 'company'::text THEN
            (COALESCE(full_name, ''::character varying))::text <> ''::text
            AND (COALESCE(given_name, ''::character varying))::text = ''::text
            AND (COALESCE(surname, ''::character varying))::text = ''::text
          WHEN 'individual'::text THEN
            (COALESCE(full_name, ''::character varying))::text = ''::text
            AND (COALESCE(given_name, ''::character varying))::text <> ''::text
            AND (COALESCE(surname, ''::character varying))::text <> ''::text
          ELSE true
        END
      );
    """)

    # cost_invoices_non_correction_total_amount_non_positive — matches production's varchar[] cast form
    execute("""
    ALTER TABLE cost_invoices
      ADD CONSTRAINT cost_invoices_non_correction_total_amount_non_positive
      CHECK (
        COALESCE((invoice_type)::text = ANY ((ARRAY['kor'::character varying, 'kor_zal'::character varying, 'kor_roz'::character varying])::text[]), false)
        OR total_amount <= (0)::numeric
      );
    """)

    # valid_vat_rate on sales_invoice_items — present in production, was missing from baseline
    execute("""
    ALTER TABLE sales_invoice_items
      ADD CONSTRAINT valid_vat_rate
      CHECK (
        (vat_rate)::text = ANY ((ARRAY[
          '23'::character varying, '22'::character varying,
          '8'::character varying, '7'::character varying,
          '5'::character varying, '4'::character varying,
          '3'::character varying, '0 KR'::character varying,
          '0 WDT'::character varying, '0 EX'::character varying,
          'zw'::character varying, 'oo'::character varying,
          'np I'::character varying, 'np II'::character varying
        ])::text[])
      );
    """)

    # Entity tag kind/tag_definition checks — all three tables
    for table <- [
          "cost_invoice_entity_tags",
          "sales_invoice_entity_tags",
          "transaction_entity_tags"
        ] do
      execute("""
      ALTER TABLE #{table}
        ADD CONSTRAINT #{table}_kind_tag_definition_check
        CHECK (
          (kind = 'project'::entity_tag_kind AND tag_definition_id IS NOT NULL) OR
          (kind <> 'project'::entity_tag_kind AND tag_definition_id IS NULL)
        );
      """)
    end
  end
end
