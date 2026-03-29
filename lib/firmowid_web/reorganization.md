# FirmowidWeb Frontend Reorganization Plan

## Goal

Reorganize `lib/firmowid_web/` from a horizontal "by type" layout (components/,
live/, controllers/) into a vertical "by feature" layout with mandatory
subfolders. Enforce module-path consistency. Set the standard for the project
going forward.

## Hard Rules

1. **Directory path = module namespace, always.** `FirmowidWeb.X.Y.Z` lives at
   `lib/firmowid_web/x/y/z.ex`. No exceptions. Enforce with `credo_naming`.
2. **Every feature has subfolders:** `views/`, `components/`, `controllers/`,
   `utilities/`. Not all need files from day one, but the structure is always
   present.
3. **Drop type suffixes from module names.** The folder signals the type.
   No `Live`, `Controller`, `Component`, `Html` in names.
4. **Enforce folder-type constraints with a custom Credo check:**
   - `use FirmowidWeb, :live_view` only in `views/`
   - `use FirmowidWeb, :live_component` and `use FirmowidWeb, :html` only in `components/`
   - `use FirmowidWeb, :controller` only in `controllers/`
   - Pure Elixir (no Phoenix macros) in `utilities/`
5. **Features can nest.** Invoicing contains cost_invoices and sales_invoices.
   Dependency direction forms a DAG — children depend on parent's components,
   never the reverse, never cross-sibling.

## Current State (Before)

87 of 109 files have module-path drift. The Phoenix scaffold convention
intentionally places files in `live/`, `controllers/`, `components/` directories
that are NOT reflected in module names. Feature code is split across multiple
top-level directories.

```
lib/firmowid_web/           # CURRENT — horizontal "by type"
├── components/             # Mix of shared + feature-specific
│   ├── core_components.ex  # FirmowidWeb.CoreComponents
│   ├── billing_components.ex
│   ├── icons.ex
│   ├── landing.ex
│   ├── layouts.ex
│   ├── layouts/
│   ├── hours_record/
│   ├── invoicing/          # 7 files
│   ├── sales_invoices/
│   └── timetracker/
├── controllers/            # 24 files, flat, mixed features
├── helpers/
├── live/                   # 45 modules across 14 subdirs
│   ├── hooks/
│   ├── invoicing_live/
│   ├── sales_invoices_live/
│   ├── cost_invoice_live/
│   ├── timetracker_live/
│   ├── hours_record_live/
│   ├── management_live/
│   ├── settings_live/
│   ├── bank_sync_live/
│   ├── analysis_live/
│   ├── user_live/
│   ├── feedback_live/
│   ├── organization_invites_live/
│   └── ... (standalone files)
├── plugs/
├── router.ex
├── endpoint.ex
├── user_auth.ex
├── flags.ex
├── telemetry.ex
├── gettext.ex
└── cache_body_reader.ex
```

## Target State (After)

```
lib/firmowid_web/
├── firmowid_web.ex                     # FirmowidWeb (macro hub — root module, only exception to path rule)
│
├── core/
│   ├── endpoint.ex                     # FirmowidWeb.Core.Endpoint
│   ├── router.ex                       # FirmowidWeb.Core.Router
│   ├── telemetry.ex                    # FirmowidWeb.Core.Telemetry
│   ├── gettext.ex                      # FirmowidWeb.Core.Gettext
│   ├── cache_body_reader.ex            # FirmowidWeb.Core.CacheBodyReader
│   └── toast.ex                        # FirmowidWeb.Core.Toast (extracted from firmowid_web.ex)
│
├── infrastructure/
│   ├── user_auth.ex                    # FirmowidWeb.Infrastructure.UserAuth
│   ├── user_auth_test.exs              # FirmowidWeb.Infrastructure.UserAuthTest
│   ├── flags.ex                        # FirmowidWeb.Infrastructure.Flags
│   ├── layouts.ex                      # FirmowidWeb.Infrastructure.Layouts
│   ├── layouts/                        # embed_templates "layouts/*" target (adjacent to layouts.ex)
│   │   ├── app.html.heex
│   │   └── root.html.heex
│   ├── plugs/
│   │   ├── analytics_dashboard_guard.ex    # FirmowidWeb.Infrastructure.Plugs.AnalyticsDashboardGuard
│   │   ├── filtered_request_tracker.ex     # FirmowidWeb.Infrastructure.Plugs.FilteredRequestTracker
│   │   ├── redirect_trailing.ex            # FirmowidWeb.Infrastructure.Plugs.RedirectTrailing
│   │   └── webhook_auth.ex                 # FirmowidWeb.Infrastructure.Plugs.WebhookAuth
│   ├── hooks/
│   │   ├── current_path.ex                 # FirmowidWeb.Infrastructure.Hooks.CurrentPath
│   │   └── timezone.ex                     # FirmowidWeb.Infrastructure.Hooks.Timezone
│   ├── controllers/
│   │   ├── health.ex                       # FirmowidWeb.Infrastructure.Controllers.Health
│   │   ├── health_test.exs                 # FirmowidWeb.Infrastructure.Controllers.HealthTest
│   │   ├── fallback.ex                     # FirmowidWeb.Infrastructure.Controllers.Fallback
│   │   └── file_download.ex                # FirmowidWeb.Infrastructure.Controllers.FileDownload
│   ├── components/
│   │   ├── error_html.ex                   # FirmowidWeb.Infrastructure.Components.ErrorHtml
│   │   ├── error_html_test.exs             # FirmowidWeb.Infrastructure.Components.ErrorHtmlTest
│   │   ├── error_json.ex                   # FirmowidWeb.Infrastructure.Components.ErrorJson
│   │   ├── error_json_test.exs             # FirmowidWeb.Infrastructure.Components.ErrorJsonTest
│   │   └── changeset_json.ex               # FirmowidWeb.Infrastructure.Components.ChangesetJson
│   └── utilities/
│       ├── time_formatter.ex               # FirmowidWeb.Infrastructure.Utilities.TimeFormatter
│       └── pdf_helpers.ex                  # FirmowidWeb.Infrastructure.Utilities.PdfHelpers
│
├── design_system/
│   ├── components/
│   │   └── core_components.ex              # FirmowidWeb.DesignSystem.Components.CoreComponents
│   ├── views/                              # (empty — future: storybook/preview)
│   ├── controllers/                        # (empty)
│   └── utilities/                          # (empty — future: class helpers, theme utils)
│
├── invoicing/
│   ├── views/
│   │   ├── index.ex                        # FirmowidWeb.Invoicing.Views.Index
│   │   ├── index.html.heex
│   │   └── index_test.exs
│   ├── components/
│   │   ├── entries_table.ex                # FirmowidWeb.Invoicing.Components.EntriesTable
│   │   ├── search_overlay.ex               # FirmowidWeb.Invoicing.Components.SearchOverlay
│   │   ├── month_closed_zero_state.ex      # FirmowidWeb.Invoicing.Components.MonthClosedZeroState
│   │   ├── assistant.ex                    # FirmowidWeb.Invoicing.Components.Assistant
│   │   ├── invoice_details.ex              # FirmowidWeb.Invoicing.Components.InvoiceDetails
│   │   ├── invoice_timeline.ex             # FirmowidWeb.Invoicing.Components.InvoiceTimeline
│   │   ├── bank_transfer_modal.ex          # FirmowidWeb.Invoicing.Components.BankTransferModal
│   │   ├── download_modal.ex               # FirmowidWeb.Invoicing.Components.DownloadModal
│   │   ├── cost_invoice_details.ex         # FirmowidWeb.Invoicing.Components.CostInvoiceDetails
│   │   └── sales_invoice_details.ex        # FirmowidWeb.Invoicing.Components.SalesInvoiceDetails
│   ├── controllers/                        # (empty)
│   ├── utilities/
│   │   └── transaction_group.ex            # FirmowidWeb.Invoicing.Utilities.TransactionGroup
│   │
│   ├── cost_invoices/
│   │   ├── views/
│   │   │   ├── inbox.ex                    # FirmowidWeb.Invoicing.CostInvoices.Views.Inbox
│   │   │   └── show.ex                     # FirmowidWeb.Invoicing.CostInvoices.Views.Show
│   │   ├── components/
│   │   │   └── assistant.ex                # FirmowidWeb.Invoicing.CostInvoices.Components.Assistant
│   │   ├── controllers/
│   │   │   ├── api.ex                      # FirmowidWeb.Invoicing.CostInvoices.Controllers.Api
│   │   │   ├── api_test.exs                # FirmowidWeb.Invoicing.CostInvoices.Controllers.ApiTest
│   │   │   └── inbound.ex                  # FirmowidWeb.Invoicing.CostInvoices.Controllers.Inbound
│   │   └── utilities/
│   │
│   └── sales_invoices/
│       ├── views/
│       │   ├── creator.ex                  # FirmowidWeb.Invoicing.SalesInvoices.Views.Creator
│       │   ├── templates/                  # embed_templates "templates/creator_*" target
│       │   │   ├── creator_counterparty.html.heex
│       │   │   ├── creator_items.html.heex
│       │   │   ├── creator_payment.html.heex
│       │   │   └── creator_preview.html.heex
│       │   ├── edit.ex                     # FirmowidWeb.Invoicing.SalesInvoices.Views.Edit
│       │   ├── edit.html.heex
│       │   ├── show.ex                     # FirmowidWeb.Invoicing.SalesInvoices.Views.Show
│       │   ├── summary.ex                  # FirmowidWeb.Invoicing.SalesInvoices.Views.Summary
│       │   └── summary_test.exs
│       ├── components/
│       │   ├── assistant.ex                # FirmowidWeb.Invoicing.SalesInvoices.Components.Assistant
│       │   ├── invoice_items.ex            # FirmowidWeb.Invoicing.SalesInvoices.Components.InvoiceItems
│       │   ├── invoice_payment.ex          # FirmowidWeb.Invoicing.SalesInvoices.Components.InvoicePayment
│       │   ├── template.ex                 # FirmowidWeb.Invoicing.SalesInvoices.Components.Template
│       │   ├── pdf.ex                      # FirmowidWeb.Invoicing.SalesInvoices.Components.Pdf
│       │   ├── shared_page.ex              # FirmowidWeb.Invoicing.SalesInvoices.Components.SharedPage
│       │   └── shared_page/
│       │       └── templates/              # embed_templates "templates/*" target
│       │           ├── show.html.heex
│       │           ├── error.html.heex
│       │           └── not_found.html.heex
│       ├── controllers/
│       │   ├── pdf.ex                      # FirmowidWeb.Invoicing.SalesInvoices.Controllers.Pdf
│       │   └── shared.ex                   # FirmowidWeb.Invoicing.SalesInvoices.Controllers.Shared
│       └── utilities/
│
├── timetracker/
│   ├── views/
│   │   ├── index.ex                        # FirmowidWeb.Timetracker.Views.Index
│   │   ├── index.html.heex
│   │   └── index_test.exs
│   ├── components/
│   │   ├── session.ex                      # FirmowidWeb.Timetracker.Components.Session
│   │   └── overlap.ex                      # FirmowidWeb.Timetracker.Components.Overlap
│   ├── controllers/
│   │   └── csv.ex                          # FirmowidWeb.Timetracker.Controllers.Csv
│   └── utilities/
│       ├── session_form.ex                 # FirmowidWeb.Timetracker.Utilities.SessionForm
│       └── grouped_session_form.ex         # FirmowidWeb.Timetracker.Utilities.GroupedSessionForm
│
├── hours_record/
│   ├── views/
│   │   ├── index.ex                        # FirmowidWeb.HoursRecord.Views.Index
│   │   └── index.html.heex
│   ├── components/
│   │   ├── upload_form.ex                  # FirmowidWeb.HoursRecord.Components.UploadForm
│   │   ├── pdf_template.ex                 # FirmowidWeb.HoursRecord.Components.PdfTemplate
│   │   └── record_html.ex                  # FirmowidWeb.HoursRecord.Components.RecordHtml
│   ├── controllers/
│   │   └── record.ex                       # FirmowidWeb.HoursRecord.Controllers.Record
│   └── utilities/
│
├── management/
│   ├── views/
│   │   ├── clients.ex                      # FirmowidWeb.Management.Views.Clients
│   │   ├── employee.ex                     # FirmowidWeb.Management.Views.Employee
│   │   ├── employee.html.heex
│   │   ├── employees.ex                    # FirmowidWeb.Management.Views.Employees
│   │   ├── employees.html.heex
│   │   ├── project.ex                      # FirmowidWeb.Management.Views.Project
│   │   ├── project.html.heex
│   │   ├── project_form.ex                 # FirmowidWeb.Management.Views.ProjectForm
│   │   ├── project_form.html.heex
│   │   ├── projects.ex                     # FirmowidWeb.Management.Views.Projects
│   │   └── projects.html.heex
│   ├── components/
│   ├── controllers/
│   └── utilities/
│
├── settings/
│   ├── views/
│   │   ├── index.ex                        # FirmowidWeb.Settings.Views.Index
│   │   └── index.html.heex
│   ├── components/
│   │   └── edit_button.ex                  # FirmowidWeb.Settings.Components.EditButton
│   ├── controllers/
│   └── utilities/
│
├── bank_sync/
│   ├── views/
│   │   ├── create.ex                       # FirmowidWeb.BankSync.Views.Create
│   │   ├── create.html.heex
│   │   └── create_test.exs
│   ├── components/
│   ├── controllers/
│   └── utilities/
│
├── analysis/
│   ├── views/
│   │   ├── dashboard.ex                    # FirmowidWeb.Analysis.Views.Dashboard
│   │   └── dashboard.html.heex
│   ├── components/
│   │   └── entries_table.ex                # FirmowidWeb.Analysis.Components.EntriesTable
│   ├── controllers/
│   └── utilities/
│
├── auth/
│   ├── views/
│   │   ├── login.ex                        # FirmowidWeb.Auth.Views.Login
│   │   ├── login_test.exs
│   │   ├── registration.ex                 # FirmowidWeb.Auth.Views.Registration
│   │   ├── registration_test.exs
│   │   ├── forgot_password.ex              # FirmowidWeb.Auth.Views.ForgotPassword
│   │   ├── forgot_password_test.exs
│   │   ├── reset_password.ex               # FirmowidWeb.Auth.Views.ResetPassword
│   │   ├── reset_password_test.exs
│   │   ├── confirmation.ex                 # FirmowidWeb.Auth.Views.Confirmation
│   │   ├── confirmation_test.exs
│   │   ├── confirmation_instructions.ex    # FirmowidWeb.Auth.Views.ConfirmationInstructions
│   │   ├── confirmation_instructions_test.exs
│   │   ├── settings.ex                     # FirmowidWeb.Auth.Views.Settings
│   │   └── settings_test.exs
│   ├── components/
│   ├── controllers/
│   │   ├── session.ex                      # FirmowidWeb.Auth.Controllers.Session
│   │   ├── session_api.ex                  # FirmowidWeb.Auth.Controllers.SessionApi
│   │   ├── session_api_test.exs            # FirmowidWeb.Auth.Controllers.SessionApiTest
│   │   └── google.ex                       # FirmowidWeb.Auth.Controllers.Google
│   └── utilities/
│
├── landing/
│   ├── views/
│   │   ├── index.ex                        # FirmowidWeb.Landing.Views.Index
│   │   ├── index.html.heex
│   │   └── index_test.exs
│   ├── components/
│   │   └── landing.ex                      # FirmowidWeb.Landing.Components.Landing
│   ├── controllers/
│   └── utilities/
│
├── organization/
│   ├── views/
│   │   └── index.ex                        # FirmowidWeb.Organization.Views.Index
│   ├── components/
│   ├── controllers/
│   ├── utilities/
│   └── invites/
│       ├── views/
│       │   ├── index.ex                    # FirmowidWeb.Organization.Invites.Views.Index
│       │   └── index.html.heex
│       ├── components/
│       ├── controllers/
│       └── utilities/
│
├── billing/
│   ├── views/
│   ├── components/
│   │   └── billing.ex                      # FirmowidWeb.Billing.Components.Billing
│   ├── controllers/
│   └── utilities/
│
├── feedback/
│   ├── views/
│   ├── components/
│   │   └── form.ex                         # FirmowidWeb.Feedback.Components.Form
│   ├── controllers/
│   └── utilities/
│
└── development/
    ├── views/
    │   ├── index.ex                        # FirmowidWeb.Development.Views.Index
    │   └── index.html.heex
    ├── components/
    ├── controllers/
    └── utilities/
```

## Complete Rename Map

Every module rename. Old name -> new name.

### Core

| Old Module | New Module | Old Path | New Path |
|---|---|---|---|
| `FirmowidWeb.Endpoint` | `FirmowidWeb.Core.Endpoint` | `endpoint.ex` | `core/endpoint.ex` |
| `FirmowidWeb.Router` | `FirmowidWeb.Core.Router` | `router.ex` | `core/router.ex` |
| `FirmowidWeb.Telemetry` | `FirmowidWeb.Core.Telemetry` | `telemetry.ex` | `core/telemetry.ex` |
| `FirmowidWeb.Gettext` | `FirmowidWeb.Core.Gettext` | `gettext.ex` | `core/gettext.ex` |
| `FirmowidWeb.CacheBodyReader` | `FirmowidWeb.Core.CacheBodyReader` | `cache_body_reader.ex` | `core/cache_body_reader.ex` |
| *(new)* | `FirmowidWeb.Core.Toast` | *(extracted from firmowid_web.ex)* | `core/toast.ex` |

### Infrastructure

| Old Module | New Module | Old Path | New Path |
|---|---|---|---|
| `FirmowidWeb.UserAuth` | `FirmowidWeb.Infrastructure.UserAuth` | `user_auth.ex` | `infrastructure/user_auth.ex` |
| `FirmowidWeb.UserAuthTest` | `FirmowidWeb.Infrastructure.UserAuthTest` | `user_auth_test.exs` | `infrastructure/user_auth_test.exs` |
| `FirmowidWeb.Flags` | `FirmowidWeb.Infrastructure.Flags` | `flags.ex` | `infrastructure/flags.ex` |
| `FirmowidWeb.Layouts` | `FirmowidWeb.Infrastructure.Layouts` | `components/layouts.ex` | `infrastructure/layouts.ex` |
| `FirmowidWeb.Plugs.AnalyticsDashboardGuard` | `FirmowidWeb.Infrastructure.Plugs.AnalyticsDashboardGuard` | `plugs/analytics_dashboard_guard.ex` | `infrastructure/plugs/analytics_dashboard_guard.ex` |
| `FirmowidWeb.Plugs.FilteredRequestTracker` | `FirmowidWeb.Infrastructure.Plugs.FilteredRequestTracker` | `plugs/filtered_request_tracker.ex` | `infrastructure/plugs/filtered_request_tracker.ex` |
| `FirmowidWeb.Plugs.RedirectTrailing` | `FirmowidWeb.Infrastructure.Plugs.RedirectTrailing` | `plugs/redirect_trailing.ex` | `infrastructure/plugs/redirect_trailing.ex` |
| `FirmowidWeb.Plugs.WebhookAuth` | `FirmowidWeb.Infrastructure.Plugs.WebhookAuth` | `plugs/webhook_auth.ex` | `infrastructure/plugs/webhook_auth.ex` |
| `FirmowidWeb.Live.Hooks.CurrentPath` | `FirmowidWeb.Infrastructure.Hooks.CurrentPath` | `live/hooks/current_path.ex` | `infrastructure/hooks/current_path.ex` |
| `FirmowidWeb.Live.Hooks.Timezone` | `FirmowidWeb.Infrastructure.Hooks.Timezone` | `live/hooks/timezone.ex` | `infrastructure/hooks/timezone.ex` |
| `FirmowidWeb.HealthController` | `FirmowidWeb.Infrastructure.Controllers.Health` | `controllers/health_controller.ex` | `infrastructure/controllers/health.ex` |
| `FirmowidWeb.HealthControllerTest` | `FirmowidWeb.Infrastructure.Controllers.HealthTest` | `controllers/health_controller_test.exs` | `infrastructure/controllers/health_test.exs` |
| `FirmowidWeb.FallbackController` | `FirmowidWeb.Infrastructure.Controllers.Fallback` | `controllers/fallback_controller.ex` | `infrastructure/controllers/fallback.ex` |
| `FirmowidWeb.FileController` | `FirmowidWeb.Infrastructure.Controllers.FileDownload` | `controllers/file_controller.ex` | `infrastructure/controllers/file_download.ex` |
| `FirmowidWeb.ErrorHTML` | `FirmowidWeb.Infrastructure.Components.ErrorHtml` | `controllers/error_html.ex` | `infrastructure/components/error_html.ex` |
| `FirmowidWeb.ErrorHTMLTest` | `FirmowidWeb.Infrastructure.Components.ErrorHtmlTest` | `controllers/error_html_test.exs` | `infrastructure/components/error_html_test.exs` |
| `FirmowidWeb.ErrorJSON` | `FirmowidWeb.Infrastructure.Components.ErrorJson` | `controllers/error_json.ex` | `infrastructure/components/error_json.ex` |
| `FirmowidWeb.ErrorJSONTest` | `FirmowidWeb.Infrastructure.Components.ErrorJsonTest` | `controllers/error_json_test.exs` | `infrastructure/components/error_json_test.exs` |
| `FirmowidWeb.ChangesetJSON` | `FirmowidWeb.Infrastructure.Components.ChangesetJson` | `controllers/changeset_json.ex` | `infrastructure/components/changeset_json.ex` |
| `FirmowidWeb.Helpers.TimeFormatter` | `FirmowidWeb.Infrastructure.Utilities.TimeFormatter` | `helpers/time_formatter.ex` | `infrastructure/utilities/time_formatter.ex` |
| `FirmowidWeb.PdfHelpers` | `FirmowidWeb.Infrastructure.Utilities.PdfHelpers` | `helpers/pdf_helpers.ex` | `infrastructure/utilities/pdf_helpers.ex` |

### Design System

| Old Module | New Module | Old Path | New Path |
|---|---|---|---|
| `FirmowidWeb.CoreComponents` | `FirmowidWeb.DesignSystem.Components.CoreComponents` | `components/core_components.ex` | `design_system/components/core_components.ex` |
| `FirmowidWeb.Icons` | *(DELETED)* | `components/icons.ex` | *(deleted — edit_icon replaced with Lucideicons.square_pen)* |

### Invoicing (parent feature)

| Old Module | New Module | Old Path | New Path |
|---|---|---|---|
| `FirmowidWeb.InvoicingLive.Index` | `FirmowidWeb.Invoicing.Views.Index` | `live/invoicing_live/index.ex` | `invoicing/views/index.ex` |
| `FirmowidWeb.InvoicingLiveTest` | `FirmowidWeb.Invoicing.Views.IndexTest` | `live/invoicing_live/index_test.exs` | `invoicing/views/index_test.exs` |
| `FirmowidWeb.InvoicingLive.InvoicingEntriesTable` | `FirmowidWeb.Invoicing.Components.EntriesTable` | `live/invoicing_live/invoicing_entries_table.ex` | `invoicing/components/entries_table.ex` |
| `FirmowidWeb.InvoicingLive.InvoiceSearchOverlay` | `FirmowidWeb.Invoicing.Components.SearchOverlay` | `live/invoicing_live/invoicing_search_overlay.ex` | `invoicing/components/search_overlay.ex` |
| `FirmowidWeb.InvoicingLive.MonthClosedZeroState` | `FirmowidWeb.Invoicing.Components.MonthClosedZeroState` | `live/invoicing_live/month_closed_zero_state.ex` | `invoicing/components/month_closed_zero_state.ex` |
| `FirmowidWeb.InvoicingLive.TransactionGroup` | `FirmowidWeb.Invoicing.Utilities.TransactionGroup` | `live/invoicing_live/transaction_group.ex` | `invoicing/utilities/transaction_group.ex` |
| `FirmowidWeb.Components.Invoicing.Assistant` | `FirmowidWeb.Invoicing.Components.Assistant` | `components/invoicing/assistant.ex` | `invoicing/components/assistant.ex` |
| `FirmowidWeb.Components.Invoicing.InvoiceDetails` | `FirmowidWeb.Invoicing.Components.InvoiceDetails` | `components/invoicing/invoice_details.ex` | `invoicing/components/invoice_details.ex` |
| `FirmowidWeb.Components.Invoicing.InvoiceTimeline` | `FirmowidWeb.Invoicing.Components.InvoiceTimeline` | `components/invoicing/invoice_timeline.ex` | `invoicing/components/invoice_timeline.ex` |
| `FirmowidWeb.Components.Invoicing.BankTransferModal` | `FirmowidWeb.Invoicing.Components.BankTransferModal` | `components/invoicing/bank_transfer_modal.ex` | `invoicing/components/bank_transfer_modal.ex` |
| `FirmowidWeb.Components.Invoicing.DownloadModal` | `FirmowidWeb.Invoicing.Components.DownloadModal` | `components/invoicing/download_modal.ex` | `invoicing/components/download_modal.ex` |
| `FirmowidWeb.Components.Invoicing.CostInvoiceDetails` | `FirmowidWeb.Invoicing.Components.CostInvoiceDetails` | `components/invoicing/cost_invoice_details.ex` | `invoicing/components/cost_invoice_details.ex` |
| `FirmowidWeb.Components.Invoicing.SalesInvoiceDetails` | `FirmowidWeb.Invoicing.Components.SalesInvoiceDetails` | `components/invoicing/sales_invoice_details.ex` | `invoicing/components/sales_invoice_details.ex` |

### Invoicing > Cost Invoices (nested feature)

| Old Module | New Module | Old Path | New Path |
|---|---|---|---|
| `FirmowidWeb.CostInvoiceLive.InboxLive` | `FirmowidWeb.Invoicing.CostInvoices.Views.Inbox` | `live/cost_invoice_live/inbox_live.ex` | `invoicing/cost_invoices/views/inbox.ex` |
| `FirmowidWeb.CostInvoiceLive.Show` | `FirmowidWeb.Invoicing.CostInvoices.Views.Show` | `live/cost_invoice_live/show.ex` | `invoicing/cost_invoices/views/show.ex` |
| `FirmowidWeb.CostInvoiceLive.Assistant` | `FirmowidWeb.Invoicing.CostInvoices.Components.Assistant` | `live/cost_invoice_live/assistant.ex` | `invoicing/cost_invoices/components/assistant.ex` |
| `FirmowidWeb.CostInvoicesApiController` | `FirmowidWeb.Invoicing.CostInvoices.Controllers.Api` | `controllers/cost_invoices_api_controller.ex` | `invoicing/cost_invoices/controllers/api.ex` |
| `FirmowidWeb.CostInvoicesApiControllerTest` | `FirmowidWeb.Invoicing.CostInvoices.Controllers.ApiTest` | `controllers/cost_invoices_api_controller_test.exs` | `invoicing/cost_invoices/controllers/api_test.exs` |
| `FirmowidWeb.ResendInboundController` | `FirmowidWeb.Invoicing.CostInvoices.Controllers.Inbound` | `controllers/resend_inbound_controller.ex` | `invoicing/cost_invoices/controllers/inbound.ex` |

### Invoicing > Sales Invoices (nested feature)

| Old Module | New Module | Old Path | New Path |
|---|---|---|---|
| `FirmowidWeb.SalesInvoicesLive.Creator` | `FirmowidWeb.Invoicing.SalesInvoices.Views.Creator` | `live/sales_invoices_live/creator.ex` | `invoicing/sales_invoices/views/creator.ex` |
| `FirmowidWeb.SalesInvoicesLive.Edit` | `FirmowidWeb.Invoicing.SalesInvoices.Views.Edit` | `live/sales_invoices_live/edit.ex` | `invoicing/sales_invoices/views/edit.ex` |
| `FirmowidWeb.SalesInvoicesLive.Show` | `FirmowidWeb.Invoicing.SalesInvoices.Views.Show` | `live/sales_invoices_live/show.ex` | `invoicing/sales_invoices/views/show.ex` |
| `FirmowidWeb.SalesInvoicesLive.Summary` | `FirmowidWeb.Invoicing.SalesInvoices.Views.Summary` | `live/sales_invoices_live/summary.ex` | `invoicing/sales_invoices/views/summary.ex` |
| `FirmowidWeb.SalesInvoicesLiveTest` | `FirmowidWeb.Invoicing.SalesInvoices.Views.SummaryTest` | `live/sales_invoices_live/summary_test.exs` | `invoicing/sales_invoices/views/summary_test.exs` |
| `FirmowidWeb.SalesInvoicesLive.Assistant` | `FirmowidWeb.Invoicing.SalesInvoices.Components.Assistant` | `live/sales_invoices_live/assistant.ex` | `invoicing/sales_invoices/components/assistant.ex` |
| `FirmowidWeb.SalesInvoicesLive.Components.InvoiceItems` | `FirmowidWeb.Invoicing.SalesInvoices.Components.InvoiceItems` | `live/sales_invoices_live/components/invoice_items.ex` | `invoicing/sales_invoices/components/invoice_items.ex` |
| `FirmowidWeb.SalesInvoicesLive.Components.InvoicePayment` | `FirmowidWeb.Invoicing.SalesInvoices.Components.InvoicePayment` | `live/sales_invoices_live/components/invoice_payment.ex` | `invoicing/sales_invoices/components/invoice_payment.ex` |
| `FirmowidWeb.SalesInvoices.Template` | `FirmowidWeb.Invoicing.SalesInvoices.Components.Template` | `components/sales_invoices/template.ex` | `invoicing/sales_invoices/components/template.ex` |
| `FirmowidWeb.PdfHTML` | `FirmowidWeb.Invoicing.SalesInvoices.Components.Pdf` | `controllers/pdf_html.ex` | `invoicing/sales_invoices/components/pdf.ex` |
| `FirmowidWeb.SharedInvoiceHTML` | `FirmowidWeb.Invoicing.SalesInvoices.Components.SharedPage` | `controllers/shared_invoice_html.ex` | `invoicing/sales_invoices/components/shared_page.ex` |
| `FirmowidWeb.PdfController` | `FirmowidWeb.Invoicing.SalesInvoices.Controllers.Pdf` | `controllers/pdf_controller.ex` | `invoicing/sales_invoices/controllers/pdf.ex` |
| `FirmowidWeb.SharedInvoiceController` | `FirmowidWeb.Invoicing.SalesInvoices.Controllers.Shared` | `controllers/shared_invoice_controller.ex` | `invoicing/sales_invoices/controllers/shared.ex` |

### Timetracker

| Old Module | New Module | Old Path | New Path |
|---|---|---|---|
| `FirmowidWeb.TimetrackerLive.Index` | `FirmowidWeb.Timetracker.Views.Index` | `live/timetracker_live/index.ex` | `timetracker/views/index.ex` |
| `FirmowidWeb.TimetrackerLiveTest` | `FirmowidWeb.Timetracker.Views.IndexTest` | `live/timetracker_live/index_test.exs` | `timetracker/views/index_test.exs` |
| `FirmowidWeb.Components.Session` | `FirmowidWeb.Timetracker.Components.Session` | `components/timetracker/session.ex` | `timetracker/components/session.ex` |
| `FirmowidWeb.Components.Timetracker.Overlap` | `FirmowidWeb.Timetracker.Components.Overlap` | `components/timetracker/overlap.ex` | `timetracker/components/overlap.ex` |
| `FirmowidWeb.CsvController` | `FirmowidWeb.Timetracker.Controllers.Csv` | `controllers/csv_controller.ex` | `timetracker/controllers/csv.ex` |
| `FirmowidWeb.TimetrackerLive.SessionForm` | `FirmowidWeb.Timetracker.Utilities.SessionForm` | `live/timetracker_live/session_form.ex` | `timetracker/utilities/session_form.ex` |
| `FirmowidWeb.TimetrackerLive.GroupedSessionForm` | `FirmowidWeb.Timetracker.Utilities.GroupedSessionForm` | `live/timetracker_live/grouped_session_form.ex` | `timetracker/utilities/grouped_session_form.ex` |

### Hours Record

| Old Module | New Module | Old Path | New Path |
|---|---|---|---|
| `FirmowidWeb.HoursRecordLive.Index` | `FirmowidWeb.HoursRecord.Views.Index` | `live/hours_record_live/index.ex` | `hours_record/views/index.ex` |
| `FirmowidWeb.HoursRecordLive.UploadForm` | `FirmowidWeb.HoursRecord.Components.UploadForm` | `live/hours_record_live/upload_form.ex` | `hours_record/components/upload_form.ex` |
| `FirmowidWeb.HoursRecord.PdfTemplate` | `FirmowidWeb.HoursRecord.Components.PdfTemplate` | `components/hours_record/pdf_template.ex` | `hours_record/components/pdf_template.ex` |
| `FirmowidWeb.HoursRecordHTML` | `FirmowidWeb.HoursRecord.Components.RecordHtml` | `controllers/hours_record_html.ex` | `hours_record/components/record_html.ex` |
| `FirmowidWeb.HoursRecordController` | `FirmowidWeb.HoursRecord.Controllers.Record` | `controllers/hours_record_controller.ex` | `hours_record/controllers/record.ex` |

### Management

| Old Module | New Module | Old Path | New Path |
|---|---|---|---|
| `FirmowidWeb.ManagementLive.Clients` | `FirmowidWeb.Management.Views.Clients` | `live/management_live/clients.ex` | `management/views/clients.ex` |
| `FirmowidWeb.ManagementLive.Employee` | `FirmowidWeb.Management.Views.Employee` | `live/management_live/employee.ex` | `management/views/employee.ex` |
| `FirmowidWeb.ManagementLive.Employees` | `FirmowidWeb.Management.Views.Employees` | `live/management_live/employees.ex` | `management/views/employees.ex` |
| `FirmowidWeb.ManagementLive.Project` | `FirmowidWeb.Management.Views.Project` | `live/management_live/project.ex` | `management/views/project.ex` |
| `FirmowidWeb.ManagementLive.ProjectForm` | `FirmowidWeb.Management.Views.ProjectForm` | `live/management_live/project_form.ex` | `management/views/project_form.ex` |
| `FirmowidWeb.ManagementLive.Projects` | `FirmowidWeb.Management.Views.Projects` | `live/management_live/projects.ex` | `management/views/projects.ex` |

### Settings

| Old Module | New Module | Old Path | New Path |
|---|---|---|---|
| `FirmowidWeb.SettingsLive.Index` | `FirmowidWeb.Settings.Views.Index` | `live/settings_live/index.ex` | `settings/views/index.ex` |
| `FirmowidWeb.SettingsLive.EditButton` | `FirmowidWeb.Settings.Components.EditButton` | `live/settings_live/edit_button.ex` | `settings/components/edit_button.ex` |

### Bank Sync

| Old Module | New Module | Old Path | New Path |
|---|---|---|---|
| `FirmowidWeb.BankSyncLive.Create` | `FirmowidWeb.BankSync.Views.Create` | `live/bank_sync_live/create.ex` | `bank_sync/views/create.ex` |
| `FirmowidWeb.BankSyncCreateLiveTest` | `FirmowidWeb.BankSync.Views.CreateTest` | `live/bank_sync_live/create_test.exs` | `bank_sync/views/create_test.exs` |

### Analysis

| Old Module | New Module | Old Path | New Path |
|---|---|---|---|
| `FirmowidWeb.AnalysisLive.Dashboard` | `FirmowidWeb.Analysis.Views.Dashboard` | `live/analysis_live/dashboard.ex` | `analysis/views/dashboard.ex` |
| `FirmowidWeb.AnalysisLive.EntriesTable` | `FirmowidWeb.Analysis.Components.EntriesTable` | `live/analysis_live/entries_table.ex` | `analysis/components/entries_table.ex` |

### Auth

| Old Module | New Module | Old Path | New Path |
|---|---|---|---|
| `FirmowidWeb.User.LoginLive` | `FirmowidWeb.Auth.Views.Login` | `live/user_live/login_live.ex` | `auth/views/login.ex` |
| `FirmowidWeb.UserLoginLiveTest` | `FirmowidWeb.Auth.Views.LoginTest` | `live/user_live/login_live_test.exs` | `auth/views/login_test.exs` |
| `FirmowidWeb.User.RegistrationLive` | `FirmowidWeb.Auth.Views.Registration` | `live/user_live/registration_live.ex` | `auth/views/registration.ex` |
| `FirmowidWeb.UserRegistrationLiveTest` | `FirmowidWeb.Auth.Views.RegistrationTest` | `live/user_live/registration_live_test.exs` | `auth/views/registration_test.exs` |
| `FirmowidWeb.User.ForgotPasswordLive` | `FirmowidWeb.Auth.Views.ForgotPassword` | `live/user_live/forgot_password_live.ex` | `auth/views/forgot_password.ex` |
| `FirmowidWeb.UserForgotPasswordLiveTest` | `FirmowidWeb.Auth.Views.ForgotPasswordTest` | `live/user_live/forgot_password_live_test.exs` | `auth/views/forgot_password_test.exs` |
| `FirmowidWeb.User.ResetPasswordLive` | `FirmowidWeb.Auth.Views.ResetPassword` | `live/user_live/reset_password_live.ex` | `auth/views/reset_password.ex` |
| `FirmowidWeb.UserResetPasswordLiveTest` | `FirmowidWeb.Auth.Views.ResetPasswordTest` | `live/user_live/reset_password_live_test.exs` | `auth/views/reset_password_test.exs` |
| `FirmowidWeb.User.ConfirmationLive` | `FirmowidWeb.Auth.Views.Confirmation` | `live/user_live/confirmation_live.ex` | `auth/views/confirmation.ex` |
| `FirmowidWeb.UserConfirmationLiveTest` | `FirmowidWeb.Auth.Views.ConfirmationTest` | `live/user_live/confirmation_live_test.exs` | `auth/views/confirmation_test.exs` |
| `FirmowidWeb.User.ConfirmationInstructionsLive` | `FirmowidWeb.Auth.Views.ConfirmationInstructions` | `live/user_live/confirmation_instructions_live.ex` | `auth/views/confirmation_instructions.ex` |
| `FirmowidWeb.UserConfirmationInstructionsLiveTest` | `FirmowidWeb.Auth.Views.ConfirmationInstructionsTest` | `live/user_live/confirmation_instructions_live_test.exs` | `auth/views/confirmation_instructions_test.exs` |
| `FirmowidWeb.User.SettingsLive` | `FirmowidWeb.Auth.Views.Settings` | `live/user_live/settings_live.ex` | `auth/views/settings.ex` |
| `FirmowidWeb.UserSettingsLiveTest` | `FirmowidWeb.Auth.Views.SettingsTest` | `live/user_live/settings_live_test.exs` | `auth/views/settings_test.exs` |
| `FirmowidWeb.UserSessionController` | `FirmowidWeb.Auth.Controllers.Session` | `controllers/user_session_controller.ex` | `auth/controllers/session.ex` |
| `FirmowidWeb.UserSessionApiController` | `FirmowidWeb.Auth.Controllers.SessionApi` | `controllers/user_session_api_controller.ex` | `auth/controllers/session_api.ex` |
| `FirmowidWeb.UserSessionApiControllerTest` | `FirmowidWeb.Auth.Controllers.SessionApiTest` | `controllers/user_session_api_controller_test.exs` | `auth/controllers/session_api_test.exs` |
| `FirmowidWeb.GoogleAuthController` | `FirmowidWeb.Auth.Controllers.Google` | `controllers/google_auth_controller.ex` | `auth/controllers/google.ex` |

### Landing

| Old Module | New Module | Old Path | New Path |
|---|---|---|---|
| `FirmowidWeb.LandingLive` | `FirmowidWeb.Landing.Views.Index` | `live/landing_live.ex` | `landing/views/index.ex` |
| `FirmowidWeb.LandingLiveTest` | `FirmowidWeb.Landing.Views.IndexTest` | `live/landing_live_test.exs` | `landing/views/index_test.exs` |
| `FirmowidWeb.Components.Landing` | `FirmowidWeb.Landing.Components.Landing` | `components/landing.ex` | `landing/components/landing.ex` |

### Organization

| Old Module | New Module | Old Path | New Path |
|---|---|---|---|
| `FirmowidWeb.OrganizationLive` | `FirmowidWeb.Organization.Views.Index` | `live/organization_live.ex` | `organization/views/index.ex` |
| `FirmowidWeb.OrganizationInvitesLive.Index` | `FirmowidWeb.Organization.Invites.Views.Index` | `live/organization_invites_live/index.ex` | `organization/invites/views/index.ex` |

### Billing

| Old Module | New Module | Old Path | New Path |
|---|---|---|---|
| `FirmowidWeb.BillingComponents` | `FirmowidWeb.Billing.Components.Billing` | `components/billing_components.ex` | `billing/components/billing.ex` |

### Feedback

| Old Module | New Module | Old Path | New Path |
|---|---|---|---|
| `FirmowidWeb.FeedbackLive.FormComponent` | `FirmowidWeb.Feedback.Components.Form` | `live/feedback_live/form_component.ex` | `feedback/components/form.ex` |

### Development

| Old Module | New Module | Old Path | New Path |
|---|---|---|---|
| `FirmowidWeb.DevelopmentLive` | `FirmowidWeb.Development.Views.Index` | `live/development_live.ex` | `development/views/index.ex` |

## Macro Hub Changes (firmowid_web.ex)

The file stays at `lib/firmowid_web.ex` as `FirmowidWeb`. It is the only
exception to the path rule (root module).

### Updated `html_helpers/0`

```elixir
defp html_helpers do
  quote do
    use Gettext, backend: FirmowidWeb.Core.Gettext

    import FirmowidWeb.DesignSystem.Components.CoreComponents
    # HTML escaping functionality
    import Phoenix.HTML
    # Core UI components and translation
    import Tails

    # Shortcut for generating JS commands
    alias Phoenix.LiveView.JS

    # Routes generation with the ~p sigil
    unquote(verified_routes())
  end
end
```

**Removed from global imports:**
- `FirmowidWeb.BillingComponents` -> import locally in 3 files
- `FirmowidWeb.Components.Landing` -> import locally in 1 file
- `FirmowidWeb.Icons` -> deleted entirely
- `FirmowidWeb.Flags` -> import locally in 1 file

### Updated `verified_routes/0`

```elixir
def verified_routes do
  quote do
    use Phoenix.VerifiedRoutes,
      endpoint: FirmowidWeb.Core.Endpoint,
      router: FirmowidWeb.Core.Router,
      statics: FirmowidWeb.static_paths()
  end
end
```

### Updated `:controller`

```elixir
def controller do
  quote do
    use Phoenix.Controller,
      formats: [:html, :json],
      layouts: [html: FirmowidWeb.Infrastructure.Layouts]

    use Gettext, backend: FirmowidWeb.Core.Gettext

    import Plug.Conn

    unquote(verified_routes())
  end
end
```

### Updated `:live_view`

```elixir
def live_view do
  quote do
    use Phoenix.LiveView,
      layout: {FirmowidWeb.Infrastructure.Layouts, :app},
      container: {:div, class: "min-h-full flex flex-col"}

    unquote(html_helpers())
  end
end
```

### Extract `toast_class_fn/1`

Move `toast_class_fn/1` (lines 116-130) from `firmowid_web.ex` to
`FirmowidWeb.Core.Toast`. Update the reference in `app.html.heex` from
`&FirmowidWeb.toast_class_fn/1` to `&FirmowidWeb.Core.Toast.toast_class_fn/1`.

## Config File Updates

All paths relative to project root.

### config/config.exs

```
FirmowidWeb.Endpoint    -> FirmowidWeb.Core.Endpoint
FirmowidWeb.ErrorHTML   -> FirmowidWeb.Infrastructure.Components.ErrorHtml
FirmowidWeb.ErrorJSON   -> FirmowidWeb.Infrastructure.Components.ErrorJson
```

### config/dev.exs

```
FirmowidWeb.Endpoint    -> FirmowidWeb.Core.Endpoint
```

### config/test.exs

```
FirmowidWeb.Endpoint    -> FirmowidWeb.Core.Endpoint
```

### config/prod.exs

```
FirmowidWeb.Endpoint    -> FirmowidWeb.Core.Endpoint
```

### config/runtime.exs

```
FirmowidWeb.Endpoint    -> FirmowidWeb.Core.Endpoint  (4 occurrences)
```

### lib/firmowid/application.ex

```
FirmowidWeb.Telemetry   -> FirmowidWeb.Core.Telemetry
FirmowidWeb.Endpoint    -> FirmowidWeb.Core.Endpoint  (2 occurrences)
```

### test/conn_case.ex

```
defmodule FirmowidWeb.ConnCase   -> stays (test support, not a web module)
use FirmowidWeb, :verified_routes -> stays (macro resolves new names internally)
@endpoint FirmowidWeb.Endpoint   -> @endpoint FirmowidWeb.Core.Endpoint
```

## Cross-Boundary References

Code outside `lib/firmowid_web/` that references web modules.

| File | Old Reference | New Reference | Notes |
|---|---|---|---|
| `lib/firmowid/invoicing.ex:18` | `alias FirmowidWeb.InvoicingLive.TransactionGroup` | `alias FirmowidWeb.Invoicing.Utilities.TransactionGroup` | **SMELL**: backend should not depend on web. Extract data logic into `Firmowid.Invoicing` context. |
| `lib/firmowid/sales_invoices/pdf.ex:8` | `alias FirmowidWeb.PdfHelpers` | `alias FirmowidWeb.Infrastructure.Utilities.PdfHelpers` | Acceptable — PDF generation is a web artifact. |
| `lib/firmowid/sales_invoices/pdf.ex:29` | `FirmowidWeb.PdfHTML` | `FirmowidWeb.Invoicing.SalesInvoices.Components.Pdf` | Same. |
| `lib/firmowid/application.ex:15` | `FirmowidWeb.Telemetry` | `FirmowidWeb.Core.Telemetry` | Supervisor tree. |
| `lib/firmowid/application.ex:33,64` | `FirmowidWeb.Endpoint` | `FirmowidWeb.Core.Endpoint` | Supervisor tree. |

## Local Import Additions

Modules removed from global `html_helpers/0` that need local imports.

### `FirmowidWeb.Billing.Components.Billing` (was `BillingComponents`)

Used in 3 views — add `import FirmowidWeb.Billing.Components.Billing` to each:
- `FirmowidWeb.Invoicing.Views.Index` (uses `limit_warning`)
- `FirmowidWeb.BankSync.Views.Create` (uses `limit_warning`)
- `FirmowidWeb.Settings.Views.Index` (uses `usage_limit_bar`)

### `FirmowidWeb.Landing.Components.Landing` (was `Components.Landing`)

Used in 1 view — add `import FirmowidWeb.Landing.Components.Landing` to:
- `FirmowidWeb.Landing.Views.Index`

### `FirmowidWeb.Infrastructure.Flags` (was `Flags`)

Used in 1 file — add `import FirmowidWeb.Infrastructure.Flags` to:
- `FirmowidWeb.Infrastructure.Layouts` (used in `app.html.heex`)

## Macro Usage Fixes

Modules using the wrong `use FirmowidWeb, :*` macro for their actual type.

| Module (new name) | Current macro | Should be | Reason |
|---|---|---|---|
| `FirmowidWeb.Invoicing.Components.EntriesTable` | `:live_view` | `:html` | No lifecycle callbacks. Pure function component. Zero state. |

`SessionForm` and `GroupedSessionForm` are NOT misusing Phoenix macros — they
use `Firmowid.Schema` and `Ecto.Schema` respectively. They are pure Ecto
embedded schemas used for form validation. They move to `utilities/` as-is.

## embed_templates Strategy

Three modules use `embed_templates`. Each needs its template directory to be
adjacent to (a child of `__DIR__` of) the `.ex` file.

### 1. Layouts

**File:** `infrastructure/layouts.ex`
**Call:** `embed_templates "layouts/*"`
**Templates:** `infrastructure/layouts/app.html.heex`, `infrastructure/layouts/root.html.heex`
**Works because:** `__DIR__` is `infrastructure/`, and `layouts/` is a child directory.

### 2. SharedPage (was SharedInvoiceHTML)

**File:** `invoicing/sales_invoices/components/shared_page.ex`
**Call:** `embed_templates "shared_page/templates/*"`
**Templates:** `invoicing/sales_invoices/components/shared_page/templates/*.html.heex`
**Note:** The module also has an inline `shared_page/1` function component. The
embedded templates (`show`, `error`, `not_found`) become additional function
components on the same module.

### 3. Creator

**File:** `invoicing/sales_invoices/views/creator.ex`
**Call:** `embed_templates "templates/creator_*"`
**Templates:** `invoicing/sales_invoices/views/templates/creator_*.html.heex`
**Note:** The `creator_*` glob pattern stays the same. Only the relative path
prefix changes.

## Icon Replacement

Delete `lib/firmowid_web/components/icons.ex` entirely.

In `settings/components/edit_button.ex`, replace:

```heex
<!-- Before -->
<.edit_icon class="h-4 w-4" />

<!-- After -->
<Lucideicons.square_pen class="h-4 w-4" />
```

The `Lucideicons.square_pen` icon is already used elsewhere in the project
(e.g., `management/views/project.html.heex`). The `lucide_icons` package
(`~> 2.0`) is already a dependency.

5 of 6 functions in `icons.ex` are dead code (`trash_icon`, `eye_closed_icon`,
`chevron_right_icon`, `arrow_left_icon`, `document_x_icon`). All replaced by
Lucide equivalents elsewhere.

## Invoicing DAG

Dependency direction is strictly one-way and layered.

```
Invoicing.CostInvoices.Views.*     ──> Invoicing.Components.*
Invoicing.CostInvoices.Components.* ──> Invoicing.Components.*
Invoicing.SalesInvoices.Views.*    ──> Invoicing.Components.*
Invoicing.SalesInvoices.Components.* ──> Invoicing.Components.*
Invoicing.Views.Index              ──> Invoicing.Components.DownloadModal (only)
Invoicing.Components.*             ──> DesignSystem.Components.CoreComponents (leaf)
```

No upward dependencies. No cross-dependencies between cost and sales. Clean DAG.

## Linting Enforcement

### 1. credo_naming

Add to `mix.exs`:

```elixir
{:credo_naming, "~> 2.1", only: [:dev, :test], runtime: false}
```

Add to `.credo.exs` checks:

```elixir
{CredoNaming.Check.Consistency.ModuleFilename, []}
```

This fails CI if any file's module name does not match its path.

### 2. Custom Credo check: folder-type constraints

Create `checks/check_module_placement.ex` (the project already has a
`checks/` directory referenced in `.credo.exs` via `requires: ["./checks/*.ex"]`).

The check should enforce:
- Files in `*/views/` must contain `use FirmowidWeb, :live_view`
- Files in `*/components/` must contain `use FirmowidWeb, :live_component`
  or `use FirmowidWeb, :html`
- Files in `*/controllers/` must contain `use FirmowidWeb, :controller`
- Files in `*/utilities/` must NOT contain any `use FirmowidWeb, :*` macro

Add to `.credo.exs`:

```elixir
{Checks.CheckModulePlacement, []}
```

## Design System Foundation

`design_system/` is prepared for the upcoming brand refactor from Figma.
Currently it holds only `CoreComponents` (1,243 lines). The future plan is to
break it into focused modules:

```
design_system/
├── components/
│   ├── core_components.ex    # Current — will be broken up
│   ├── buttons.ex            # Future
│   ├── inputs.ex             # Future
│   ├── modals.ex             # Future
│   ├── tables.ex             # Future
│   ├── typography.ex         # Future
│   └── navigation.ex         # Future
├── views/                    # Future: storybook/preview views
├── controllers/              # (empty)
└── utilities/                # Future: class helpers, theme utilities
```

This reorganization establishes the namespace and directory structure so the
brand refactor can proceed without another restructuring pass.

## Implementation Phases

Each phase must end with `mix check` passing (compile, format, credo, sobelow, test).
Commit after each successful phase.

### Phase 0: Tooling and quick wins

1. Add `credo_naming` to `mix.exs` deps
2. Write `checks/check_module_placement.ex` custom Credo check
3. Add both checks to `.credo.exs` (disabled initially — enable after Phase 6)
4. Replace `<.edit_icon>` with `<Lucideicons.square_pen>` in `edit_button.ex`
5. Delete `lib/firmowid_web/components/icons.ex`
6. Remove `import FirmowidWeb.Icons` from `html_helpers/0` in `firmowid_web.ex`
7. Fix `InvoicingEntriesTable`: change `use FirmowidWeb, :live_view` to
   `use FirmowidWeb, :html`
8. `mix check`

### Phase 1: Core

9. Create `lib/firmowid_web/core/` directory
10. Move + rename: `endpoint.ex`, `router.ex`, `telemetry.ex`, `gettext.ex`,
    `cache_body_reader.ex` to `core/` with `FirmowidWeb.Core.*` module names
11. Extract `toast_class_fn/1` from `firmowid_web.ex` into
    `core/toast.ex` as `FirmowidWeb.Core.Toast`
12. Update `firmowid_web.ex`: verified_routes endpoint/router, gettext backend
13. Update all config files: `config.exs`, `dev.exs`, `test.exs`, `prod.exs`,
    `runtime.exs`
14. Update `lib/firmowid/application.ex` supervisor references
15. Update `test/conn_case.ex` endpoint reference
16. Update `router.ex` internal references (it imports from UserAuth, Plugs —
    these haven't moved yet, so use old names temporarily)
17. `mix check`

### Phase 2: Infrastructure

18. Create full `infrastructure/` directory tree
19. Move + rename plugs to `FirmowidWeb.Infrastructure.Plugs.*`
20. Move + rename hooks to `FirmowidWeb.Infrastructure.Hooks.*`
21. Move `layouts.ex` + `layouts/` to `infrastructure/`. Rename module to
    `FirmowidWeb.Infrastructure.Layouts`
22. Move `user_auth.ex` + test to `infrastructure/`. Rename to
    `FirmowidWeb.Infrastructure.UserAuth`
23. Move `flags.ex` to `infrastructure/`. Rename to
    `FirmowidWeb.Infrastructure.Flags`
24. Move infra controllers (health, fallback, file_download) to
    `infrastructure/controllers/`. Rename and drop type suffixes.
25. Move error renderers (ErrorHTML, ErrorJSON, ChangesetJSON) to
    `infrastructure/components/`. Rename.
26. Move helpers to `infrastructure/utilities/`. Rename.
27. Clean `html_helpers/0`: remove `BillingComponents`, `Landing`, `Flags`
    imports. Add local imports where each is actually used (see Local Import
    Additions section).
28. Update `firmowid_web.ex` layout references in `:controller` and `:live_view`
29. Update `config.exs` error handler references
30. Update `router.ex` hook aliases, plug references, UserAuth import
31. Update `user_auth.ex` FallbackController alias
32. `mix check`

### Phase 3: Design System

33. Create `design_system/{components,views,controllers,utilities}/`
34. Move `core_components.ex` to `design_system/components/`. Rename to
    `FirmowidWeb.DesignSystem.Components.CoreComponents`
35. Update `html_helpers/0` import
36. Update the one explicit `import FirmowidWeb.CoreComponents` in
    `invoicing_entries_table.ex` (already renamed in Phase 0)
37. `mix check`

### Phase 4: Simple features (one at a time)

Each feature: create `{views,components,controllers,utilities}/` subdirs, move
files, rename modules, update router, update all alias/import/FQN references,
move colocated `.html.heex` and `_test.exs` files.

38. **timetracker** — 7 modules. Includes SessionForm + GroupedSessionForm
    moving to `utilities/`.
39. **hours_record** — 5 modules. Includes controller + components.
40. **management** — 6 modules. All views.
41. **settings** — 2 modules. View + component.
42. **bank_sync** — 1 module + test.
43. **analysis** — 2 modules. View + component.
44. **landing** — 2 modules. View + component (extracted from global imports).
45. **development** — 1 module.
46. **organization** — 2 modules. Includes nested `invites/`.
47. **feedback** — 1 module. Component only.
48. **billing** — 1 module. Component only (extracted from global imports).
49. **auth** — 17 modules. Biggest rename: `User.*Live` -> `Auth.Views.*`,
    controllers merged. Update router live_session references.
50. `mix check` after each feature

### Phase 5: Invoicing (nested features, last)

51. Create `invoicing/{views,components,controllers,utilities}/`
52. Move shared invoice components from `components/invoicing/` to
    `invoicing/components/`. Rename `FirmowidWeb.Components.Invoicing.*` to
    `FirmowidWeb.Invoicing.Components.*`.
53. Move invoicing dashboard views from `live/invoicing_live/` to
    `invoicing/views/`.
54. Move `TransactionGroup` to `invoicing/utilities/`.
55. Create `invoicing/cost_invoices/{views,components,controllers,utilities}/`
56. Move all cost_invoices modules. Rename.
57. Create `invoicing/sales_invoices/{views,components,controllers,utilities}/`
58. Move all sales_invoices modules. Rename. Update `embed_templates` paths.
59. Update all FQN references in HEEx templates (there are ~25 FQN component
    calls across templates).
60. `mix check`

### Phase 6: Cleanup and enforcement

61. Fix cross-boundary smell: extract data logic from `TransactionGroup` into
    `Firmowid.Invoicing` context so `lib/firmowid/invoicing.ex` no longer
    depends on a web module.
62. Delete all empty old directories: `live/`, `controllers/`, `components/`,
    `helpers/`, `plugs/`
63. Enable `credo_naming` and `CheckModulePlacement` checks in `.credo.exs`
64. Final `mix check` — all checks must pass with zero violations
65. Verify the full directory tree matches the target state documented above

## Reference: FQN Component Calls in HEEx Templates

These are the hardest references to find via grep because they appear as HTML
tags. Every one must be updated.

| Template File (old path) | FQN Reference (old) | New FQN |
|---|---|---|
| `live/timetracker_live/index.html.heex` | `FirmowidWeb.Components.Session.render` | `FirmowidWeb.Timetracker.Components.Session.render` |
| `live/timetracker_live/index.html.heex` | `FirmowidWeb.Components.Timetracker.Overlap.new_session_card` | `FirmowidWeb.Timetracker.Components.Overlap.new_session_card` |
| `live/timetracker_live/index.html.heex` | `FirmowidWeb.Components.Timetracker.Overlap.trim_action_card` | `FirmowidWeb.Timetracker.Components.Overlap.trim_action_card` |
| `live/sales_invoices_live/edit.html.heex` | `FirmowidWeb.SalesInvoicesLive.Creator.render_header` | `FirmowidWeb.Invoicing.SalesInvoices.Views.Creator.render_header` |
| `live/sales_invoices_live/edit.html.heex` | `FirmowidWeb.SalesInvoicesLive.Components.InvoiceItems.invoice_items` | `FirmowidWeb.Invoicing.SalesInvoices.Components.InvoiceItems.invoice_items` |
| `live/sales_invoices_live/edit.html.heex` | `FirmowidWeb.SalesInvoicesLive.Components.InvoicePayment.invoice_payment` | `FirmowidWeb.Invoicing.SalesInvoices.Components.InvoicePayment.invoice_payment` |
| `live/sales_invoices_live/edit.html.heex` | `FirmowidWeb.PdfHTML.sales_invoice` | `FirmowidWeb.Invoicing.SalesInvoices.Components.Pdf.sales_invoice` |
| `live/sales_invoices_live/creator_items.html.heex` | `FirmowidWeb.SalesInvoicesLive.Components.InvoiceItems.invoice_items` | `FirmowidWeb.Invoicing.SalesInvoices.Components.InvoiceItems.invoice_items` |
| `live/sales_invoices_live/creator_preview.html.heex` | `FirmowidWeb.PdfHTML.sales_invoice` | `FirmowidWeb.Invoicing.SalesInvoices.Components.Pdf.sales_invoice` |
| `live/sales_invoices_live/creator_payment.html.heex` | `FirmowidWeb.SalesInvoicesLive.Components.InvoicePayment.invoice_payment` | `FirmowidWeb.Invoicing.SalesInvoices.Components.InvoicePayment.invoice_payment` |
| `live/invoicing_live/index.html.heex` | `module={FirmowidWeb.Components.Invoicing.DownloadModal}` | `module={FirmowidWeb.Invoicing.Components.DownloadModal}` |
| `live/invoicing_live/index.html.heex` | `module={FirmowidWeb.InvoicingLive.InvoiceSearchOverlay}` | `module={FirmowidWeb.Invoicing.Components.SearchOverlay}` |
| `live/invoicing_live/index.html.heex` | `module={FirmowidWeb.InvoicingLive.MonthClosedZeroState}` | `module={FirmowidWeb.Invoicing.Components.MonthClosedZeroState}` |
| `live/invoicing_live/index.html.heex` | `FirmowidWeb.InvoicingLive.InvoicingEntriesTable.table` | `FirmowidWeb.Invoicing.Components.EntriesTable.table` |
| `live/hours_record_live/index.html.heex` | `module={FirmowidWeb.HoursRecordLive.UploadForm}` | `module={FirmowidWeb.HoursRecord.Components.UploadForm}` |
| `live/analysis_live/dashboard.html.heex` | `FirmowidWeb.AnalysisLive.EntriesTable.table` | `FirmowidWeb.Analysis.Components.EntriesTable.table` |
| `controllers/shared_invoice_html/show.html.heex` | `FirmowidWeb.PdfHTML.sales_invoice` | `FirmowidWeb.Invoicing.SalesInvoices.Components.Pdf.sales_invoice` |
| `controllers/shared_invoice_html/show.html.heex` | `FirmowidWeb.Components.Invoicing.InvoiceDetails.sales_invoice_metadata` | `FirmowidWeb.Invoicing.Components.InvoiceDetails.sales_invoice_metadata` |
| `controllers/hours_record_html.ex` (inline HEEx) | `FirmowidWeb.HoursRecord.PdfTemplate.hours_record` | `FirmowidWeb.HoursRecord.Components.PdfTemplate.hours_record` |
| `components/layouts/app.html.heex` | `module={FirmowidWeb.FeedbackLive.FormComponent}` | `module={FirmowidWeb.Feedback.Components.Form}` |
| `components/layouts/app.html.heex` | `&FirmowidWeb.toast_class_fn/1` | `&FirmowidWeb.Core.Toast.toast_class_fn/1` |
| `components/invoicing/sales_invoice_details.ex` (inline HEEx) | `FirmowidWeb.PdfHTML.sales_invoice` | `FirmowidWeb.Invoicing.SalesInvoices.Components.Pdf.sales_invoice` |
| `components/invoicing/sales_invoice_details.ex` (inline HEEx) | `module={FirmowidWeb.SalesInvoicesLive.Assistant}` | `module={FirmowidWeb.Invoicing.SalesInvoices.Components.Assistant}` |
| `components/invoicing/invoice_details.ex` (inline HEEx) | `module={FirmowidWeb.Components.Invoicing.BankTransferModal}` | `module={FirmowidWeb.Invoicing.Components.BankTransferModal}` |
| `components/invoicing/cost_invoice_details.ex` (inline HEEx) | `module={FirmowidWeb.CostInvoiceLive.Assistant}` | `module={FirmowidWeb.Invoicing.CostInvoices.Components.Assistant}` |

## Reference: All alias/import Statements to Update

| File (old path) | Old Statement | New Statement |
|---|---|---|
| `router.ex` | `alias FirmowidWeb.Live.Hooks.CurrentPath` | `alias FirmowidWeb.Infrastructure.Hooks.CurrentPath` |
| `router.ex` | `alias FirmowidWeb.Live.Hooks.Timezone` | `alias FirmowidWeb.Infrastructure.Hooks.Timezone` |
| `router.ex` | `import FirmowidWeb.Plugs.RedirectTrailing` | `import FirmowidWeb.Infrastructure.Plugs.RedirectTrailing` |
| `router.ex` | `import FirmowidWeb.UserAuth` | `import FirmowidWeb.Infrastructure.UserAuth` |
| `user_auth.ex` | `alias FirmowidWeb.FallbackController` | `alias FirmowidWeb.Infrastructure.Controllers.Fallback` |
| `live/timetracker_live/index.ex` | `alias FirmowidWeb.Helpers.TimeFormatter` | `alias FirmowidWeb.Infrastructure.Utilities.TimeFormatter` |
| `live/timetracker_live/index.ex` | `alias FirmowidWeb.TimetrackerLive.GroupedSessionForm` | `alias FirmowidWeb.Timetracker.Utilities.GroupedSessionForm` |
| `live/timetracker_live/index.ex` | `alias FirmowidWeb.TimetrackerLive.SessionForm` | `alias FirmowidWeb.Timetracker.Utilities.SessionForm` |
| `live/timetracker_live/grouped_session_form.ex` | `alias FirmowidWeb.TimetrackerLive.SessionForm` | `alias FirmowidWeb.Timetracker.Utilities.SessionForm` |
| `live/sales_invoices_live/edit.ex` | `alias FirmowidWeb.SalesInvoicesLive.Creator` | `alias FirmowidWeb.Invoicing.SalesInvoices.Views.Creator` |
| `live/sales_invoices_live/assistant.ex` | `alias FirmowidWeb.Components.Invoicing.Assistant, as: Components` | `alias FirmowidWeb.Invoicing.Components.Assistant, as: Components` |
| `live/management_live/project.ex` | `alias FirmowidWeb.Helpers.TimeFormatter` | `alias FirmowidWeb.Infrastructure.Utilities.TimeFormatter` |
| `live/management_live/employee.ex` | `alias FirmowidWeb.Helpers.TimeFormatter` | `alias FirmowidWeb.Infrastructure.Utilities.TimeFormatter` |
| `live/management_live/employee.ex` | `import FirmowidWeb.ManagementLive.Employees, only: [hours_record_status: 1]` | `import FirmowidWeb.Management.Views.Employees, only: [hours_record_status: 1]` |
| `live/invoicing_live/invoicing_entries_table.ex` | `alias FirmowidWeb.InvoicingLive.TransactionGroup` | `alias FirmowidWeb.Invoicing.Utilities.TransactionGroup` |
| `live/invoicing_live/invoicing_entries_table.ex` | `import FirmowidWeb.CoreComponents` | `import FirmowidWeb.DesignSystem.Components.CoreComponents` |
| `live/invoicing_live/index.ex` | `alias FirmowidWeb.InvoicingLive.TransactionGroup` | `alias FirmowidWeb.Invoicing.Utilities.TransactionGroup` |
| `live/hours_record_live/index.ex` | `alias FirmowidWeb.Helpers.TimeFormatter` | `alias FirmowidWeb.Infrastructure.Utilities.TimeFormatter` |
| `live/cost_invoice_live/assistant.ex` | `alias FirmowidWeb.Components.Invoicing.Assistant, as: Components` | `alias FirmowidWeb.Invoicing.Components.Assistant, as: Components` |
| `live/settings_live/index.ex` | `import FirmowidWeb.SettingsLive.EditButton` | `import FirmowidWeb.Settings.Components.EditButton` |
| `controllers/user_session_controller.ex` | `alias FirmowidWeb.UserAuth` | `alias FirmowidWeb.Infrastructure.UserAuth` |
| `controllers/pdf_html.ex` | `alias FirmowidWeb.SalesInvoices.Template` | `alias FirmowidWeb.Invoicing.SalesInvoices.Components.Template` |
| `controllers/hours_record_controller.ex` | `alias FirmowidWeb.PdfHelpers` | `alias FirmowidWeb.Infrastructure.Utilities.PdfHelpers` |
| `controllers/google_auth_controller.ex` | `alias FirmowidWeb.UserAuth` | `alias FirmowidWeb.Infrastructure.UserAuth` |
| `components/timetracker/session.ex` | `alias FirmowidWeb.Helpers.TimeFormatter` | `alias FirmowidWeb.Infrastructure.Utilities.TimeFormatter` |
| `components/timetracker/session.ex` | `alias FirmowidWeb.TimetrackerLive.GroupedSessionForm` | `alias FirmowidWeb.Timetracker.Utilities.GroupedSessionForm` |
| `components/timetracker/session.ex` | `alias FirmowidWeb.TimetrackerLive.Index` | `alias FirmowidWeb.Timetracker.Views.Index` |
| `components/invoicing/sales_invoice_details.ex` | `alias FirmowidWeb.Components.Invoicing.InvoiceDetails, as: InvoiceDetails` | `alias FirmowidWeb.Invoicing.Components.InvoiceDetails, as: InvoiceDetails` |
| `components/invoicing/sales_invoice_details.ex` | `alias FirmowidWeb.Components.Invoicing.InvoiceTimeline` | `alias FirmowidWeb.Invoicing.Components.InvoiceTimeline` |
| `components/invoicing/cost_invoice_details.ex` | `alias FirmowidWeb.Components.Invoicing.InvoiceDetails, as: InvoiceDetails` | `alias FirmowidWeb.Invoicing.Components.InvoiceDetails, as: InvoiceDetails` |
| `components/invoicing/cost_invoice_details.ex` | `alias FirmowidWeb.Components.Invoicing.InvoiceTimeline` | `alias FirmowidWeb.Invoicing.Components.InvoiceTimeline` |
| `components/invoicing/assistant.ex` | `alias FirmowidWeb.Helpers.TimeFormatter` | `alias FirmowidWeb.Infrastructure.Utilities.TimeFormatter` |
| `lib/firmowid/invoicing.ex` | `alias FirmowidWeb.InvoicingLive.TransactionGroup` | `alias FirmowidWeb.Invoicing.Utilities.TransactionGroup` |
| `lib/firmowid/sales_invoices/pdf.ex` | `alias FirmowidWeb.PdfHelpers` | `alias FirmowidWeb.Infrastructure.Utilities.PdfHelpers` |

## Reference: Router Module Updates

The router uses `scope "/", FirmowidWeb` which auto-prefixes module names.
Every `live` and controller reference inside that scope uses a short name that
gets expanded. These all need updating.

The full list of router references is in the "Router Module References" section
of the research data. Key examples:

```elixir
# Old
live "/fakturowanie", InvoicingLive.Index, :index

# New
live "/fakturowanie", Invoicing.Views.Index, :index
```

```elixir
# Old
live "/zaloguj", User.LoginLive, :new

# New
live "/zaloguj", Auth.Views.Login, :new
```

```elixir
# Old
get "/sprzedazowe/:id/pdf", PdfController, :index

# New
get "/sprzedazowe/:id/pdf", Invoicing.SalesInvoices.Controllers.Pdf, :index
```

Every route must be updated. There are approximately 35 LiveView references and
20 controller references in the router.
