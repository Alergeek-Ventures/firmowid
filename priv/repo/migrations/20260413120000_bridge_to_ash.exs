defmodule Firmowid.Repo.Migrations.BridgeToAsh do
  @moduledoc """
  Bridge migration that transforms the production schema (baseline) into the
  state that Ash/AshPostgres expects.

  This migration is designed to run on top of the baseline migration
  (`20260412150547_baseline_schema`). On production, the baseline is skipped
  (its timestamp is pre-inserted into `schema_migrations`), so this migration
  bridges from production's current state to Ash-native types.

  Categories of changes:
   1. varchar/varchar(N) → text
   2. integer → bigint
   3. numeric(10,2) → numeric (bare decimal)
   4. enum types → text (+ drop unused enums)
   5. jsonb → jsonb[] (cost_invoices.items_list)
   6. Timestamp precision adjustments
   7. Add column defaults (UUIDs, timestamps, value defaults)
   8. Remove outdated defaults
   9. Nullability changes
  10. Dead column removal
  11. Index renames/restructures
  12. FK constraint renames and additions
  """

  use Ecto.Migration

  # sobelow_skip ["SQL.Query"]
  # All SQL here is static/hardcoded DDL for schema migration,
  # not user-controlled input.

  def up do
    # Order matters: drop old indexes first (some will be recreated with different
    # columns/names), then alter columns, then create new indexes and FKs.

    drop_old_indexes()
    alter_columns()
    remove_dead_columns()
    create_new_indexes()
    change_fk_constraints()
    drop_unused_enums()
  end

  def down do
    raise "Irreversible migration — use mix ecto.reset to recreate from scratch"
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # PHASE 1: DROP OLD INDEXES
  # ═══════════════════════════════════════════════════════════════════════════
  # Drop indexes that need renaming or column reordering before column type
  # changes (safer ordering). Indexes that keep the same name but change
  # columns are also dropped here.

  defp drop_old_indexes do
    for idx <- [
          "bank_accounts_iban_organization_id_index",
          "bank_accounts_organization_id_currency_is_default_index",
          "blobs_unique_checksum_per_org_index",
          "cost_invoices_ksef_number_idx",
          "exchange_rates_cache_cache_date_index",
          "hours_records_month_year_organization_id_user_id_index",
          "inbound_emails_resend_email_id_index",
          "ksef_credentials_organization_id_index",
          "organizations_inbound_email_nickname_index",
          "projects_users_project_id_user_id_index",
          "sales_invoices_invoice_number_organization_id_index",
          "tags_organization_id_name_index",
          "transactions_internal_transaction_id_organization_id_index",
          "user_salaries_active_unique_index"
        ] do
      execute("DROP INDEX IF EXISTS #{idx}")
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # PHASE 2: ALTER COLUMNS
  # ═══════════════════════════════════════════════════════════════════════════
  # Handles: type changes, defaults, and nullability — grouped per table
  # for efficiency (single ALTER TABLE per table where possible).

  defp alter_columns do
    alter_ash_events()
    alter_bank_accounts()
    alter_blobs()
    alter_cost_invoices()
    alter_cost_invoices_transactions()
    alter_counterparties()
    alter_exchange_rates_cache()
    alter_hours_records()
    alter_inbound_emails()
    alter_ksef_credentials()
    alter_organization_invites()
    alter_organizations()
    alter_projects()
    alter_projects_users()
    alter_requisitions()
    alter_sales_invoice_items()
    alter_sales_invoices()
    alter_sales_invoices_transactions()
    alter_sessions()
    alter_tag_definitions()
    alter_tokens()
    alter_transactions()
    alter_user_identities()
    alter_user_salaries()
    alter_users()
  end

  # ── ash_events ──────────────────────────────────────────────────────────

  defp alter_ash_events do
    execute("""
    ALTER TABLE ash_events
      ALTER COLUMN id SET DEFAULT uuid_generate_v7()
    """)
  end

  # ── bank_accounts ───────────────────────────────────────────────────────

  defp alter_bank_accounts do
    execute("""
    ALTER TABLE bank_accounts
      ALTER COLUMN iban TYPE text,
      ALTER COLUMN institution_id TYPE text,
      ALTER COLUMN institution_name TYPE text,
      ALTER COLUMN owner_name TYPE text,
      ALTER COLUMN gocardless_id TYPE text,
      ALTER COLUMN currency TYPE text,
      ALTER COLUMN name TYPE text,
      ALTER COLUMN id SET DEFAULT uuid_generate_v7(),
      ALTER COLUMN gocardless_id DROP DEFAULT,
      ALTER COLUMN inserted_at SET DEFAULT (now() AT TIME ZONE 'utc'),
      ALTER COLUMN updated_at SET DEFAULT (now() AT TIME ZONE 'utc'),
      ALTER COLUMN is_default DROP NOT NULL
    """)
  end

  # ── blobs ───────────────────────────────────────────────────────────────

  defp alter_blobs do
    execute("""
    ALTER TABLE blobs
      ALTER COLUMN blob_path TYPE text,
      ALTER COLUMN blob_checksum TYPE text,
      ALTER COLUMN original_filename TYPE text,
      ALTER COLUMN processing_target TYPE text,
      ALTER COLUMN processing_state TYPE text,
      ALTER COLUMN id SET DEFAULT uuid_generate_v7(),
      ALTER COLUMN inserted_at SET DEFAULT (now() AT TIME ZONE 'utc'),
      ALTER COLUMN updated_at SET DEFAULT (now() AT TIME ZONE 'utc')
    """)
  end

  # ── cost_invoices ───────────────────────────────────────────────────────

  defp alter_cost_invoices do
    # items_list needs special handling: jsonb → jsonb[]
    # PostgreSQL doesn't allow subqueries in USING, so we use a helper function.
    execute("""
    CREATE OR REPLACE FUNCTION pg_temp.jsonb_to_jsonb_array(val jsonb)
    RETURNS jsonb[] AS $$
      SELECT COALESCE(array_agg(elem), ARRAY[]::jsonb[])
      FROM jsonb_array_elements(val) AS elem;
    $$ LANGUAGE SQL IMMUTABLE
    """)

    execute("""
    ALTER TABLE cost_invoices
      ALTER COLUMN items_list DROP DEFAULT
    """)

    execute("""
    ALTER TABLE cost_invoices
      ALTER COLUMN items_list TYPE jsonb[]
        USING pg_temp.jsonb_to_jsonb_array(items_list)
    """)

    execute("""
    ALTER TABLE cost_invoices
      ALTER COLUMN items_list SET DEFAULT ARRAY[]::jsonb[]
    """)

    # Remaining column type changes, defaults, nullability
    execute("""
    ALTER TABLE cost_invoices
      ALTER COLUMN seller TYPE text,
      ALTER COLUMN seller_display_name TYPE text,
      ALTER COLUMN account_number TYPE text,
      ALTER COLUMN seller_address TYPE text,
      ALTER COLUMN ksef_number TYPE text,
      ALTER COLUMN seller_nip TYPE text,
      ALTER COLUMN seller_country_code TYPE text,
      ALTER COLUMN seller_email TYPE text,
      ALTER COLUMN seller_phone TYPE text,
      ALTER COLUMN invoice_type TYPE text,
      ALTER COLUMN original_invoice_ksef_number TYPE text,
      ALTER COLUMN payment_method TYPE text,
      ALTER COLUMN currency TYPE text,
      ALTER COLUMN invoice_identifier TYPE text,
      ALTER COLUMN total_amount TYPE numeric,
      ALTER COLUMN ksef_permanent_storage_date TYPE timestamp(0) without time zone,
      ALTER COLUMN id SET DEFAULT uuid_generate_v7(),
      ALTER COLUMN inserted_at SET DEFAULT (now() AT TIME ZONE 'utc'),
      ALTER COLUMN updated_at SET DEFAULT (now() AT TIME ZONE 'utc'),
      ALTER COLUMN seller DROP NOT NULL,
      ALTER COLUMN seller_display_name DROP NOT NULL,
      ALTER COLUMN sale_date DROP NOT NULL,
      ALTER COLUMN issue_date DROP NOT NULL,
      ALTER COLUMN due_date DROP NOT NULL,
      ALTER COLUMN total_amount DROP NOT NULL,
      ALTER COLUMN currency DROP NOT NULL,
      ALTER COLUMN invoice_identifier DROP NOT NULL,
      ALTER COLUMN skip_invoicing DROP NOT NULL
    """)
  end

  # ── cost_invoices_transactions ──────────────────────────────────────────

  defp alter_cost_invoices_transactions do
    execute("""
    ALTER TABLE cost_invoices_transactions
      ALTER COLUMN id SET DEFAULT uuid_generate_v7(),
      ALTER COLUMN inserted_at SET DEFAULT (now() AT TIME ZONE 'utc'),
      ALTER COLUMN updated_at SET DEFAULT (now() AT TIME ZONE 'utc')
    """)
  end

  # ── counterparties ──────────────────────────────────────────────────────

  defp alter_counterparties do
    execute("""
    ALTER TABLE counterparties
      ALTER COLUMN type TYPE text,
      ALTER COLUMN tax_id TYPE text,
      ALTER COLUMN full_name TYPE text,
      ALTER COLUMN given_name TYPE text,
      ALTER COLUMN surname TYPE text,
      ALTER COLUMN pesel TYPE text,
      ALTER COLUMN address TYPE text,
      ALTER COLUMN country TYPE text,
      ALTER COLUMN mail_address TYPE text,
      ALTER COLUMN mail_country TYPE text,
      ALTER COLUMN email TYPE text,
      ALTER COLUMN phone TYPE text,
      ALTER COLUMN description TYPE text,
      ALTER COLUMN display_name TYPE text,
      ALTER COLUMN id SET DEFAULT uuid_generate_v7(),
      ALTER COLUMN type SET DEFAULT 'company',
      ALTER COLUMN inserted_at SET DEFAULT (now() AT TIME ZONE 'utc'),
      ALTER COLUMN updated_at SET DEFAULT (now() AT TIME ZONE 'utc'),
      ALTER COLUMN type DROP NOT NULL,
      ALTER COLUMN is_different_mail_address DROP NOT NULL
    """)
  end

  # ── exchange_rates_cache ────────────────────────────────────────────────

  defp alter_exchange_rates_cache do
    execute("""
    ALTER TABLE exchange_rates_cache
      ALTER COLUMN id SET DEFAULT uuid_generate_v7(),
      ALTER COLUMN expires_at DROP DEFAULT,
      ALTER COLUMN inserted_at SET DEFAULT (now() AT TIME ZONE 'utc'),
      ALTER COLUMN updated_at SET DEFAULT (now() AT TIME ZONE 'utc')
    """)
  end

  # ── hours_records ───────────────────────────────────────────────────────

  defp alter_hours_records do
    execute("""
    ALTER TABLE hours_records
      ALTER COLUMN month TYPE bigint,
      ALTER COLUMN year TYPE bigint,
      ALTER COLUMN number_of_hours TYPE bigint,
      ALTER COLUMN id SET DEFAULT uuid_generate_v7(),
      ALTER COLUMN inserted_at SET DEFAULT (now() AT TIME ZONE 'utc'),
      ALTER COLUMN updated_at SET DEFAULT (now() AT TIME ZONE 'utc'),
      ALTER COLUMN blob_id SET NOT NULL
    """)
  end

  # ── inbound_emails ──────────────────────────────────────────────────────

  defp alter_inbound_emails do
    execute("""
    ALTER TABLE inbound_emails
      ALTER COLUMN resend_email_id TYPE text,
      ALTER COLUMN sender_email TYPE text,
      ALTER COLUMN failure_reason TYPE text,
      ALTER COLUMN id SET DEFAULT uuid_generate_v7(),
      ALTER COLUMN inserted_at SET DEFAULT (now() AT TIME ZONE 'utc'),
      ALTER COLUMN updated_at SET DEFAULT (now() AT TIME ZONE 'utc')
    """)
  end

  # ── ksef_credentials ────────────────────────────────────────────────────

  defp alter_ksef_credentials do
    execute("""
    ALTER TABLE ksef_credentials
      ALTER COLUMN auth_type TYPE text,
      ALTER COLUMN inserted_at TYPE timestamp without time zone,
      ALTER COLUMN updated_at TYPE timestamp without time zone,
      ALTER COLUMN id SET DEFAULT uuid_generate_v7(),
      ALTER COLUMN inserted_at SET DEFAULT (now() AT TIME ZONE 'utc'),
      ALTER COLUMN updated_at SET DEFAULT (now() AT TIME ZONE 'utc')
    """)
  end

  # ── organization_invites ────────────────────────────────────────────────

  defp alter_organization_invites do
    execute("""
    ALTER TABLE organization_invites
      ALTER COLUMN invite_code TYPE text,
      ALTER COLUMN id SET DEFAULT uuid_generate_v7(),
      ALTER COLUMN inserted_at SET DEFAULT (now() AT TIME ZONE 'utc'),
      ALTER COLUMN updated_at SET DEFAULT (now() AT TIME ZONE 'utc')
    """)
  end

  # ── organizations ───────────────────────────────────────────────────────

  defp alter_organizations do
    execute("""
    ALTER TABLE organizations
      ALTER COLUMN nip TYPE text,
      ALTER COLUMN address TYPE text,
      ALTER COLUMN name TYPE text,
      ALTER COLUMN phone_number TYPE text,
      ALTER COLUMN organization_type TYPE text,
      ALTER COLUMN correspondence_name TYPE text,
      ALTER COLUMN correspondence_address TYPE text,
      ALTER COLUMN id SET DEFAULT uuid_generate_v7(),
      ALTER COLUMN inserted_at SET DEFAULT (now() AT TIME ZONE 'utc'),
      ALTER COLUMN updated_at SET DEFAULT (now() AT TIME ZONE 'utc')
    """)
  end

  # ── projects ────────────────────────────────────────────────────────────

  defp alter_projects do
    execute("""
    ALTER TABLE projects
      ALTER COLUMN name TYPE text,
      ALTER COLUMN id SET DEFAULT uuid_generate_v7(),
      ALTER COLUMN inserted_at SET DEFAULT (now() AT TIME ZONE 'utc'),
      ALTER COLUMN updated_at SET DEFAULT (now() AT TIME ZONE 'utc'),
      ALTER COLUMN name SET NOT NULL
    """)
  end

  # ── projects_users ──────────────────────────────────────────────────────

  defp alter_projects_users do
    execute("""
    ALTER TABLE projects_users
      ALTER COLUMN id SET DEFAULT uuid_generate_v7(),
      ALTER COLUMN inserted_at SET DEFAULT (now() AT TIME ZONE 'utc'),
      ALTER COLUMN updated_at SET DEFAULT (now() AT TIME ZONE 'utc')
    """)
  end

  # ── requisitions ────────────────────────────────────────────────────────

  defp alter_requisitions do
    execute("""
    ALTER TABLE requisitions
      ALTER COLUMN status TYPE text USING status::text,
      ALTER COLUMN status SET DEFAULT 'pending',
      ALTER COLUMN inserted_at SET DEFAULT (now() AT TIME ZONE 'utc'),
      ALTER COLUMN updated_at SET DEFAULT (now() AT TIME ZONE 'utc')
    """)
  end

  # ── sales_invoice_items ─────────────────────────────────────────────────

  defp alter_sales_invoice_items do
    execute("""
    ALTER TABLE sales_invoice_items
      ALTER COLUMN name TYPE text,
      ALTER COLUMN unit TYPE text,
      ALTER COLUMN vat_rate TYPE text,
      ALTER COLUMN index TYPE bigint,
      ALTER COLUMN id SET DEFAULT uuid_generate_v7(),
      ALTER COLUMN inserted_at SET DEFAULT (now() AT TIME ZONE 'utc'),
      ALTER COLUMN updated_at SET DEFAULT (now() AT TIME ZONE 'utc')
    """)
  end

  # ── sales_invoices ──────────────────────────────────────────────────────

  defp alter_sales_invoices do
    execute("""
    ALTER TABLE sales_invoices
      ALTER COLUMN invoice_type TYPE text,
      ALTER COLUMN invoice_number TYPE text,
      ALTER COLUMN currency TYPE text,
      ALTER COLUMN seller_nip TYPE text,
      ALTER COLUMN seller_display_name TYPE text,
      ALTER COLUMN seller_address TYPE text,
      ALTER COLUMN seller_account_number TYPE text,
      ALTER COLUMN seller_name TYPE text,
      ALTER COLUMN seller_surname TYPE text,
      ALTER COLUMN buyer_type TYPE text,
      ALTER COLUMN buyer_id TYPE text,
      ALTER COLUMN buyer_pesel TYPE text,
      ALTER COLUMN buyer_full_name TYPE text,
      ALTER COLUMN buyer_given_name TYPE text,
      ALTER COLUMN buyer_surname TYPE text,
      ALTER COLUMN buyer_address TYPE text,
      ALTER COLUMN buyer_country TYPE text,
      ALTER COLUMN buyer_email TYPE text,
      ALTER COLUMN buyer_phone TYPE text,
      ALTER COLUMN buyer_description TYPE text,
      ALTER COLUMN buyer_mail_address TYPE text,
      ALTER COLUMN buyer_mail_country TYPE text,
      ALTER COLUMN buyer_display_name TYPE text,
      ALTER COLUMN ksef_number TYPE text,
      ALTER COLUMN ksef_session_reference_number TYPE text,
      ALTER COLUMN ksef_invoice_kind TYPE text,
      ALTER COLUMN correction_reason TYPE text,
      ALTER COLUMN share_token TYPE text,
      ALTER COLUMN ksef_invoice_checksum TYPE text,
      ALTER COLUMN payment_method TYPE text USING payment_method::text,
      ALTER COLUMN id SET DEFAULT uuid_generate_v7(),
      ALTER COLUMN invoice_type SET DEFAULT 'poland',
      ALTER COLUMN buyer_type SET DEFAULT 'company',
      ALTER COLUMN payment_method SET DEFAULT 'transfer',
      ALTER COLUMN inserted_at SET DEFAULT (now() AT TIME ZONE 'utc'),
      ALTER COLUMN updated_at SET DEFAULT (now() AT TIME ZONE 'utc'),
      ALTER COLUMN invoice_type DROP NOT NULL,
      ALTER COLUMN buyer_type DROP NOT NULL,
      ALTER COLUMN buyer_is_different_mail_address DROP NOT NULL,
      ALTER COLUMN is_cash_account DROP NOT NULL,
      ALTER COLUMN is_reverse_charge DROP NOT NULL,
      ALTER COLUMN skip_invoicing DROP NOT NULL,
      ALTER COLUMN currency DROP NOT NULL
    """)
  end

  # ── sales_invoices_transactions ─────────────────────────────────────────

  defp alter_sales_invoices_transactions do
    execute("""
    ALTER TABLE sales_invoices_transactions
      ALTER COLUMN id SET DEFAULT uuid_generate_v7(),
      ALTER COLUMN inserted_at SET DEFAULT (now() AT TIME ZONE 'utc'),
      ALTER COLUMN updated_at SET DEFAULT (now() AT TIME ZONE 'utc')
    """)
  end

  # ── sessions ────────────────────────────────────────────────────────────

  defp alter_sessions do
    execute("""
    ALTER TABLE sessions
      ALTER COLUMN title TYPE text,
      ALTER COLUMN id SET DEFAULT uuid_generate_v7(),
      ALTER COLUMN inserted_at SET DEFAULT (now() AT TIME ZONE 'utc'),
      ALTER COLUMN updated_at SET DEFAULT (now() AT TIME ZONE 'utc'),
      ALTER COLUMN project_id SET NOT NULL
    """)
  end

  # ── tag_definitions ─────────────────────────────────────────────────────

  defp alter_tag_definitions do
    execute("""
    ALTER TABLE tag_definitions
      ALTER COLUMN name TYPE text,
      ALTER COLUMN color TYPE text,
      ALTER COLUMN id SET DEFAULT uuid_generate_v7(),
      ALTER COLUMN inserted_at SET DEFAULT (now() AT TIME ZONE 'utc'),
      ALTER COLUMN updated_at SET DEFAULT (now() AT TIME ZONE 'utc')
    """)
  end

  # ── tokens ──────────────────────────────────────────────────────────────

  defp alter_tokens do
    execute("""
    ALTER TABLE tokens
      ALTER COLUMN inserted_at SET DEFAULT (now() AT TIME ZONE 'utc'),
      ALTER COLUMN updated_at SET DEFAULT (now() AT TIME ZONE 'utc')
    """)
  end

  # ── transactions ────────────────────────────────────────────────────────

  defp alter_transactions do
    execute("""
    ALTER TABLE transactions
      ALTER COLUMN transaction_id TYPE text,
      ALTER COLUMN internal_transaction_id TYPE text,
      ALTER COLUMN creditor_name TYPE text,
      ALTER COLUMN creditor_account TYPE text,
      ALTER COLUMN debtor_name TYPE text,
      ALTER COLUMN debtor_account TYPE text,
      ALTER COLUMN transaction_currency TYPE text,
      ALTER COLUMN transaction_amount TYPE numeric,
      ALTER COLUMN id SET DEFAULT uuid_generate_v7(),
      ALTER COLUMN inserted_at SET DEFAULT (now() AT TIME ZONE 'utc'),
      ALTER COLUMN updated_at SET DEFAULT (now() AT TIME ZONE 'utc')
    """)
  end

  # ── user_identities ─────────────────────────────────────────────────────

  defp alter_user_identities do
    execute("""
    ALTER TABLE user_identities
      ALTER COLUMN inserted_at TYPE timestamp(0) without time zone,
      ALTER COLUMN updated_at TYPE timestamp(0) without time zone,
      ALTER COLUMN access_token_expires_at TYPE timestamp without time zone,
      ALTER COLUMN inserted_at SET DEFAULT (now() AT TIME ZONE 'utc'),
      ALTER COLUMN updated_at SET DEFAULT (now() AT TIME ZONE 'utc'),
      ALTER COLUMN user_id DROP NOT NULL
    """)
  end

  # ── user_salaries ───────────────────────────────────────────────────────

  defp alter_user_salaries do
    execute("""
    ALTER TABLE user_salaries
      ALTER COLUMN hourly_rate TYPE numeric,
      ALTER COLUMN id SET DEFAULT uuid_generate_v7(),
      ALTER COLUMN inserted_at SET DEFAULT (now() AT TIME ZONE 'utc'),
      ALTER COLUMN updated_at SET DEFAULT (now() AT TIME ZONE 'utc')
    """)
  end

  # ── users ───────────────────────────────────────────────────────────────

  defp alter_users do
    execute("""
    ALTER TABLE users
      ALTER COLUMN hashed_password TYPE text,
      ALTER COLUMN system_role TYPE text,
      ALTER COLUMN role TYPE text,
      ALTER COLUMN name TYPE text,
      ALTER COLUMN phone TYPE text,
      ALTER COLUMN slack_url TYPE text,
      ALTER COLUMN slack_id TYPE text,
      ALTER COLUMN bank_account_number TYPE text,
      ALTER COLUMN "position" TYPE text,
      ALTER COLUMN employment_contract_type TYPE text USING employment_contract_type::text,
      ALTER COLUMN correspondence_street TYPE text,
      ALTER COLUMN correspondence_city TYPE text,
      ALTER COLUMN correspondence_code TYPE text,
      ALTER COLUMN residence_street TYPE text,
      ALTER COLUMN residence_city TYPE text,
      ALTER COLUMN residence_code TYPE text,
      ALTER COLUMN id SET DEFAULT uuid_generate_v7(),
      ALTER COLUMN inserted_at SET DEFAULT (now() AT TIME ZONE 'utc'),
      ALTER COLUMN updated_at SET DEFAULT (now() AT TIME ZONE 'utc')
    """)
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # PHASE 3: REMOVE DEAD COLUMNS
  # ═══════════════════════════════════════════════════════════════════════════

  defp remove_dead_columns do
    alter table(:users) do
      remove :email_change_confirmed_at
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # PHASE 4: CREATE NEW INDEXES
  # ═══════════════════════════════════════════════════════════════════════════
  # Recreate indexes with new names and/or column orderings per Ash snapshots.

  defp create_new_indexes do
    # bank_accounts
    create unique_index(:bank_accounts, [:organization_id, :iban],
             name: "bank_accounts_unique_iban_per_org_index"
           )

    create unique_index(:bank_accounts, [:organization_id, :currency],
             name: "bank_accounts_organization_id_currency_is_default_index",
             where: "(is_default = true)"
           )

    # blobs — same name, new column order
    create unique_index(:blobs, [:organization_id, :blob_checksum],
             name: "blobs_unique_checksum_per_org_index"
           )

    # cost_invoices — new compound index
    create unique_index(:cost_invoices, [:organization_id, :ksef_number],
             name: "cost_invoices_ksef_number_index"
           )

    # exchange_rates_cache — rename
    create unique_index(:exchange_rates_cache, [:cache_date],
             name: "exchange_rates_cache_unique_cache_date_index"
           )

    # hours_records — new column order
    create unique_index(:hours_records, [:organization_id, :month, :year, :user_id],
             name: "hours_records_unique_month_year_user_index"
           )

    # inbound_emails — new compound index
    create unique_index(:inbound_emails, [:organization_id, :resend_email_id],
             name: "inbound_emails_unique_resend_email_id_index"
           )

    # ksef_credentials — rename
    create unique_index(:ksef_credentials, [:organization_id],
             name: "ksef_credentials_unique_organization_index"
           )

    # organizations — rename
    create unique_index(:organizations, [:inbound_email_nickname],
             name: "organizations_unique_nickname_index"
           )

    # projects — new index
    create unique_index(:projects, [:organization_id, :name],
             name: "projects_unique_name_per_org_index"
           )

    # projects_users — new compound index (adds organization_id)
    create unique_index(:projects_users, [:organization_id, :project_id, :user_id],
             name: "projects_users_unique_project_user_index"
           )

    # requisitions — new index
    create unique_index(:requisitions, [:organization_id, :id],
             name: "requisitions_unique_id_index"
           )

    # sales_invoices — renamed + reordered + nulls_distinct
    create unique_index(:sales_invoices, [:organization_id, :invoice_number],
             name: "sales_invoices_invoice_number_per_org_index",
             nulls_distinct: false
           )

    # tag_definitions — rename
    create unique_index(:tag_definitions, [:organization_id, :name],
             name: "tag_definitions_unique_name_per_org_index"
           )

    # transactions — renamed + reordered
    create unique_index(:transactions, [:organization_id, :internal_transaction_id],
             name: "transactions_unique_internal_tx_per_org_index"
           )

    # user_salaries — renamed + reordered + nulls_distinct
    create unique_index(:user_salaries, [:organization_id, :user_id],
             name: "user_salaries_active_user_salary_index",
             nulls_distinct: false,
             where: "(deleted_at IS NULL)"
           )
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # PHASE 5: FK CONSTRAINT CHANGES
  # ═══════════════════════════════════════════════════════════════════════════

  defp change_fk_constraints do
    # Rename: projects_tag_id_fkey → projects_tag_definition_id_fkey
    execute(
      "ALTER TABLE projects RENAME CONSTRAINT projects_tag_id_fkey TO projects_tag_definition_id_fkey"
    )

    # Rename: tags_organization_id_fkey → tag_definitions_organization_id_fkey
    execute(
      "ALTER TABLE tag_definitions RENAME CONSTRAINT tags_organization_id_fkey TO tag_definitions_organization_id_fkey"
    )

    # NOTE: NOT creating FK cost_invoices_original_invoice_ksef_number_fkey here.
    # AshPostgres multitenancy requires MATCH FULL for compound FKs, but
    # original_invoice_ksef_number is nullable (most cost invoices aren't corrections).
    # MATCH FULL + nullable source + non-null organization_id = broken inserts.
    # The CostInvoice resource uses `references do reference :original_invoice, ignore?: true end`
    # to tell Ash not to manage this FK. The relationship still works for queries.
    # We create a regular index instead (Ash expects this for the belongs_to relationship).
    create index(:cost_invoices, [:organization_id, :original_invoice_ksef_number])
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # PHASE 6: DROP UNUSED ENUM TYPES
  # ═══════════════════════════════════════════════════════════════════════════
  # After converting enum columns to text, the enum types are orphaned.
  # entity_tag_kind is kept — it's used by entity_tag tables (not Ash-managed).

  defp drop_unused_enums do
    execute("DROP TYPE IF EXISTS employment_contract_type")
    execute("DROP TYPE IF EXISTS payment_method_type")
    execute("DROP TYPE IF EXISTS requisition_status")
  end
end
