# Phase 6: Rewrite Edit View

## Goal

Replace `edit.ex` to use Ash actions via AshPhoenix.Form. Handles three cases:
draft editing, confirmed invoice editing, and correction invoice creation.

## Current flow

1. Load invoice via Ash `by_id`
2. Check `editable?` — redirect if not
3. Bodyguard permission check
4. Build changeset:
   - Draft → combined step1+step2+step3 changeset
   - Confirmed (not KSeF submitted) → same
   - KSeF submitted → `prepare_correction_invoice_changeset` + combined changeset
5. Form with live PDF preview
6. Save: `SalesInvoices.update_sales_invoice` or `SalesInvoices.create_correction_invoice`

## New flow

1. Load invoice via Ash `by_id` (unchanged)
2. Check `editable?` (unchanged — already on Ash module)
3. Ash policies replace Bodyguard (automatic)
4. Build form:
   - Draft / Confirmed → `AshPhoenix.Form.for_update(invoice, :update)`
   - KSeF submitted → `AshPhoenix.Form.for_create(SalesInvoice, :create_correction, params_from_invoice)`
5. Form with live PDF preview (structure unchanged)
6. Save: Ash `:update` or `:create_correction` via `AshPhoenix.Form.submit`

## Key changes

### mount/1

```elixir
def mount(%{"id" => id}, _session, socket) do
  # Ash policy check replaces Bodyguard
  invoice = SalesInvoice.by_id!(id, scope: scope)

  cond do
    not SalesInvoice.editable?(invoice) ->
      {:ok, socket |> put_flash(:error, not_editable_message(invoice)) |> push_navigate(...)}
    true ->
      {:ok, mount_editable_invoice(socket, invoice)}
  end
end
```

### build_form — draft or confirmed

```elixir
defp build_form(%{ksef_number: nil} = invoice) do
  AshPhoenix.Form.for_update(invoice, :update,
    forms: [
      sales_invoice_items: [
        type: :list,
        resource: SalesInvoiceItem,
        create_action: :create,
        update_action: :update,
        data: invoice.sales_invoice_items
      ]
    ]
  )
end
```

### build_form — KSeF submitted (correction)

```elixir
defp build_form(%{ksef_number: _} = invoice) do
  original = if invoice.ksef_invoice_kind == :kor, do: invoice.corrected_invoice, else: invoice
  latest = SalesInvoice.get_latest_invoice_snapshot(original)

  # Pre-populate correction form from latest snapshot
  params = %{
    "original_invoice_id" => original.id,
    "issue_date" => Date.utc_today(),
    "invoice_number" => SalesInvoice.get_next_number!(Date.utc_today(), series: "FK", scope: scope),
    # Copy all buyer/seller/payment fields from latest snapshot
    "buyer_type" => latest.buyer_type,
    # ... etc ...
    "sales_invoice_items" => Enum.map(latest.sales_invoice_items, &serialize_item/1)
  }

  AshPhoenix.Form.for_create(SalesInvoice, :create_correction,
    params: params,
    forms: [
      sales_invoice_items: [
        type: :list,
        resource: SalesInvoiceItem,
        create_action: :create,
        update_action: :update
      ]
    ]
  )
end
```

### handle_event "validate"

```elixir
def handle_event("validate", %{"form" => params}, socket) do
  form = AshPhoenix.Form.validate(socket.assigns.form, params)

  socket =
    socket
    |> assign(:form, form)
    |> assign_preview_from_form(form)
    |> maybe_auto_fill_correction_reason()
    |> push_event("unsaved-changed", %{value: true})

  {:noreply, socket}
end
```

### handle_event "submit"

```elixir
def handle_event("send_to_ksef", %{"form" => params}, socket) do
  case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
    {:ok, invoice} ->
      maybe_submit_to_ksef(socket, invoice)
    {:error, form} ->
      {:noreply, assign(socket, :form, form)}
  end
end
```

### Preview invoice

The live preview needs to render an invoice from the form state. Currently it uses
`Ecto.Changeset.apply_action(changeset, :update)` to get a struct.

With AshPhoenix.Form, use `AshPhoenix.Form.value(form, :field)` to read field values,
or build a preview map from form params.

Alternative: keep the preview as a plain map built from form values — it doesn't need
to be a real struct.

### Correction reason auto-generation

Keep `CorrectionReason.generate(preview, reference)` — it's a pure function. Feed it
the preview map and the reference invoice. No change needed to the module itself.

## Remove

- All `EctoSalesInvoice` aliases and references
- `SalesInvoices.update_sales_invoice` calls
- `SalesInvoices.create_correction_invoice` calls
- `SalesInvoices.get_next_invoice_number` → `SalesInvoice.get_next_number!`
- `SalesInvoices.get_currency_rate` → `SalesInvoice.get_currency_rate`
- Bodyguard checks
- `Creator.validate_organization_for_invoicing` — move validation to `:create` / `:create_correction` action
  or keep as helper but call from the generic action

## JS hook contracts — must preserve

The edit view has tightly coupled JS hooks that must be preserved exactly:

1. **`ConfirmLeave` hook** — `phx-hook="ConfirmLeave"` on the `<.form>` element.
   Listens for `push_event("unsaved-changed", %{value: true/false})`.
   Blocks navigation when form has unsaved changes.
   - `push_event("unsaved-changed", %{value: true})` — on validate (phx-change)
   - `push_event("unsaved-changed", %{value: false})` — on cancel_edit, save success

2. **`PaperPlane` hook** (in `summary.ex`, not edit) — `phx-hook="PaperPlane"` on
   `#invoice-preview` div. Receives `push_event("paper-plane-fly", %{})` on KSeF
   submission success. Plays animation. Safe — no data coupling.

3. **`copy-to-clipboard`** (in `show.ex`) — `push_event("copy-to-clipboard", %{text: url})`.
   Utility event, no data coupling.

These hook names and event names are contracts with the JS side. Do NOT rename them.

## Testing

1. Edit draft → verify update persists
2. Edit confirmed invoice → verify update
3. Edit KSeF-submitted → verify correction created
4. Correction with auto-generated reason → verify reason text
5. Correction with user-edited reason → verify preserved
6. Bank account selection → verify seller_account_number updated
7. Cancel edit → verify no changes
8. Save as draft (for drafts) → verify saved
