# Phase 5: Rewrite Creator Wizard

## Goal

Replace `creator.ex` to use WizardDraft + AshPhoenix.Form for each step, and
the confirm-from-draft generic action for final creation.

## Current flow (legacy)

1. `mount` → Bodyguard check, load bank_accounts/counterparties/recent_invoices
2. `handle_params` → create or restore `CreatorDraftStore` (Cachex)
3. Step 1: counterparty selection → `SalesInvoice.step1_changeset` → `to_form`
4. Step 2: items → `SalesInvoice.step2_changeset` with `cast_assoc` → `to_form`
5. Step 3: payment → `SalesInvoice.step3_changeset` → `to_form`
6. Step 4: preview → generate number, validate, build preview
7. Confirm → `SalesInvoice.changeset(attrs) |> Repo.insert()`
8. Save as draft → same but without invoice_number

## New flow

1. `mount` → load bank_accounts/counterparties/recent_invoices (unchanged)
2. `handle_params` → create or load WizardDraft (Ash ETS)
3. Step 1: `AshPhoenix.Form.for_update(draft, :update_counterparty)` → `to_form`
4. Step 2: `AshPhoenix.Form.for_update(draft, :update_items)` — nested forms for embedded items
5. Step 3: `AshPhoenix.Form.for_update(draft, :update_payment)` → `to_form`
6. Step 4: preview → read draft, generate number, validate
7. Confirm → `SalesInvoice.confirm_from_draft!(draft_id, invoice_number, org, scope:)`
8. Save as draft → `SalesInvoice.confirm_from_draft!(draft_id, nil, org, scope:)` (no number)

## Key changes in creator.ex

### Remove
- All `CreatorDraftStore` references
- All `serialize_to_creator_draft` / `restore_from_creator_draft`
- All `%SalesInvoice{}` bare struct construction
- All `SalesInvoice.step1_changeset` / `step2_changeset` / `step3_changeset` calls
- All `Ecto.Changeset.apply_action` calls
- `build_invoice_from_data/1`, `build_item_from_data/1`
- `SalesInvoice.changeset(attrs) |> Repo.insert()`
- Bodyguard checks (replaced by Ash policies)
- `apply_vat_rate_from_context` (replaced by NormalizeReverseChargeVatRates change)

### Replace with
- `WizardDraft` Ash resource via code interfaces
- `AshPhoenix.Form` for each step
- `confirm_from_draft` generic action

### mount/1

```elixir
def mount(_params, _session, socket) do
  socket =
    socket
    |> assign(:bank_accounts, Finances.list_bank_accounts!(scope: scope))
    |> assign(:last_counterparties, Counterparty.list_all!(scope: scope))
    |> assign(:last_invoices, SalesInvoice.list_recent!(scope: scope))
    |> assign(:ksef_connected?, Ksef.get_credential() != nil)
    |> assign(:open_counterparty_modal, false)

  {:ok, socket}
end
```

### handle_params — create or load draft

```elixir
case params do
  %{"draft" => draft_id} ->
    # Load existing draft from ETS
    case WizardDraft.get(draft_id) do
      {:ok, draft} -> restore_draft(socket, draft, params)
      {:error, _} -> create_and_redirect(socket)
    end

  %{"skopiuj" => invoice_id} ->
    create_draft_from_copy(socket, invoice_id)

  _ ->
    create_and_redirect(socket)
end
```

### create_and_redirect

```elixir
defp create_and_redirect(socket) do
  draft = WizardDraft.create!(%{organization_id: org_id})
  {:noreply, push_patch(socket, to: draft_url(draft.id, :counterparty), replace: true)}
end
```

### Step 1: counterparty

```elixir
defp maybe_setup_step(socket, :counterparty, _params) do
  draft = socket.assigns.draft
  form = AshPhoenix.Form.for_update(draft, :update_counterparty) |> to_form()

  socket
  |> assign(:counterparty_form, form)
  |> update_counterparty_stream(...)
end

def handle_event("validate_counterparty", %{"wizard_draft" => params}, socket) do
  form =
    socket.assigns.counterparty_form.source
    |> AshPhoenix.Form.validate(params)
    |> to_form()

  {:noreply, assign(socket, :counterparty_form, form)}
end

def handle_event("submit_counterparty", %{"wizard_draft" => params}, socket) do
  case AshPhoenix.Form.submit(socket.assigns.counterparty_form.source, params: params) do
    {:ok, updated_draft} ->
      {:noreply, persist_and_navigate(socket, updated_draft, :items)}
    {:error, form} ->
      {:noreply, assign(socket, :counterparty_form, to_form(form))}
  end
end
```

### Step 1: select_counterparty (from list)

When a user clicks a counterparty from the list, we bypass the form and directly
update the draft:

```elixir
def handle_event("select_counterparty", %{"counterparty_id" => id}, socket) do
  counterparty = Counterparty.get!(id, scope: scope)

  # Build attrs from counterparty
  attrs = %{
    counterparty_id: counterparty.id,
    buyer_type: counterparty.type,
    buyer_id: counterparty.tax_id,
    # ... map all fields ...
    currency: currency_for_country(counterparty.country),
    invoice_type: invoice_type_for_country(counterparty.country),
    is_reverse_charge: reverse_charge_for_id_type?(...)
  }

  updated_draft = WizardDraft.update_counterparty!(socket.assigns.draft, attrs, scope: scope)
  {:noreply, persist_and_navigate(socket, updated_draft, :items)}
end
```

### Step 2: items with nested forms

```elixir
defp maybe_setup_step(socket, :items, _params) do
  draft = socket.assigns.draft
  form =
    AshPhoenix.Form.for_update(draft, :update_items,
      forms: [
        items: [
          type: :list,
          resource: WizardDraft.Item,
          create_action: :create,
          update_action: :update
        ]
      ]
    )
    |> to_form()

  assign(socket, :items_form, form)
end
```

Add/remove items via `_add_items` / `_drop_items` hidden inputs (AshPhoenix convention).

### Step 3: payment

Similar to step 1 — `AshPhoenix.Form.for_update(draft, :update_payment)`.

### Step 4: preview + confirm

```elixir
defp maybe_setup_step(socket, :preview, _params) do
  draft = socket.assigns.draft
  {:ok, org} = Accounts.get_organization(org_id)
  issue_date = Date.utc_today()
  invoice_number = SalesInvoice.get_next_number!(issue_date, scope: scope)

  socket
  |> assign(:organization, org)
  |> assign(:invoice_number, invoice_number)
  |> assign(:preview_draft, draft)
  |> assign(:currency_rate, compute_currency_rate(draft))
end

def handle_event("confirm_invoice", _params, socket) do
  case SalesInvoice.confirm_from_draft(
    socket.assigns.draft.id,
    socket.assigns.invoice_number,
    socket.assigns.organization,
    scope: scope
  ) do
    {:ok, invoice} ->
      {:noreply, push_navigate(socket, to: ~p"/sprzedazowe/#{invoice.id}/podsumowanie")}
    {:error, error} ->
      {:noreply, put_flash(socket, :error, get_error_message(error))}
  end
end

def handle_event("save_as_draft", _params, socket) do
  case SalesInvoice.confirm_from_draft(
    socket.assigns.draft.id,
    nil,  # no invoice number → draft
    socket.assigns.organization,
    scope: scope
  ) do
    {:ok, invoice} ->
      {:noreply, redirect(socket, to: ~p"/sprzedazowe/#{invoice.id}")}
    {:error, error} ->
      {:noreply, put_flash(socket, :error, get_error_message(error))}
  end
end
```

### Copy from invoice

```elixir
defp create_draft_from_copy(socket, invoice_id) do
  source = SalesInvoice.by_id!(invoice_id, scope: scope)
  draft = WizardDraft.create!(%{organization_id: org_id})

  attrs = %{
    # Map all buyer/payment/items from source invoice
    counterparty_id: source.counterparty_id,
    buyer_type: source.buyer_type,
    # ... etc ...
    items: Enum.map(source.sales_invoice_items, &Map.take(&1, [:index, :name, :quantity, :unit, :unit_price, :vat_rate]))
  }

  case WizardDraft.populate_from_invoice(draft, attrs) do
    {:ok, draft} ->
      {:noreply, push_patch(socket, to: draft_url(draft.id, :items), replace: true)}
    {:error, _} ->
      # Partial copy — counterparty data invalid, land on counterparty step
      ...
  end
end
```

## VAT rate context handling

The legacy `apply_vat_rate_from_context` in creator.ex forces VAT rates based on
buyer context (reverse charge, EU B2B, non-EU). In the new flow:

- `NormalizeReverseChargeVatRates` change handles this on WizardDraft `:update_items`
- The LiveView still needs to determine which rates to show in the dropdown UI
- Use `VatRate.available_rates(buyer_country, buyer_id_type)` in the template — this
  is a read-only display concern, NOT a persistence concern

## Testing

### New tests (colocated with WizardDraft, Phase 2)

Step changeset tests from `sales_invoices_test.exs` move here — same user paths,
new implementation:

1. Update counterparty → validates buyer fields, step advances to :items
2. Update counterparty with invalid country → error
3. Update counterparty company → requires buyer_full_name
4. Update counterparty individual → requires given_name + surname
5. Update items → embedded items stored, step advances to :payment
6. Update items with reverse charge → VAT rates normalized to "oo"
7. Update payment → due date calculated, step advances to :preview
8. Update payment missing required fields → error

### Integration tests (Phase 5)

1. Full wizard flow: create draft → counterparty → items → payment → confirm → verify invoice in DB
2. Copy from invoice → verify draft populated, navigate to items step
3. Partial copy (invalid counterparty) → verify lands on counterparty step (AshPhoenix.Form handles state — no Cachex workaround needed)
4. Save as draft → verify invoice without invoice_number
5. Validation errors per step → verify form shows errors
6. Add/remove items → verify nested forms work
7. Select counterparty from list → verify draft updated
8. Select from recent invoice tab → verify draft populated
9. Series selection → verify number updates
10. Number validation warnings → verify display
