# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

- **Primary: the owner or administrator of a small Polish service company**:
  a sole trader (JDG) or a team of roughly 6–20 people, often in IT. They run
  invoicing, KSeF, bank reconciliation, projects, counterparties and the team
  themselves, without a dedicated back office. Their job: get invoices out,
  know what has been paid, and know what the team's work really costs.
- **Secondary: the owner's employees.** They record working time, request
  leave and file business trips (delegations). They often do this from a
  phone.

## Product Purpose

Firmowid runs the day-to-day administration of a small company in one place:
sales and cost invoices synchronized with KSeF, bank accounts connected and
matched against invoices, time tracking with the statutory hours record,
employees, projects, counterparties, leave, delegations and analysis.
Success means the owner stops keeping spreadsheets and can see, without
manual assembly, what was invoiced, what was paid, and what the team costs.

## Positioning

- **All in one:** invoices with KSeF, the bank with transaction matching, and
  team time and cost are connected data in a single tool, not separate
  products or integrations.
- **AI-native operation:** the company can be operated from an AI assistant
  through Firmowid's MCP server and ChatGPT app (`lib/firmowid_mcp`), not
  only through the web UI.
- **Open source and self-hostable:** the code is published under AGPL-3.0
  (`LICENSE`) and the company can run it on its own infrastructure ("Self-host,
  open source (AGPL-3.0)" in the pricing table). This is a brand commitment and
  a reason to trust the product with financial data.
- **Against Polish competitors:** iFirma, inFakt and wFirma offer similar
  online invoicing and accounting services for small companies. They are
  closed SaaS products and each covers one slice; Firmowid connects invoices,
  the bank and the team in one open product.

## Operating Context

- Polish legal and accounting reality: KSeF (the national e-invoicing system),
  net prices in PLN, the statutory hours record, leave types, and delegations.
- Owners work in recurring monthly cycles: issue sales invoices, collect cost
  invoices from the KSeF inbox, match bank transactions, close the hours
  record, and review the month.
- Employees make short, task-shaped visits: log time, request leave, file a
  delegation, often on mobile.
- Some users work through ChatGPT or another MCP client instead of the
  browser. Embedded widgets render inside those hosts.

## Capabilities and Constraints

- Phoenix LiveView application. Areas: invoicing (sales, cost inbox, shared
  invoice links, PDFs), KSeF connection, bank sync and transaction matching,
  time tracker and hours record, management (employees, counterparties,
  projects, contracts, documents), delegations, payroll, analysis,
  organization and invites, settings, billing, admin.
- Plans on the landing page: Free (KSeF invoicing, no card, no trial),
  Entrepreneur (PLN 29/month net), and Company (PLN 149/month net, for service
  companies of 6–20 people). Annual billing is 20% cheaper
  (`lib/firmowid_web/landing/components/pricing.ex`).
- **Polish market only.** The UI is in Polish, and user-facing URLs, query
  keys and readable values are Polish. No other languages or markets are
  planned.
- **Employee flows must work well on mobile** (time, leave, delegations).
  Owner-side finance flows have no confirmed device priority.
- User-facing text goes through Gettext and Accent (see the
  `user-facing-text` skill). Prefer Elixir components over `.heex` templates.

## Brand Commitments

- Name: **Firmowid**. Built by Alergeek Ventures (linked from the landing
  page).
- Open-source (AGPL) status is shown publicly on the landing page and must
  stay truthful.
- Landing voice is direct and plain-spoken. It addresses the owner as "Ty"
  ("Prowadzisz firmę.", "Uczciwy cennik. Bez gwiazdek.").

## Evidence on Hand

- Landing claims in `lib/firmowid_web/landing/components/hero.ex`: 29
  supported banks and fintechs, a 15-minute average onboarding time, and two
  years of history tied to Alergeek Ventures.
- Assets in `priv/static/images/landing/` include characters, ChatGPT, Claude
  and MCP marks, and product preview frames. Bank and invoice badges are under
  `priv/static/images/`.
- Seeded demo organization for screenshots and manual testing (`/development`).
- No customer testimonials, case studies or press are present in the
  repository. Do not invent them.

## Product Principles

1. **Connected over separate:** a feature earns its place by linking invoices,
   money and team work, not by standing alone.
2. **Owner without a back office:** assume no accountant is in the loop. Make
   the state of the company obvious and the next action clear.
3. **Polish reality, first-class:** KSeF, PLN net prices, the statutory hours
   record and Polish terminology are the product's native vocabulary, not
   localization.
4. **Operable by people and by AI:** each core capability should make sense
   both in the UI and through the assistant integrations.
5. **Trust through openness:** open code and honest, fine-print-free pricing
   are part of the product, so copy must never overclaim.

## Accessibility & Inclusion

No formal standard (such as WCAG AA) has been set as a requirement. Employee
flows must be comfortable on phones.
