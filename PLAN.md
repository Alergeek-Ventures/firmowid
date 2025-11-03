# Resend Inbound Email Handler - Implementation Plan

## Overview

Add `/kosztowe/skrzynka` endpoint and UI for processing invoice attachments received via email. Each organization gets a unique inbound email address (`{org_uuid}@firmowid.pl`) that accepts invoice PDFs and images, automatically processing them into cost invoices.

## Architecture Decisions

### Email-to-Organization Mapping
Use organization UUID as email prefix: `{org_uuid}@firmowid.pl`. This provides:
- Clean UX (dedicated inbox per org)
- Simple parsing (extract UUID before @)
- Configured via Resend code option (not DNS routing)

### Sender Allowlist Strategy
- Empty allowlist rejects all emails (secure by default)
- On org creation: automatically seed with owner's email
- When user becomes admin: add their email to allowlist
- Users can manually add/remove any emails via settings UI
- Rationale: Balance security with usability - admins are trusted by default

### Data Model - No Status Column
Track processing state via nullable fields rather than explicit status enum:
- `processed_at == nil && failure_reason == nil` → pending
- `processed_at != nil && failure_reason == nil` → success  
- `failure_reason != nil` → failed

This simplifies state management and allows direct inference from Oban job state if needed.

### Failure Tracking
`failure_reason` enum with three values:
- `:unexpected_sender` - sender not in allowlist
- `:no_attachment` - email had no PDF/image attachments
- `:processing_failed` - extraction or storage error

This provides actionable failure information for users.

### Webhook Verification
Use Svix standard (industry standard for webhooks):
- Headers: `svix-id`, `svix-timestamp`, `svix-signature`
- Manual HMAC-SHA256 verification (avoid new dependency)
- 5-minute timestamp tolerance to prevent replay attacks

### Reprocessing Flow
Failed emails can be reprocessed from UI with one-click "Reprocess & Allowlist":
- Atomically adds sender to allowlist
- Re-enqueues worker with bypass flag
- Resets failure state for clean retry

### External API Boundary (Rule 8)
Define `Firmowid.Resend.Client` behaviour for testability:
- Production: `ReqClient` using Req library
- Test: `ClientMock` using Mox
- Callbacks: `get_email/1`, `list_attachments/1`, `download_attachment/1`

## Task List

### Phase 1: Database Schema

- [ ] 1.1: Create migration for `organizations.allowed_sender_emails` (text array, default `[]`)
- [ ] 1.2: Create migration for `inbound_emails` table:
  - Columns: `id`, `organization_id`, `resend_email_id` (unique), `sender_email`, `subject`, `body`, `received_at`, `processed_at`, `failure_reason`, `cost_invoice_id`
  - Indexes: `organization_id`, `resend_email_id` (unique), `cost_invoice_id`
- [ ] 1.3: Create `Firmowid.CostInvoices.InboundEmail` schema with Ecto enum for `failure_reason` (`:unexpected_sender`, `:no_attachment`, `:processing_failed`)
- [ ] 1.4: Update `Organization` schema to add `allowed_sender_emails` field with default `[]`

### Phase 2: Allowlist Management

- [ ] 2.1: Add `Accounts.add_email_to_org_allowlist(org_id, email)` - appends if not present
- [ ] 2.2: Add `Accounts.remove_email_from_org_allowlist(org_id, email)`
- [ ] 2.3: Update `Accounts.create_organization/1` to seed allowlist with owner email
- [ ] 2.4: Find user role assignment logic, add hook to call `add_email_to_org_allowlist/2` when user becomes admin
- [ ] 2.5: Create data migration to backfill existing orgs with admin emails

### Phase 3: Resend API Client (External Boundary)

- [ ] 3.1: Define `Firmowid.Resend.Client` behaviour with three callbacks:
  - `get_email(email_id)` → `{:ok, %{html: ..., text: ...}}` or `{:error, term}`
  - `list_attachments(email_id)` → `{:ok, [%{filename: ..., content_type: ..., download_url: ...}]}` or `{:error, term}`
  - `download_attachment(url)` → `{:ok, binary}` or `{:error, term}`
- [ ] 3.2: Implement `Firmowid.Resend.ReqClient`:
  - `get_email/1` calls `GET https://api.resend.com/emails/receiving/{email_id}` with `Authorization: Bearer {api_key}`
  - `list_attachments/1` calls `GET https://api.resend.com/emails/receiving/{email_id}/attachments`
  - `download_attachment/1` calls `GET {download_url}` (presigned, no auth)
- [ ] 3.3: Add config to `runtime.exs`: `:resend_api_key`, `:resend_webhook_secret` from env vars
- [ ] 3.4: Add config to `config.exs`: `:resend_client` → `Firmowid.Resend.ReqClient` (prod/dev)

### Phase 4: Webhook Verification

- [ ] 4.1: Create `FirmowidWeb.WebhookAuth` module with `verify_svix_webhook_signature/2` plug
- [ ] 4.2: Extract headers: `svix-id`, `svix-timestamp`, `svix-signature`
- [ ] 4.3: Construct signed content: `"#{svix_id}.#{svix_timestamp}.#{raw_body}"`
- [ ] 4.4: Compute expected signature: base64(HMAC-SHA256(webhook_secret, signed_content))
- [ ] 4.5: Compare signatures (constant-time comparison)
- [ ] 4.6: Validate timestamp (reject if older than 5 minutes)
- [ ] 4.7: On failure: halt with 401 Unauthorized, log attempt

### Phase 5: Webhook Handler

- [ ] 5.1: Add `:webhook` pipeline in router (accepts JSON, uses `verify_svix_webhook_signature`)
- [ ] 5.2: Add `POST /kosztowe/skrzynka` route in webhook scope
- [ ] 5.3: Create `FirmowidWeb.ResendInboundController.handle_webhook/2`
- [ ] 5.4: Parse payload: extract `email_id`, `to` array, `from`, `subject` from `event.data`
- [ ] 5.5: Extract org_id from recipient email (parse UUID before `@`)
- [ ] 5.6: Validate org exists with `Accounts.get_organization(org_id)`
- [ ] 5.7: Create `inbound_emails` record with `resend_email_id`, `sender_email`, `subject`, `received_at`, `organization_id`
- [ ] 5.8: Enqueue `InboundEmailWorker.new(%{inbound_email_id: id, organization_id: org_id})`
- [ ] 5.9: Return `json(conn, %{status: "ok"})`
- [ ] 5.10: Handle idempotency: catch unique constraint on `resend_email_id`, return 200 OK

### Phase 6: Email Processing Worker

- [ ] 6.1: Create `Firmowid.CostInvoices.InboundEmailWorker` (queue: `:inbound_emails`, max_attempts: 3)
- [ ] 6.2: Accept args: `%{inbound_email_id, organization_id, bypass_sender_check: false}`
- [ ] 6.3: Set `Repo.put_org_id(organization_id)`
- [ ] 6.4: Fetch `inbound_email` and `organization` records
- [ ] 6.5: Call `Resend.Client.get_email(resend_email_id)` to fetch body, update record
- [ ] 6.6: Validate sender (unless bypass):
  - If allowlist empty OR sender not in list: set `failure_reason: :unexpected_sender`, broadcast, return `:ok`
- [ ] 6.7: Call `Resend.Client.list_attachments(resend_email_id)`
- [ ] 6.8: If no attachments: set `failure_reason: :no_attachment`, broadcast, return `:ok`
- [ ] 6.9: Filter attachments by `content_type` (keep `application/pdf` and `image/*`)
- [ ] 6.10: For each attachment:
  - Download via `Resend.Client.download_attachment(download_url)`
  - Save to temp file using `Briefly.create/0`
  - Call `CostInvoices.upload_cost_invoice(path, content_type, filename)`
- [ ] 6.11: On success: update with `processed_at: DateTime.utc_now()`, link first `cost_invoice_id`
- [ ] 6.12: On error: set `failure_reason: :processing_failed`, log with `Logger.error/1` and Sentry
- [ ] 6.13: Use `Ecto.Multi` for transactional inbound_email update (Rule 4)
- [ ] 6.14: Broadcast update via PubSub

### Phase 7: Context Functions

- [ ] 7.1: Create `Firmowid.CostInvoices.InboundEmails` module (or extend main context)
- [ ] 7.2: Add `list_inbound_emails(date_from, date_to)` - filter by `received_at`, order desc, preload `:cost_invoice`
- [ ] 7.3: Add `get_inbound_email!(id)` with preloads
- [ ] 7.4: Add `create_inbound_email(attrs)`
- [ ] 7.5: Add `update_inbound_email(inbound_email, attrs)`
- [ ] 7.6: Add `reprocess_inbound_email(id)`:
  - Use `Ecto.Multi` to add sender to allowlist and enqueue worker with `bypass_sender_check: true`
  - Reset `processed_at`, `failure_reason`, `cost_invoice_id` to nil
- [ ] 7.7: Add `subscribe_inbound_emails(org_id)` for PubSub
- [ ] 7.8: Add `broadcast_inbound_email_updated(inbound_email)` for PubSub

### Phase 8: LiveView Interface

- [ ] 8.1: Create `FirmowidWeb.InboundEmailLive.Index` LiveView
- [ ] 8.2: Add `GET /kosztowe/skrzynka` route in `:admin` live_session
- [ ] 8.3: Mount: subscribe to PubSub, stream initial records with `stream/3`
- [ ] 8.4: Add status helper:
  - `pending`: `processed_at == nil && failure_reason == nil`
  - `success`: `processed_at != nil && failure_reason == nil`
  - `failed`: `failure_reason != nil`
- [ ] 8.5: Template: table with columns - received_at, sender_email, subject, status badge, invoice link, actions
- [ ] 8.6: Status badge: color-coded (green success, yellow pending, red failed)
- [ ] 8.7: Action column: "Reprocess & Allowlist" button (phx-click) for failed emails only
- [ ] 8.8: Handle `reprocess` event: call context function, show toast
- [ ] 8.9: Handle PubSub broadcast: update stream with `stream_insert/3`
- [ ] 8.10: Add filter controls: date range pickers, status dropdown
- [ ] 8.11: Click subject: show modal with email body
- [ ] 8.12: Click invoice link: navigate to `/kosztowe/{id}`

### Phase 9: Organization Settings UI

- [ ] 9.1: Update `FirmowidWeb.SettingsLive.Index` to add "Inbound Email" section
- [ ] 9.2: Display org inbound address: `{organization.id}@firmowid.pl` with copy button
- [ ] 9.3: Show allowlist as list items with badge for admin emails
- [ ] 9.4: Add form: email input + "Add to Allowlist" button (validate email format)
- [ ] 9.5: Handle `add_sender` event: call `Accounts.add_email_to_org_allowlist/2`, toast
- [ ] 9.6: Handle `remove_sender` event: call `Accounts.remove_email_from_org_allowlist/2`, toast
- [ ] 9.7: Disable removal for admin emails (show tooltip)

### Phase 10: Logging and Error Handling

- [ ] 10.1: Add structured logging per Rule 5:
  - Info: "Inbound email received" (org_id, sender, resend_email_id)
  - Debug: "Processing N attachments" (filenames)
  - Warning: "Sender not in allowlist" (sender)
  - Error: "Processing failed" (reason, resend_email_id)
- [ ] 10.2: Ensure Worker rescues exceptions, sets `failure_reason: :processing_failed`
- [ ] 10.3: Log invalid org_id in webhook controller

### Phase 11: Integration and Polish

- [ ] 11.1: Add navigation link to `/kosztowe/skrzynka` in main menu/sidebar
- [ ] 11.2: Test webhook with Resend test events
- [ ] 11.3: Test full flow: send email → verify webhook → check worker → view in UI
- [ ] 11.4: Test reprocessing flow with failed emails
- [ ] 11.5: Test allowlist management in settings
- [ ] 11.6: Run `mix format` on all new files
- [ ] 11.7: Update documentation if needed

## Technical Notes

### Webhook Payload Structure
```json
{
  "type": "email.received",
  "data": {
    "email_id": "4ef9a417-02e9-4d39-ad75-9611e0fcc33c",
    "from": "sender@example.com",
    "to": ["org-uuid@firmowid.pl"],
    "subject": "Invoice from vendor",
    "created_at": "2024-01-01T12:00:00Z"
  }
}
```

### Resend API Endpoints
- Get email: `GET /emails/receiving/{email_id}`
- List attachments: `GET /emails/receiving/{email_id}/attachments`
- Download URL: Returned in attachment list, presigned (1 hour validity)

### Svix Signature Verification
```
signed_content = "#{svix_id}.#{svix_timestamp}.#{raw_body}"
expected_signature = Base.encode64(:crypto.mac(:hmac, :sha256, webhook_secret, signed_content))
```

### Oban Queue Configuration
Add to `lib/firmowid/oban.ex`:
```elixir
queues: [
  # existing queues...
  inbound_emails: 10
]
```

## Dependencies

- `req` - Already available, used for HTTP requests
- `briefly` - Already available, used for temp files
- No new dependencies required

## Configuration Required

Add to `.env` or deployment config:
```bash
RESEND_API_KEY=re_xxxxx
RESEND_WEBHOOK_SECRET=whsec_xxxxx
```

Configure in Resend dashboard:
- Add inbound route (code option)
- For each organization: add `{org_uuid}@firmowid.pl` → webhook URL
- Webhook URL: `https://your-domain.com/kosztowe/skrzynka`

## Rollout Notes

1. Deploy database migrations first
2. Run backfill migration for existing orgs
3. Deploy application code
4. Configure Resend inbound routing
5. Test with single organization before rollout
6. Monitor Oban queue and error rates
