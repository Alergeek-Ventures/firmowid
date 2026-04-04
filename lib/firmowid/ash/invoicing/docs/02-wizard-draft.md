# Phase 2: WizardDraft Resource (ETS)

## Goal

Create an Ash resource backed by ETS that replaces `CreatorDraftStore` (Cachex).
Typed fields, proper validations per wizard step, ephemeral (dies on restart).

## Files to create

```
lib/firmowid/ash/invoicing/
  wizard_draft.ex
  wizard_draft/
    item.ex              # embedded resource for line items
```

## WizardDraft.Item (embedded resource)

```elixir
defmodule Firmowid.Ash.Invoicing.WizardDraft.Item do
  use Ash.Resource, data_layer: :embedded

  attributes do
    uuid_v7_primary_key :id
    attribute :index, :integer, public?: true
    attribute :name, :string, public?: true, allow_nil?: false
    attribute :quantity, :decimal, public?: true, allow_nil?: false
    attribute :unit, :string, public?: true, default: "szt.", allow_nil?: false
    attribute :unit_price, :decimal, public?: true, allow_nil?: false
    attribute :vat_rate, :string, public?: true, allow_nil?: false
  end

  validations do
    validate {ValidateVatRate, []}
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end
end
```

## WizardDraft resource

```elixir
defmodule Firmowid.Ash.Invoicing.WizardDraft do
  use Ash.Resource,
    domain: Firmowid.Ash.Invoicing,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer]

  ets do
    private? true
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :organization_id, :uuid, allow_nil?: false, public?: true
    attribute :step, :atom,
      constraints: [one_of: [:counterparty, :items, :payment, :preview]],
      default: :counterparty,
      public?: true

    # Step 1 — Counterparty
    attribute :counterparty_id, :uuid, public?: true
    attribute :buyer_type, :atom,
      constraints: [one_of: [:individual, :company]], default: :company, public?: true
    attribute :buyer_id, :string, public?: true
    attribute :buyer_full_name, :string, public?: true
    attribute :buyer_given_name, :string, public?: true
    attribute :buyer_surname, :string, public?: true
    attribute :buyer_pesel, :string, public?: true
    attribute :buyer_display_name, :string, public?: true
    attribute :buyer_address, :string, public?: true
    attribute :buyer_country, :string, public?: true
    attribute :buyer_email, :string, public?: true
    attribute :buyer_phone, :string, public?: true
    attribute :buyer_description, :string, public?: true
    attribute :invoice_type, :atom,
      constraints: [one_of: [:poland, :foreign]], default: :poland, public?: true
    attribute :is_reverse_charge, :boolean, default: false, public?: true
    attribute :currency, :string, public?: true
    attribute :seller_account_number, :string, public?: true

    # Step 2 — Items (embedded)
    attribute :items, {:array, WizardDraft.Item}, public?: true, default: []

    # Step 3 — Payment
    attribute :sale_date, :date, public?: true
    attribute :due_date, :date, public?: true
    attribute :payment_method, :atom,
      constraints: [one_of: ~w[cash card voucher check credit transfer mobile]a],
      public?: true

    timestamps()
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:organization_id]
    end

    update :update_counterparty do
      require_atomic? false

      accept [
        :counterparty_id, :buyer_type, :buyer_id, :buyer_full_name,
        :buyer_given_name, :buyer_surname, :buyer_pesel, :buyer_display_name,
        :buyer_address, :buyer_country, :buyer_email, :buyer_phone,
        :buyer_description, :invoice_type, :is_reverse_charge, :currency,
        :seller_account_number
      ]

      change {ValidateCountryCode, field: :buyer_country}
      change {ClearIrrelevantBuyerFields,
        type_field: :buyer_type,
        company_fields: [:buyer_id, :buyer_full_name],
        individual_fields: [:buyer_pesel, :buyer_given_name, :buyer_surname]}
      change {CastBasedOnInvoiceType, []}
      change set_attribute(:step, :items)

      validate {ValidateTaxId,
        id_field: :buyer_id, country_field: :buyer_country,
        pesel_field: :buyer_pesel, type_field: :buyer_type}
      validate {ValidateNameFields,
        type_field: :buyer_type, full_name_field: :buyer_full_name,
        given_name_field: :buyer_given_name, surname_field: :buyer_surname}
      validate present([:buyer_country, :buyer_address])
    end

    update :update_items do
      require_atomic? false

      accept [:currency, :is_reverse_charge, :items]

      change {NormalizeReverseChargeVatRates, source: :attribute, field: :items}
      change set_attribute(:step, :payment)

      validate present([:currency])
      validate match(:currency, ~r/^[A-Z]{3}$/)
      # validate items not empty — custom validation or validate present([:items])
    end

    update :update_payment do
      require_atomic? false

      accept [:sale_date, :due_date, :payment_method, :seller_account_number]
      argument :due_date_days, :integer

      change {CalculateDueDate, []}
      change set_attribute(:step, :preview)

      validate present([:sale_date, :due_date, :payment_method, :seller_account_number])
      validate string_length(:seller_account_number, min: 10, max: 34)
    end

    # For copy-from-invoice: populate multiple steps at once
    update :populate_from_invoice do
      require_atomic? false

      accept [
        :counterparty_id, :buyer_type, :buyer_id, :buyer_full_name,
        :buyer_given_name, :buyer_surname, :buyer_pesel, :buyer_display_name,
        :buyer_address, :buyer_country, :buyer_email, :buyer_phone,
        :buyer_description, :invoice_type, :is_reverse_charge, :currency,
        :seller_account_number, :items, :sale_date, :due_date, :payment_method
      ]

      # Minimal validation — the source invoice was already valid
      change {ValidateCountryCode, field: :buyer_country}
    end
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end
end

# NOTE on ETS scoping:
# ETS `private? true` means the table is NOT publicly accessible outside the OTP app,
# but ALL processes within the app share it. It is NOT per-LiveView-process scoped.
# Multitenancy via organization_id is required for org isolation, same as Postgres resources.
```

## Code interfaces on domain

```elixir
# In Firmowid.Ash.Invoicing domain
define :create_wizard_draft, resource: WizardDraft, action: :create
define :get_wizard_draft, resource: WizardDraft, args: [:id], action: :read
define :destroy_wizard_draft, resource: WizardDraft, action: :destroy
```

## CreatorDraftStore → WizardDraft mapping

The legacy `CreatorDraftStore` (Cachex) has 5 public functions. Here's how each maps:

| CreatorDraftStore call | Count | WizardDraft equivalent |
|---|---|---|
| `create(org_id)` | 2 | `WizardDraft.create!(%{organization_id: org_id}, tenant: org_id)` |
| `get(org_id, id)` | 1 | `Ash.get!(WizardDraft, id, tenant: org_id)` |
| `put(org_id, id, %{step: :items, data: ...})` | 5 | Step-specific actions: `update_counterparty!`, `update_items!`, `update_payment!`, or `populate_from_invoice!` — no generic "put" |
| `delete(org_id, id)` | 3 | `Ash.destroy!(draft, tenant: org_id)` |
| `exists?(org_id, id)` | 0 | Dead code — don't port |

### partial_copy_changeset — NOT NEEDED

Legacy stores an `Ecto.Changeset` in Cachex to survive `push_patch` during the
copy-from-invoice flow. In the new model: `WizardDraft.populate_from_invoice` returns
`{:error, form}` on validation failure. The LiveView catches the error, assigns the form
with errors, and `push_patch`es to counterparty step. AshPhoenix.Form state lives in
socket assigns — it survives `push_patch` without external storage.

## NormalizeReverseChargeVatRates — dual mode

This change needs to work on both:
- **WizardDraft** `:update_items` — items is an attribute `{:array, WizardDraft.Item}`
- **SalesInvoice** `:create`/`:update` — items is an argument `{:array, :map}` for `manage_relationship`

**Options:**
- `:source` — `:attribute` or `:argument` (where to read/write items)
- `:field` — atom (`:items` or `:sales_invoice_items`)

**Implementation:**
```elixir
def change(changeset, opts, _context) do
  source = opts[:source] || :argument
  field = opts[:field] || :items

  items = case source do
    :argument -> Ash.Changeset.get_argument(changeset, field)
    :attribute -> Ash.Changeset.get_attribute(changeset, field)
  end

  # ... normalize ...

  case source do
    :argument -> Ash.Changeset.set_argument(changeset, field, normalized)
    :attribute -> Ash.Changeset.force_change_attribute(changeset, field, normalized)
  end
end
```

Items from attributes come as structs (`%WizardDraft.Item{}`), items from arguments come
as maps. The normalizer needs to handle both:

```elixir
defp get_vat_rate(%{vat_rate: rate}), do: rate
defp get_vat_rate(%{"vat_rate" => rate}), do: rate

defp set_vat_rate(%{} = item, rate) when is_struct(item), do: %{item | vat_rate: rate}
defp set_vat_rate(%{} = item, rate), do: Map.put(item, access_key(item, :vat_rate), rate)
```

## Confirm flow (generic action on SalesInvoice or domain)

The confirm step reads the WizardDraft and creates a real SalesInvoice:

```elixir
action :confirm_from_draft, :struct do
  constraints instance_of: SalesInvoice
  argument :draft_id, :uuid_v7, allow_nil?: false
  argument :invoice_number, :string  # nil for save-as-draft
  argument :organization, :map, allow_nil?: false  # org data for seller fields

  run fn input, context ->
    opts = Ash.Context.to_opts(context)
    draft = WizardDraft |> Ash.get!(input.arguments.draft_id, opts)
    org = input.arguments.organization

    attrs = %{
      # From draft
      counterparty_id: draft.counterparty_id,
      buyer_type: draft.buyer_type,
      buyer_id: draft.buyer_id,
      # ... all buyer fields ...
      invoice_type: draft.invoice_type,
      is_reverse_charge: draft.is_reverse_charge,
      currency: draft.currency,
      seller_account_number: draft.seller_account_number,
      sale_date: draft.sale_date,
      due_date: draft.due_date,
      payment_method: draft.payment_method,

      # From arguments
      invoice_number: input.arguments.invoice_number,
      issue_date: Date.utc_today(),

      # From organization
      seller_display_name: org.name,
      seller_address: org.address,
      seller_nip: org.nip,

      # Items
      sales_invoice_items: Enum.map(draft.items, &Map.take(&1, [:index, :name, :quantity, :unit, :unit_price, :vat_rate]))
    }

    # Create SalesInvoice — if this fails, draft is preserved
    case Ash.create(SalesInvoice, attrs, opts) do
      {:ok, invoice} ->
        # Destroy draft — if this fails, orphan draft is harmless
        Ash.destroy!(draft, opts)
        {:ok, invoice}

      {:error, error} ->
        {:error, error}
    end
  end
end
```

**Safety:** SalesInvoice creation is attempted first. Only if it succeeds, the draft is
destroyed. If creation fails → draft untouched → user can retry. If draft destroy fails
→ orphan draft → dies on restart.

## Testing

1. Create draft → verify ETS record exists
2. Update counterparty → verify fields set, step advanced to :items
3. Update items → verify embedded items, step advanced to :payment
4. Update payment → verify dates, step advanced to :preview
5. Confirm → verify SalesInvoice in Postgres, draft destroyed
6. Confirm failure → verify draft preserved
7. Copy-from-invoice → verify draft populated with source data
8. Validation errors → verify per-step error messages
