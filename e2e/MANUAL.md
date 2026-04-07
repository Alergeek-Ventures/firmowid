# Scenarios

## S01 — Authentication

1. Sign out if logged in
2. Navigate to /zaloguj
3. Log in with <kira@bytecraft.collective> / kolejka123456
4. Verify redirect to main page, navbar shows Fakturowanie, Analiza, Czasośledź, Zarządzanie
5. Sign out via user dropdown → /sign-out
6. Verify redirect to landing or login
Expected: All nav items visible for admin. Sign-out clears session.

## S02 — Connect KSeF account via token

1. Log in as kira (admin)
2. Go to /ustawienia/organizacja
3. Find the KSeF section
4. Paste token: 20260406-EC-4D64AD5000-176BED60A2-7C|nip-6161525811|a06968acfd8d449a9923d760fc2dbb55306534e168fa47b1bac09a255f945600
5. Submit / save
6. Verify status indicator changes to "connected" (or equivalent)
7. Cleanup: Disconnect the KSeF credential after verifying
Expected: Token accepted, credential stored, status visible in settings.

## S03 — Add a sandbox bank account via GoCardless

1. Log in as kira (admin)
2. Go to /ustawienia/konta-bankowe
3. Click "Add bank account" / Dodaj konto
4. Navigate to /ustawienia/bank/dodaj
5. Select a sandbox institution (GoCardless sandbox / test bank — usually labeled "Sandbox" or "Developer")
6. Complete OAuth redirect flow
7. Verify new bank account appears in /ustawienia/konta-bankowe with status "connected"
8. Rename the account (inline rename)
9. Set it as default if not already
Expected: Bank account connected, visible in list, renameable.

## S04 — Issue a sales invoice (full wizard)

1. Log in as kira (admin)
2. Go to /sprzedazowe (or click "Nowa faktura" from /fakturowanie)
3. Step 1 — Counterparty: Search for existing counterparty (e.g. from seed data) or create new (name, NIP, address)
4. Step 2 — Items: Add at least 2 line items (name, qty, unit price, VAT rate 23%)
5. Step 3 — Payment: Set sale date = today, due date = +14 days, payment method = bank transfer, select default bank account
6. Step 4 — Preview: Verify PDF preview renders, pick invoice number/series, click "Confirm"
7. Verify redirect to summary page /sprzedazowe/:id/podsumowanie
8. From summary, attempt "Send to KSeF" (will fail if KSeF not connected — verify error is graceful)
9. Go to /sprzedazowe/:id — verify invoice details, status badge
Expected: Invoice created, PDF renderable, summary shown, KSeF send attempt handled.

## S05 — Issue a sales invoice and send to KSeF

Pre-condition: S02 completed (KSeF connected)

1. Repeat S04 steps 1–6
2. On step 4 preview, click "Wyślij do KSeF"
3. Verify summary shows KSeF sending animation
4. Wait for status to update (submitted / error)
5. Go to /sprzedazowe/:id — verify KSeF status badge and timeline
Expected: Invoice submitted to KSeF, status timeline visible.

## S06 — Add a cost invoice via file upload (blob)

1. Log in as kira (admin)
2. Go to /fakturowanie
3. Drag-and-drop a PDF or image file onto the invoicing hub (or use the upload button)
4. Verify the file is processed and a cost invoice entry appears
5. Click into the cost invoice → /kosztowe/:id
6. Verify blob (PDF/image) is displayed
7. Verify extracted data fields (amount, date, counterparty) — may be partially auto-filled
Expected: File uploaded, cost invoice created, blob visible in detail view.

## S07 — Link invoice to transaction (from recommendation)

Pre-condition: At least one sales or cost invoice and one bank transaction exist

1. Log in as kira (admin)
2. Go to /fakturowanie, switch to "Unmatched" tab
3. Find an invoice or transaction with a match recommendation (highlighted suggestion)
4. Click the recommended match button
5. Verify the pair is linked and disappears from "Unmatched" tab
6. Go to the invoice detail — verify the transaction is listed under "Powiązane transakcje"
Expected: Invoice and transaction linked via recommendation, reflected in both views.

## S08 — Link invoice to transaction via the AI assistant

Pre-condition: At least one unmatched invoice and unmatched transaction exist

1. Log in as kira (admin)
2. Go to /fakturowanie
3. Open a sales or cost invoice detail
4. Open the matching assistant panel
5. Interact with the assistant — ask it to find a matching transaction
6. Confirm the suggested link
7. Verify both invoice and transaction show as matched
Expected: Assistant surfaces a transaction, link confirmed, records updated.

## S09 — Unlink invoice from transaction

1. Log in as kira (admin)
2. Open a matched sales or cost invoice detail
3. Find the linked transaction in the detail panel
4. Click disconnect/unlink
5. Verify both invoice and transaction are unmatched again
Expected: Pair unlinked cleanly.

## S10 — Delete a cost invoice

1. Log in as kira (admin)
2. Go to /fakturowanie or navigate to a cost invoice detail /kosztowe/:id
3. Click "Delete invoice" / Usuń
4. Confirm deletion in dialog
5. Verify invoice disappears from the list
Expected: Invoice deleted, removed from invoicing hub.

## S11 — Edit a sales invoice (creates correction)

1. Log in as kira (admin)
2. Go to /sprzedazowe/:id/edytuj on an existing invoice
3. Change a line item price or quantity
4. Save
5. Verify a correction invoice is created (if already submitted to KSeF) or the original is updated (if draft)
Expected: Edit flow handled correctly depending on invoice state.

## S12 — Download invoices for a month

1. Log in as kira (admin)
2. Go to /fakturowanie
3. Select a month that has invoices
4. Click "Download month" / Pobierz miesiąc
5. Verify ZIP download starts (or modal appears with download link)
6. Extract ZIP — verify it contains PDFs of all invoices in the selected month
Expected: ZIP file downloaded with correct invoice PDFs.

## S13 — View and share a public invoice link

1. Log in as kira (admin)
2. Open a sales invoice detail /sprzedazowe/:id
3. Find the "Share" or copy link button
4. Copy the public link (/faktura/:token)
5. Open link in incognito/private browser (no auth)
6. Verify invoice is readable
7. Verify PDF download works via /faktura/:token/pdf
Expected: Public share link works without authentication.

## S14 — Cost invoice inbox (inbound email)

1. Log in as kira (admin)
2. Go to /ustawienia/organizacja — note the inbound email address
3. Go to /kosztowe/skrzynka
4. Verify inbox list renders (may be empty in sandbox)
5. If seed emails exist — click one and verify processing status
Expected: Inbox renders, entries show processing state.

## S15 — Add a project

1. Log in as kira (admin)
2. Go to /zarzadzanie/projekty/dodaj
3. Fill in: project name, select counterparty (optional), add team members (select from seed users)
4. Save
5. Verify project appears in /zarzadzanie/projekty
6. Click into it — verify member list, month stats (empty)
Expected: Project created, members assigned, visible in list.

## S16 — Browse projects

1. Log in as kira (admin)
2. Go to /zarzadzanie/projekty
3. Verify active projects list with month hours and cost
4. Search by name — verify filter works
5. Navigate to /zarzadzanie/projekty/archiwum — verify archived projects
6. Archive an active project (from detail page) — verify it moves to archive
7. Unarchive it — verify it returns to active list
Expected: Project list, search, archive/unarchive all work.

## S17 — Edit a project

1. Log in as kira (admin)
2. Go to /zarzadzanie/projekty/:id/edycja
3. Change project name
4. Add / remove a member
5. Save
6. Verify changes reflected in project detail
Expected: Project editable, member changes saved.

## S18 — Add an employee (invite flow)

1. Log in as kira (admin)
2. Go to /zaproszenia
3. Generate a new invite code
4. Copy the invite code
5. Open incognito window → register a new account
6. During / after registration, use invite code to join the organization
7. Back as kira — go to /zarzadzanie/pracownicy — verify new user appears
8. Set an hourly rate for the new employee
Expected: Invite generated, new user joins org, appears in employee list with editable rate.

## S19 — Track time in a project

1. Log in as sable (employee) or kira
2. Go to /czasosledz
3. Select a project from the dropdown, enter a session title
4. Click Start
5. Verify session timer is running (page title updates)
6. Wait 30 seconds, click Stop
7. Verify session appears in history with correct duration and project
Expected: Timer starts, session recorded on stop.

## S20 — Add a session with explicit times

1. Log in as any user with access to /czasosledz
2. Open the extended session form (not quick-start)
3. Enter: project, title, date, start time, end time (e.g. 09:00–11:30)
4. Save
5. Verify session appears in history with correct times
Expected: Manual session entry works.

## S21 — Session overlap detection

1. Log in as any user
2. Go to /czasosledz
3. Add a session from 10:00–12:00 today
4. Add another session from 11:00–13:00 today (overlapping)
5. Verify overlap warning / conflict dialog appears
6. Confirm trim or cancellation per dialog options
Expected: Overlap detected, conflict resolution dialog shown.

## S22 — Submit an hours record

1. Log in as sable (employee)
2. Go to /czasosledz/ewidencja
3. Select a month with tracked sessions
4. Verify monthly breakdown by project and sessions
5. Click "Generate PDF" — verify PDF renders and downloads
6. Upload the signed hours record (upload form)
7. Verify status updates to "submitted"
Expected: Hours record PDF generated, upload accepted, status visible.

## S23 — Admin reviews employee hours

1. Log in as kira (admin)
2. Go to /zarzadzanie/pracownicy
3. Select a month with recorded sessions
4. Click on an employee (e.g. sable)
5. Verify /zarzadzanie/pracownicy/:id shows: hours worked, salary calculation, project breakdown
6. Download employee hours record PDF
7. Toggle hourly rates view → edit a rate → save
Expected: Employee detail shows full breakdown, rates editable, record downloadable.

## S24 — Export sessions as CSV

1. Log in as kira (admin)
2. Go to /zarzadzanie/projekty/:id for a project with sessions
3. Find "Export CSV" button
4. Download — verify CSV contains session rows with user, date, duration, title
5. Repeat for all projects at /czasosledz/projekty/csv
Expected: CSV exported, content correct.

## S25 — Amend account settings

1. Log in as kira (admin)
2. Go to /ustawienia/konto
3. Change display name → save → verify
4. Upload avatar image → verify it appears
5. Toggle marketing consent
Expected: Profile editable, avatar uploadable.

## S26 — Amend organization settings

1. Log in as kira (admin)
2. Go to /ustawienia/organizacja
3. Edit company name, NIP, address → save → verify
4. Edit correspondence email → save → verify
5. Upload org logo → verify it appears
Expected: Org settings saved, logo visible.

## S27 — Security settings

1. Log in as kira (admin)
2. Go to /ustawienia/bezpieczenstwo
3. Initiate email change (new email) → verify confirmation email sent (check /admin/mailbox in dev)
4. Initiate password change → verify success
Expected: Email change flow triggered, password changeable.

## S28 — Validate analysis dashboard

1. Log in as kira (admin)
2. Go to /analiza
3. Select a month with both sales invoices and cost invoices
4. Verify:
   - Income total = sum of sales invoice net amounts for that month
   - Expenses total = sum of cost invoice amounts for that month
   - Net profit = Income − Expenses
5. Assign a tag to an invoice/transaction row
6. Filter by that tag — verify totals update to reflect only tagged items
7. Change month — verify all numbers update
Expected: Totals match ledger data, tag filtering works, month picker updates.

## S29 — Role-based access (invoicing user)

1. Log in as jules (invoicing role)
2. Verify: can see /fakturowanie, can read invoices and transactions
3. Verify: cannot create new sales invoice (no "Nowa faktura" button or blocked)
4. Verify: cannot access /zarzadzanie (redirected or 403)
5. Verify: can access /czasosledz
Expected: Invoicing role has read-only access to finances, no management access.

## S30 — Role-based access (employee user)

1. Log in as sable (employee role)
2. Verify: cannot see /fakturowanie in navbar
3. Verify: can access /czasosledz
4. Verify: cannot access /zarzadzanie
5. Verify: /ustawienia accessible, but organization tab limited
Expected: Employee sees only timetracker.
