# KSeF Implementation Plan for Firmowid

## Executive Summary

This document outlines the comprehensive plan for integrating Firmowid with Poland's National e-Invoicing System (KSeF - Krajowy System e-Faktur). The integration will enable Firmowid to:

- Submit sales invoices to KSeF and receive official KSeF numbers
- Download cost invoices from KSeF for processing

The implementation leverages Elixir's Oban job system for state management, and aligns the database schema with KSeF's FA(2) format to minimize transformation complexity.

## Table of Contents

1. [Background and Requirements](#background-and-requirements)
2. [Technical Architecture](#technical-architecture)
3. [Database Schema Changes](#database-schema-changes)
4. [API Client Design](#api-client-design)
5. [Invoice Transformation](#invoice-transformation)
6. [Immutability Implementation](#immutability-implementation)
7. [Oban Job Workflows](#oban-job-workflows)
8. [Error Handling and Recovery](#error-handling-and-recovery)
9. [Testing Strategy](#testing-strategy)
10. [UI/UX Changes](#uiux-changes)
11. [Security Considerations](#security-considerations)
12. [Deployment Plan](#deployment-plan)
13. [Monitoring and Operations](#monitoring-and-operations)

## 1. Background and Requirements

### KSeF Overview

KSeF is Poland's mandatory e-invoicing system that requires businesses to:

- Submit all B2B invoices electronically in FA(2) XML format
- Receive unique KSeF numbers for each invoice
- Maintain invoice immutability after submission

### Key Requirements

1. **Authentication**: Token-based authentication with session management
2. **Invoice Submission**: Convert Firmowid invoices to FA(2) XML and submit
3. **Status Tracking**: Monitor submission status and retrieve KSeF numbers
4. **Invoice Reception**: Download and process incoming cost invoices
5. **Immutability**: Prevent modifications to submitted invoices
6. **Compliance**: Ensure all invoices meet KSeF validation requirements

## 2. Technical Architecture

### Proposed Module Structure

Subject of change - we always want minimalism.

```
lib/firmowid/ksef/
├── api_client.ex          # Req-based HTTP client for KSeF API
├── auth.ex                # Authentication and session management
├── invoice_mapper.ex      # Bidirectional transformation (Firmowid ↔ FA(2))
├── invoice_validator.ex   # XSD validation and business rules
├── session_worker.ex      # Oban worker for session lifecycle
├── submission_worker.ex   # Oban worker for invoice submission
├── fetch_worker.ex        # Oban worker for downloading cost invoices
└── credentials.ex         # Encrypted credential management
```

### Key Design Decisions

1. **Oban as State Machine**: Use Oban jobs to track submission states and session lifecycle, eliminating need for separate state tables
2. **Schema Alignment**: Modify existing invoice tables to closely match FA(2) structure, reducing transformation complexity
3. **Immutability by Design**: Lock invoices upon KSeF submission to ensure
   compliance, enforced at database level and application level

## 3. Database Schema Changes

### 3.1 Sales Invoices Table Updates

```sql
ALTER TABLE sales_invoices 
  -- KSeF submission tracking
  ADD COLUMN ksef_number VARCHAR(255),                    -- Official KSeF invoice number
  ADD COLUMN ksef_reference_number VARCHAR(255),          -- Submission reference
  ADD COLUMN ksef_submission_job_id BIGINT REFERENCES oban_jobs(id),
  ADD COLUMN ksef_submitted_at TIMESTAMP,
  ADD COLUMN is_ksef_submitted BOOLEAN DEFAULT FALSE,
  
  -- Immutability enforcement
  ADD COLUMN locked_at TIMESTAMP,                         -- When invoice was locked
  ADD COLUMN locked_reason VARCHAR(50),                   -- 'ksef_submitted', 'manual', etc.
  
  -- FA(2) invoice type alignment
  ADD COLUMN invoice_subtype VARCHAR(50),                 -- 'VAT', 'KOR', 'ZAL', 'ROZ', 'UPR'
  ADD COLUMN original_invoice_number VARCHAR(255),        -- For corrections (KOR)
  ADD COLUMN correction_reason TEXT,                      -- Required for corrections
  ADD COLUMN correction_type VARCHAR(50),                 -- Type of correction
  ADD COLUMN is_final_invoice BOOLEAN DEFAULT FALSE,     -- For advance settlements
  
  -- Enhanced seller information (FA(2) requirements)
  ADD COLUMN seller_country_code VARCHAR(2) DEFAULT 'PL',
  ADD COLUMN seller_email VARCHAR(255),
  ADD COLUMN seller_phone VARCHAR(50),
  ADD COLUMN seller_bank_name VARCHAR(255),
  ADD COLUMN seller_bank_account_swift VARCHAR(11),
  
  -- Enhanced buyer information
  ADD COLUMN buyer_country_code VARCHAR(2) DEFAULT 'PL',
  ADD COLUMN buyer_internal_id VARCHAR(255),             -- Internal buyer reference
  ADD COLUMN buyer_ksef_id VARCHAR(255),                 -- KSeF platform buyer ID
  
  -- Payment details (FA(2) P_14 section)
  ADD COLUMN payment_terms TEXT,
  ADD COLUMN paid_amount DECIMAL(15,2) DEFAULT 0,
  ADD COLUMN payment_due_amount DECIMAL(15,2),
  ADD COLUMN payment_bank_account VARCHAR(255),
  ADD COLUMN split_payment BOOLEAN DEFAULT FALSE,        -- Mechanizm podzielonej płatności
  
  -- Special markers and procedures
  ADD COLUMN is_self_billing BOOLEAN DEFAULT FALSE,      -- Samofakturowanie
  ADD COLUMN is_vat_margin BOOLEAN DEFAULT FALSE,        -- Procedura marży
  ADD COLUMN is_tourism_margin BOOLEAN DEFAULT FALSE,    -- Marża - turystyka
  ADD COLUMN special_procedure VARCHAR(50),               -- Special tax procedures
  
  -- Additional compliance fields
  ADD COLUMN cash_register_number VARCHAR(50),           -- For cash register invoices
  ADD COLUMN annotations TEXT;                            -- Additional annotations

-- Indexes for performance
CREATE UNIQUE INDEX sales_invoices_ksef_number_idx 
  ON sales_invoices(ksef_number) 
  WHERE ksef_number IS NOT NULL;

CREATE INDEX sales_invoices_locked_at_idx 
  ON sales_invoices(locked_at) 
  WHERE locked_at IS NOT NULL;

CREATE INDEX sales_invoices_ksef_submitted_idx 
  ON sales_invoices(is_ksef_submitted, organization_id) 
  WHERE is_ksef_submitted = TRUE;
```

### 3.2 Sales Invoice Items Table Updates

```sql
ALTER TABLE sales_invoice_items
  -- Sequential numbering (required by KSeF)
  ADD COLUMN item_number INTEGER NOT NULL,
  
  -- Classification codes
  ADD COLUMN classification_code VARCHAR(20),            -- PKWiU, CN, or PKOB code
  ADD COLUMN classification_type VARCHAR(10),            -- 'PKWiU', 'CN', 'PKOB'
  ADD COLUMN gtu_code VARCHAR(10),                      -- GTU_01 through GTU_13
  
  -- Service/goods distinction
  ADD COLUMN is_service BOOLEAN DEFAULT FALSE,
  ADD COLUMN service_date_from DATE,
  ADD COLUMN service_date_to DATE,
  
  -- VAT special cases
  ADD COLUMN vat_marker VARCHAR(20),                    -- 'SW', 'EE', 'TP', 'TP-R', etc.
  ADD COLUMN vat_exemption_reason TEXT,                 -- Reason for 0% or exempt
  ADD COLUMN is_vat_margin BOOLEAN DEFAULT FALSE,
  
  -- Additional pricing fields
  ADD COLUMN discount_percentage DECIMAL(5,2),
  ADD COLUMN base_net_price DECIMAL(15,2),             -- Price before discounts
  
  -- Constraints
  ADD CONSTRAINT sales_invoice_items_item_number_unique 
    UNIQUE(sales_invoice_id, item_number);
```

### 3.3 Cost Invoices Table Updates

```sql
ALTER TABLE cost_invoices
  -- KSeF tracking
  ADD COLUMN ksef_number VARCHAR(255),
  ADD COLUMN ksef_download_reference VARCHAR(255),
  ADD COLUMN ksef_downloaded_at TIMESTAMP,
  ADD COLUMN ksef_fetch_job_id BIGINT REFERENCES oban_jobs(id), -- maybe remove?
  
  -- Enhanced seller information from KSeF
  ADD COLUMN seller_nip VARCHAR(20),
  ADD COLUMN seller_country_code VARCHAR(2),
  ADD COLUMN seller_email VARCHAR(255),
  ADD COLUMN seller_phone VARCHAR(50),
  
  -- Invoice type information
  ADD COLUMN invoice_type VARCHAR(50),                   -- 'VAT', 'KOR', etc.
  ADD COLUMN original_invoice_number VARCHAR(255),       -- For corrections
  
  -- Payment information
  ADD COLUMN payment_method VARCHAR(50),
  ADD COLUMN payment_terms TEXT,
  ADD COLUMN paid_amount DECIMAL(15,2),
  
  -- Create index for deduplication
  CREATE UNIQUE INDEX cost_invoices_ksef_number_idx 
    ON cost_invoices(ksef_number, organization_id) 
    WHERE ksef_number IS NOT NULL;
```

### 3.4 New Tables

```sql
-- KSeF credentials per organization
CREATE TABLE ksef_credentials (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  environment VARCHAR(20) NOT NULL CHECK (environment IN ('test', 'demo', 'production')),
  auth_type VARCHAR(20) NOT NULL CHECK (auth_type IN ('token', 'certificate')),
  credentials JSONB NOT NULL,  -- Encrypted JSON with token/cert data
  is_active BOOLEAN DEFAULT TRUE,
  last_used_at TIMESTAMP,
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
  
  UNIQUE(organization_id, environment)
);

-- Audit log for KSeF operations -- maybe not required or actually crucial
CREATE TABLE ksef_audit_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id),
  operation_type VARCHAR(50) NOT NULL,  -- 'submit', 'fetch', 'auth', etc.
  entity_type VARCHAR(50),              -- 'sales_invoice', 'cost_invoice'
  entity_id UUID,
  ksef_reference VARCHAR(255),
  request_data JSONB,
  response_data JSONB,
  status VARCHAR(20),                   -- 'success', 'failure', 'timeout'
  error_message TEXT,
  performed_by UUID REFERENCES users(id),
  created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

-- Index for audit queries
CREATE INDEX ksef_audit_logs_org_created_idx 
  ON ksef_audit_logs(organization_id, created_at DESC);
```

## 4. API Client Design

### 4.1 Req-based HTTP Client

The API client uses Req with proper configuration for KSeF's requirements:

```elixir
defmodule Firmowid.KSeF.ApiClient do
  @moduledoc """
  HTTP client for KSeF API communication using Req.
  Handles authentication, invoice submission, and status checking.
  """
  
  @base_urls %{
    test: "https://ksef-test.mf.gov.pl/api",
    demo: "https://ksef-demo.mf.gov.pl/api",
    production: "https://ksef.mf.gov.pl/api"
  }
  
  # Client configuration with retry and timeout settings
  def client(environment, session_token \\ nil)
  
  # Authentication endpoints
  def init_session_token(nip, token, environment)
  def init_session_certificate(certificate_data, environment)
  def terminate_session(session_token, environment)
  def get_session_status(session_token, environment)
  
  # Invoice operations
  def send_invoice(session_token, invoice_xml, environment)
  def get_invoice_status(session_token, reference_number, environment)
  def download_invoice(session_token, ksef_number, environment)
  
  # Batch operations
  def send_invoice_batch(session_token, batch_xml, environment)
  def get_batch_status(session_token, batch_reference, environment)
  
  # Query operations
  def query_invoices(session_token, criteria, environment)
end
```

### 4.2 Session Management

```elixir
defmodule Firmowid.KSeF.Auth do
  @moduledoc """
  Manages KSeF authentication sessions with automatic renewal.
  Uses Oban jobs to maintain active sessions per organization.
  """
  
  # Get or create active session
  def ensure_active_session(organization_id, environment)
  
  # Check if session needs renewal (5 minutes before expiry)
  def session_needs_renewal?(session)
  
  # Renew existing session
  def renew_session(session_token, environment)
  
  # Get credentials for organization
  def get_credentials(organization_id, environment)
end
```

## 5. Invoice Transformation

### 5.1 Mapping Strategy

The transformation between Firmowid's schema and KSeF's FA(2) format is simplified due to schema alignment:

```elixir
defmodule Firmowid.KSeF.InvoiceMapper do
  @moduledoc """
  Bidirectional transformation between Firmowid invoices and KSeF FA(2) XML.
  Handles all invoice types: VAT, KOR, ZAL, ROZ, UPR.
  """
  
  # Firmowid to KSeF
  def to_fa2_xml(%SalesInvoice{} = invoice)
  def to_fa2_batch(invoices)
  
  # KSeF to Firmowid
  def from_fa2_xml(xml_string)
  def extract_cost_invoice_data(fa2_map)
  
  # Validation
  def validate_against_xsd(xml_string, invoice_type)
  def validate_business_rules(invoice)
end
```

### 5.2 Field Mapping

Key mappings between Firmowid and FA(2):

| Firmowid Field | FA(2) Element | Notes |
|----------------|---------------|-------|
| invoice_number | P_2 | Must be unique within organization |
| issue_date | P_1 | Data wystawienia |
| sale_date | P_6 | Data sprzedaży |
| seller_nip | Podmiot1/DaneIdentyfikacyjne/NIP | |
| buyer_nip | Podmiot2/DaneIdentyfikacyjne/NIP | For B2B |
| buyer_pesel | Podmiot2/DaneIdentyfikacyjne/NrPESEL | For B2C |
| currency | KodWaluty | ISO 4217 code |
| invoice_subtype | RodzajFaktury | Determines XML structure |

## 6. Immutability Implementation

### 6.1 Locking Mechanism

Once an invoice is submitted to KSeF, it becomes immutable:

```elixir
defmodule Firmowid.SalesInvoices.SalesInvoice do
  # Regular changeset checks if invoice is locked
  def changeset(invoice, attrs) do
    invoice
    |> check_if_locked()
    |> cast(attrs, @fields)
    |> validate_required(@required_fields)
  end
  
  # Special changeset for KSeF updates only
  def ksef_update_changeset(invoice, attrs) do
    # Only allows updating KSeF-specific fields
    invoice
    |> cast(attrs, @ksef_fields)
  end
  
  defp check_if_locked(changeset) do
    if get_field(changeset, :locked_at) do
      add_error(changeset, :base, "Invoice is locked and cannot be modified")
    else
      changeset
    end
  end
end
```

### 6.2 Correction Workflow

For locked invoices that need corrections:

1. Create new invoice with `invoice_subtype = "KOR"`
2. Link to original via `original_invoice_number`
3. Specify `correction_reason` and what changed
4. Submit correction to KSeF
5. Original invoice remains unchanged

## 7. Oban Job Workflows

### 7.1 Session Worker

Maintains active KSeF sessions with automatic renewal:

```elixir
defmodule Firmowid.KSeF.SessionWorker do
  use Oban.Worker,
    queue: :ksef_sessions,
    max_attempts: 3,
    unique: [period: :infinity, keys: [:organization_id, :environment]]
  
  # Job args structure:
  # %{
  #   "action" => "authenticate" | "renew",
  #   "organization_id" => uuid,
  #   "environment" => "test" | "demo" | "production",
  #   "session_token" => string (for renewal),
  #   "expires_at" => datetime
  # }
  
  # Workflow:
  # 1. Authenticate with credentials
  # 2. Store session token in job args
  # 3. Schedule renewal 5 minutes before expiry
  # 4. On renewal, update token and reschedule
end
```

### 7.2 Submission Worker

Handles invoice submission in phases:

```elixir
defmodule Firmowid.KSeF.SubmissionWorker do
  use Oban.Worker,
    queue: :ksef_submissions,
    max_attempts: 5
  
  # Job args structure:
  # %{
  #   "phase" => "prepare" | "submit" | "verify",
  #   "sales_invoice_id" => uuid,
  #   "organization_id" => uuid,
  #   "environment" => string,
  #   "ksef_reference" => string (after submit),
  #   "attempt_count" => integer
  # }
  
  # Phase workflow:
  # prepare: Generate and validate XML
  # submit: Send to KSeF, get reference
  # verify: Poll for KSeF number
end
```

### 7.3 Fetch Worker

Downloads cost invoices from KSeF:

```elixir
defmodule Firmowid.KSeF.FetchWorker do
  use Oban.Worker,
    queue: :ksef_fetch,
    max_attempts: 3
  
  # Job args structure:
  # %{
  #   "action" => "query" | "download",
  #   "organization_id" => uuid,
  #   "environment" => string,
  #   "date_from" => date,
  #   "date_to" => date,
  #   "ksef_numbers" => [string] (for download)
  # }
  
  # Workflow:
  # 1. Query for new invoices in date range
  # 2. Filter out already downloaded
  # 3. Download each new invoice
  # 4. Create cost invoice records
  # 5. Trigger matching process
end
```

## 8. Error Handling and Recovery

### 8.1 Error Categories

1. **Authentication Errors**
   - Invalid credentials → Alert user, disable submissions
   - Session expired → Automatic renewal
   - Rate limited → Exponential backoff

2. **Validation Errors**
   - XSD validation failure → Show specific errors to user
   - Business rule violation → Detailed error messages
   - Missing required fields → Prevent submission

3. **Network Errors**
   - Timeout → Retry with backoff
   - Connection failure → Queue for retry
   - Partial failure → Resume from last successful step

4. **KSeF API Errors**
   - 400 Bad Request → Log and alert user
   - 401 Unauthorized → Reauthenticate
   - 429 Too Many Requests → Backoff and retry
   - 500 Server Error → Retry with exponential backoff

### 8.2 Recovery Strategies

```elixir
defmodule Firmowid.KSeF.ErrorHandler do
  # Categorize errors and determine recovery action
  def handle_error({:error, %{status: 429}}), do: {:retry, delay: :exponential}
  def handle_error({:error, %{status: 401}}), do: {:reauthenticate}
  def handle_error({:error, %{status: 400, body: body}}), do: {:validation_error, parse_errors(body)}
  def handle_error({:error, :timeout}), do: {:retry, delay: 5000}
  
  # User-friendly error messages
  def format_error_for_user(error)
end
```

## 9. Testing Strategy

### 9.1 Test Levels

1. **Unit Tests**
   - XML transformation accuracy
   - Field mapping correctness
   - Validation logic
   - Error handling

2. **Integration Tests**
   - KSeF test environment communication
   - Session lifecycle
   - Invoice submission flow
   - Cost invoice fetching

3. **End-to-End Tests**
   - Complete invoice lifecycle
   - Error recovery scenarios
   - Concurrent submissions
   - Performance under load

### 9.2 Test Data

Create comprehensive test fixtures:

- Various invoice types (VAT, KOR, ZAL, etc.)
- Edge cases (foreign currency, special procedures)
- Invalid data for error testing
- Large batches for performance testing

### 9.3 Compliance Testing

- Validate all generated XML against official XSD schemas
- Test business rule compliance
- Verify immutability enforcement
- Check audit trail completeness

## 10. UI/UX Changes

### 10.1 Organization Settings

Add KSeF configuration section:

- Environment selection (test/production)
- Credential management
- Test connection button
- Submission preferences

### 10.2 Invoice List View

> No. We don't.

Enhanced with KSeF status:

- KSeF number display
- Submission status indicator
- Lock icon for submitted invoices
- Retry button for failed submissions

### 10.3 Invoice Detail View

KSeF information panel:

- Submission status and history
- KSeF number (if submitted)
- Error messages (if failed)
- Download XML button

## 11. Security Considerations

### 11.1 Credential Storage

- Encrypt credentials at rest using Cloak (idk what it is)
- Separate credentials per environment
- Audit all credential access
- Rotate tokens periodically

### 11.2 Data Protection

- Encrypt sensitive invoice data
- Secure communication with KSeF (TLS 1.2+)
- Validate all input data
- Sanitize error messages

### 11.3 Access Control

- Role-based permissions for KSeF operations
- Audit trail for all submissions
- Separate test/production access
- IP whitelisting for production

## Conclusion

This implementation plan provides a comprehensive approach to integrating KSeF with Firmowid. The design emphasizes:

- Reliability through Oban job management
- Compliance through schema alignment and immutability
- Performance through efficient transformation
- User experience through clear status tracking

The phased approach allows for iterative development and testing, ensuring a smooth rollout to production.

