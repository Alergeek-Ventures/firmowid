---
name: Firmowid
description: Application UI for running a small Polish company's invoices, money and team in one place.
colors:
  white: "#FFFFFF"
  black: "#000000"
  transparent: "transparent"
  grey-50: "#FAFAFA"
  grey-100: "#F5F5F5"
  grey-200: "#DDDDDD"
  grey-300: "#CCCCCC"
  grey-400: "#B5B5B5"
  grey-500: "#949494"
  grey-600: "#707070"
  grey-700: "#4E4E4E"
  grey-800: "#303030"
  grey-900: "#1A1A1A"
  grey-950: "#121212"
  rust-50: "#FEF9F7"
  rust-100: "#F0EAE6"
  rust-200: "#E6D7CE"
  rust-300: "#E9C3AC"
  rust-400: "#DEA785"
  rust-500: "#D28F67"
  rust-600: "#9C5D39"
  rust-700: "#8B3F13"
  rust-800: "#662905"
  rust-900: "#4E2005"
  rust-950: "#220900"
  teal-50: "#F6FBFB"
  teal-100: "#EDF5F5"
  teal-200: "#CEE6E6"
  teal-300: "#AEDEDE"
  teal-400: "#8BC9C9"
  teal-500: "#6AAAAA"
  teal-600: "#578383"
  teal-700: "#455E5E"
  teal-800: "#2F4343"
  teal-900: "#1D3232"
  teal-950: "#051515"
  moss-50: "#F6FCF5"
  moss-100: "#ECF5EB"
  moss-200: "#D0E6CE"
  moss-300: "#B9DDB5"
  moss-400: "#9ECD9B"
  moss-500: "#89BD85"
  moss-600: "#699166"
  moss-700: "#475E45"
  moss-800: "#2D432B"
  moss-900: "#142113"
  moss-950: "#0A1509"
  brick-50: "#FEF9F8"
  brick-100: "#FBF4F4"
  brick-200: "#E6CECE"
  brick-300: "#E5BDBD"
  brick-400: "#D69F9F"
  brick-500: "#C96E6E"
  brick-600: "#BB4A4A"
  brick-700: "#A22A2A"
  brick-800: "#891515"
  brick-900: "#610404"
  brick-950: "#2A0002"
typography:
  caps-sm:
    fontFamily: "Geist, ui-sans-serif, system-ui, sans-serif"
    fontSize: "11px"
    fontWeight: 500
    lineHeight: 1.6
  xs:
    fontFamily: "Geist, ui-sans-serif, system-ui, sans-serif"
    fontSize: "12px"
    fontWeight: 500
    lineHeight: 1.4
  sm:
    fontFamily: "Geist, ui-sans-serif, system-ui, sans-serif"
    fontSize: "14px"
    fontWeight: 400
    lineHeight: 1.5
  base:
    fontFamily: "Geist, ui-sans-serif, system-ui, sans-serif"
    fontSize: "16px"
    fontWeight: 400
    lineHeight: 1.25
  h5:
    fontFamily: "Geist, ui-sans-serif, system-ui, sans-serif"
    fontSize: "18px"
    fontWeight: 500
    lineHeight: 1.4
  lg:
    fontFamily: "Geist, ui-sans-serif, system-ui, sans-serif"
    fontSize: "20px"
    fontWeight: 600
    lineHeight: 1.4
  xl:
    fontFamily: "Geist, ui-sans-serif, system-ui, sans-serif"
    fontSize: "23px"
  "2xl":
    fontFamily: "Geist, ui-sans-serif, system-ui, sans-serif"
    fontSize: "27px"
    fontWeight: 600
    lineHeight: 1.25
  "3xl":
    fontFamily: "Geist, ui-sans-serif, system-ui, sans-serif"
    fontSize: "40px"
rounded:
  sm: "0.25rem"
  md: "0.25rem"
  lg: "0.25rem"
  xl: "0.25rem"
  2xl: "0.25rem"
components:
  button-primary-cost:
    backgroundColor: "{colors.rust-700}"
    textColor: "{colors.white}"
    rounded: "{rounded.sm}"
    padding: "6px 10px"
    height: "36px"
  button-primary-cost-hover:
    backgroundColor: "{colors.rust-800}"
  button-primary-sales:
    backgroundColor: "{colors.teal-700}"
    textColor: "{colors.white}"
    rounded: "{rounded.sm}"
    padding: "6px 10px"
    height: "36px"
  button-primary-sales-hover:
    backgroundColor: "{colors.teal-800}"
  button-secondary-cost:
    backgroundColor: "{colors.rust-200}"
    textColor: "{colors.rust-900}"
    rounded: "{rounded.sm}"
    padding: "6px 10px"
    height: "36px"
  button-secondary-sales:
    backgroundColor: "{colors.teal-200}"
    textColor: "{colors.teal-900}"
    rounded: "{rounded.sm}"
    padding: "6px 10px"
    height: "36px"
  button-neutral-special:
    backgroundColor: "{colors.black}"
    textColor: "{colors.white}"
    rounded: "{rounded.sm}"
    padding: "6px 10px"
    height: "36px"
  button-neutral-special-hover:
    backgroundColor: "{colors.grey-700}"
  button-neutral-tertiary:
    backgroundColor: "{colors.grey-700}"
    textColor: "{colors.white}"
    rounded: "{rounded.sm}"
    padding: "6px 10px"
    height: "36px"
  button-outline:
    backgroundColor: "{colors.white}"
    textColor: "{colors.grey-900}"
    rounded: "{rounded.sm}"
    padding: "6px 10px"
    height: "36px"
  button-outline-hover:
    backgroundColor: "{colors.grey-200}"
  button-destructive:
    backgroundColor: "{colors.brick-200}"
    textColor: "{colors.brick-700}"
    rounded: "{rounded.sm}"
    padding: "6px 10px"
    height: "36px"
  button-small:
    rounded: "{rounded.sm}"
    padding: "6px 8px"
    height: "30px"
    typography: "{typography.sm}"
  filter-chip:
    backgroundColor: "{colors.grey-100}"
    textColor: "{colors.grey-700}"
    rounded: "9999px"
    padding: "4px 8px"
    typography: "{typography.sm}"
  filter-chip-active:
    backgroundColor: "{colors.grey-700}"
    textColor: "{colors.white}"
  input-field:
    backgroundColor: "{colors.grey-50}"
    textColor: "{colors.grey-900}"
    rounded: "{rounded.sm}"
    padding: "6px 12px"
    typography: "{typography.base}"
  card:
    backgroundColor: "{colors.white}"
    rounded: "{rounded.sm}"
    padding: "24px"
  sidebar:
    backgroundColor: "{colors.black}"
    textColor: "{colors.white}"
    width: "256px"
  navbar:
    backgroundColor: "{colors.black}"
    textColor: "{colors.white}"
    height: "66px"
---

# Design System: Firmowid

## Overview

**Creative North Star: "The Craftsman's Ledger"**

Firmowid is a well-kept account book on a craftsman's workbench. It is orderly
and dependable, but made by people for people. Surfaces are warm rather than
clinical. Neutrals are true greys on a soft paper-grey canvas, and colour is
reserved for the two sides of the ledger: rust for money going out (costs and
purchases) and deep sea teal for money coming in (sales and revenue). When you
see colour, it tells you which side of the book you are looking at.

Components are warm and tactile. Secondary actions and status pills use
pastel tonal fills instead of hard outlines. Corners are gently rounded
(8px on most controls). The page is flat by default: white surfaces sit on the
grey canvas through tonal contrast, and a shadowed card is used only in the
few places that group a self-contained record. A heavy black sidebar
frames the workspace like the spine of a ledger. The typeface is Geist
throughout, a plain, compact sans that keeps dense financial tables calm and
businesslike. Lexend survives in the "Firmowid" wordmark, where it keeps
the brand recognisable, and on the landing page (see below).

This document covers the application UI only. The marketing landing page is
an expressive surface with its own hand-drawn vocabulary and is deliberately
out of scope here. It is set in Lexend (`font-landing`); only its previews of
real product screens switch back to Geist (`font-sans`), so they look like the app.

The frontmatter is the source of truth for colours, the text size scale and
radii. Its keys are the Tailwind token names (`rust-700` is `bg-rust-700`,
`sm` under typography is `text-sm`). After editing it, run `mix design.tokens`
to regenerate `assets/css/design-tokens.css`; `mix check` fails while that
file is out of date. Fonts, spacing and animations live in
`assets/css/theme.css`.

The structure of this system (foundations first, then a catalog of primitives
with their variants and states, rendered live) follows the
[Intent design system](https://intentapp.dev/design-system) as a reference.
Only the structure is borrowed: every value, colour and component here is
Firmowid's own.

**Key Characteristics:**
- Colour has a fixed meaning: rust means costs, teal means sales. Neutral work uses black and graphite.
- Warm, tactile components with pastel tonal fills (secondary buttons, pills, badges).
- Flat by default: white surfaces on the `grey-100` canvas separated by tone or a 1px `grey-200` line. Cards with a shadow are the exception.
- Geist everywhere, Lexend only in the wordmark. Dense, 14px-led body text with medium weight for emphasis.
- Gentle 8px corners on controls, 6px on small controls and cards, full pills for filters and toggles.

## Colors

A warm, earthy ledger palette: two directional accents on a neutral grey
field, plus moss and brick for outcomes.

Five palettes (`grey`, `rust`, `teal`, `moss`, `brick`) share one step naming,
50–950. Steps 100–900 are the colours the product was designed with; 50 and
950 extend each scale (an OKLCH extrapolation) for washes and deepest text. Step
700 is the brand anchor of each palette. Use 50–300 for tints and washes,
600–950 for text and hover/active states.

### Primary
- **Burnt Rust** (`rust-700`): the colour of costs and purchases. Cost-invoice headers and accents, cost amounts in entry tables, cost-side primary buttons, and cost search results. Darker steps (`rust-800`, `rust-900`) serve hover, active and the text on rust tints.
- **Rust Tint / Rust Wash** (`rust-200`, `rust-100`): pastel backgrounds for cost-side secondary buttons, cost invoice source badges, cost amount cells and cost invoice detail headers.

### Secondary
- **Deep Sea Teal** (`teal-700`): the colour of sales and revenue. Sales-invoice accents, income rows, sales-side primary buttons, and date-picker selection. Deeper steps handle hover, active and text on teal tints.
- **Sea Teal Tint / Wash** (`teal-200`, `teal-100`): pastel backgrounds for sales-side secondary buttons, sales and KSeF source badges, and income cells.

### Tertiary
- **Moss** (`moss-700` on `moss-200`): positive outcomes such as matched transactions and success states and buttons.
- **Brick** (`brick-700` on `brick-200`): errors, destructive actions and validation. Destructive buttons are a brick-tint fill with brick text, never a solid red block.

### Neutral
- **Ink** (`black`): the sidebar and the phone top bar, the neutral "special" button and the back-link disc.
- **Charcoal** (`grey-900`): the strongest body text and labels on light surfaces.
- **Graphite** (`grey-700`): the workhorse text colour (by far the most used), neutral tertiary buttons, active filter chips and icon buttons.
- **Pebble** (`grey-500`): secondary and meta text, placeholders and quiet labels.
- **Stone Line** (`grey-200`): the default 1px border on cards, inputs and outline buttons, the neutral secondary fill, and outline-button hover.
- **Field Paper** (`grey-50`): input and select backgrounds, so fields read as slightly recessed paper on white cards.
- **Canvas** (`grey-100`): the application background behind all content.
- **Surface** (`white`): cards, modals, popovers and tables.

### Named Rules
**The Two Sides of the Ledger Rule.** Rust appears only where the subject is a cost or purchase, and teal only where it is a sale or revenue. On an invoice-related screen, the accent follows the invoice's side (`accent={if(@is_cost_invoice, do: "rust", else: "teal")}`). Never use rust or teal decoratively.

**The Neutral Action Rule.** Actions that belong to neither side (saving settings, inviting an employee, adding a project) use the black `special` or graphite `tertiary` button, not rust. Note that `<.button variant="primary">` still defaults to the rust accent in code. New neutral actions must pick `special` or `tertiary` explicitly.

**The Pastel Before Solid Rule.** Status and secondary emphasis use the tint plus deep-text pair (for example, `rust-200` with `rust-900`). Solid accent fills are reserved for the one primary action in a view.

## Typography

**Display Font:** Geist (with ui-sans-serif, system-ui, sans-serif)
**Body Font:** Geist (same stack)
**Wordmark Font:** Lexend (`font-logo`), for the "Firmowid" wordmark only

**Character:** One plain, compact sans for everything. Geist's narrow,
even letterforms fit more into dense tables and keep amounts, NIP numbers
and forms businesslike, while weight (medium and semibold) carries hierarchy
instead of a second family. Its tabular figures (`tabular-nums`) keep
amounts aligned in columns.
The mono stack (`font-mono`, system monospace) is only for raw identifiers a
user may compare character by character: IBANs, NIPs, OAuth scopes and URIs.

### Hierarchy
The frontmatter `typography` keys are the Tailwind text sizes; only `fontSize`
becomes a CSS token. Weight and line height describe how each role is set.

- **Headline** (`text-2xl`, 27px, 600): page and section titles, used sparingly.
- **Title** (`text-lg`, 20px, 600): card and panel titles, modal headings.
- **Subtitle** (`text-h5`, 18px, 500): sub-panel headings and invoice section headers.
- **Body Large** (`text-base`, 16px): form controls and big buttons, set tight (1.25) so controls stay compact.
- **Body** (`text-sm`, 14px): the default for the whole app. Tables, lists, descriptions and small buttons are 14px.
- **Label** (`text-xs`, 12px, 500): meta text, table annotations and tooltip text.
- **Caps** (`text-caps-sm`, 11px, 500): uppercase micro-labels, table column headers and the sidebar's layer heading. Table headers and that heading are set in uppercase.
- `text-xl` (23px) and `text-3xl` (40px) are larger steps for headings and big figures.

Line heights come from the Tailwind scale through the size shorthand
(`text-sm/snug`, `text-base/tight`). Dense copy and labels use `snug` (1.375);
the landing's 1.35 from the original Figma was folded into it.

### Named Rules
**The Weight Carries Hierarchy Rule.** Emphasis comes from medium (500) and semibold (600) Geist, not from colour or a second typeface. Bold (700) is for figures that must jump out, such as totals and big numbers.

**The Wordmark Only Rule.** In the app, Lexend (`font-logo`) sets the "Firmowid" wordmark and nothing else: the sidebar head, the navbar logo, the landing navigation and footer, and the email header. Headings, empty states and modals stay in Geist.

## Layout

The app is a black sidebar on the left and a single centred column on the grey
canvas. The sidebar is 256px wide and collapses to a 56px column of icons;
`main` keeps its left margin in step with it and pads 16px on mobile, 24px
from `sm`, and 32px from `lg`. Onboarding pages (`focused`) have no sidebar.
Wide data views cap around 1140px (`max-w-284`) or 1280px (`max-w-7xl`).
Forms and dialogs use narrow columns (`max-w-md` to `max-w-3xl`).

Spacing follows a 4px rhythm. 8px and 16px gaps dominate, with 12px and 24px
as secondary steps, and 32px or more only between major sections. Card
interiors use 24px padding (16px on compact cards).

Below 768px the sidebar is hidden and a sticky black top bar, 66px tall, shows
the wordmark and a menu (hamburger) button, which slides the sidebar in over
the page at full width. Page content must fit 390px without horizontal
scrolling, because any overflow widens the layout viewport and pushes the menu
button off-screen. Employee-facing flows (time tracking,
leave, delegations) must be fully usable at phone widths.

## Elevation & Depth

The app is flat by default. The canvas is `grey-100`, content sits on white
surfaces, and inputs recede slightly with `grey-50` field paper. Regions are
separated by tone, spacing or a 1px `grey-200` line, not by shadow. Cards are
used only in some places: where a self-contained record or settings group
must read as one object, such as the panels on management detail pages
(`FirmowidWeb.Management.Components.Card`) and admin settlement panels.
Shadows belong to those cards and to overlays that float above the page.

### Shadow Vocabulary
- **Card** (`shadow-card`, a token in `assets/css/theme.css`): only on the cards described above.
- **Overlay** (`shadow-small`, Figma's "Small shadow": `0 1px 6px` black at 2%, plus a 1px grey-200 border, or a graphite/10 ring on modals and toasts): modals, popovers, dropdown menus and toasts, with a 4px radius. The ring does the separating; the shadow only softens the edge. It replaces the older `shadow-lg`, which some overlays outside the shared primitives still use.
- **Error tooltip** (`box-shadow: 0 2px 8px rgba(0,0,0,0.15)`): field-level error bubbles.

### Named Rules
**The Flat by Default Rule.** A surface at rest has no shadow. Lists, tables, forms, toolbars and page sections sit flat on the canvas or on white, separated by tone or a `grey-200` line. Reach for a card only when the content is one self-contained record, and never nest cards.

**The Paper on Canvas Rule.** A surface rises by being whiter than what is under it. Reach for the overlay shadow (`shadow-small`) only for things that float: modals, popovers, dropdowns and toasts.

## Motion

Motion is short and only confirms what the user just did: something opened,
appeared or changed. Nothing loops or moves on its own, and every animation
stops under `prefers-reduced-motion` (`motion-reduce:transition-none`,
`motion-reduce:animate-none!`, and the hooks skip it).

- **Colour change** (100ms): hover and press states of buttons.
- **Dropdown entrance** (in `dropdown_panel_styles/0` and the menu; the session
  edit popover uses `dropdown_styles/0` in `FirmowidWeb.Timetracker.Components.Session`): 150ms ease-out, scale 95% to
  100% and opacity 0 to 1 through `@starting-style` (`starting:`), so it plays
  every time the element is shown, whatever shows it. Set the origin to the side
  it unfolds from (`origin-top`, `origin-top-right`). Used by the project, work
  mode and workplace lists and the session edit popover. Closing has no
  animation.
- **Revealed fields** (`list_enter/0` in `FirmowidWeb.Timetracker.Views.Index`):
  200ms ease-out, rising 8px from opacity 0, for content that opens in place,
  such as the manual time fields. It leaves no classes behind, as a lingering
  translate would anchor sticky headers and popovers.
- **State colour** (300ms ease-out): a value changing meaning, such as the
  time tracker's idle counter darkening from `grey-300` to `grey-500` once the
  form can start.
- **Changed number** (`t-digit-pop-in` in `assets/css/shared.css`, played by the
  `NumberPopIn` hook): 500ms, each digit rising 8px out of a 2px blur with a
  slight overshoot, 70ms apart. With `data-changed-only` only the digits that
  differ from the previous value move, which marks what a save changed (the
  session time in the time tracker list); without it all digits play (landing
  pricing).

## Focus

Every focusable element shows the same keyboard focus: a 2px solid outline,
offset 2px, in `--focus-ring` (`grey-900`). This is one base rule in
`assets/css/app.css`; components do not add their own focus colours. Dark
surfaces (the sidebar with its account menu, the phone top bar, the cookie
banner) set `[--focus-ring:var(--color-white)]` so the outline stays visible.
Text fields signal focus with their border (`grey-700`) instead of an outline.

**The One Focus Rule.** Never remove focus (`outline-none`, `focus:ring-0`) without the replacement above, and never colour it by ledger side.

## Control Sizes

- **Big** (36px, `h-9`): the default button size and page-level actions; 10px side padding, 16px medium text.
- **Small** (30px, `h-7.5`): toolbar, table, card and row actions; 8px side padding, 14px medium text, 16px icon, 6px between icon and text.
- **Icon only**: a 36px or 30px square with the icon centred (`icon_button`).
- Heights are fixed, not grown from padding. 44px touch targets are only for phone screens where an employee flow needs them.
- **Chip** (24px, `h-6`): status chips and compact toggles.
- Text fields are about 34px tall today; when a field sits in a row with buttons, match the button size explicitly.

## Shapes

One radius for everything with corners: 4px. Buttons, inputs, selects,
checkboxes, cards, modals, tiles, menus, tooltips and status badges all use it.
Every `rounded` token (`sm` to `2xl`) is 4px, so `rounded-sm` is the one to
write in new code; do not add arbitrary radii like `rounded-[3px]`.

Full pills (`rounded-full`) are only for toggle switches, avatars, filter chips
and round counters. The marketing landing page keeps its own scaled radii.

Borders are 1px `grey-200`. Dashed borders mark drop zones and empty
placeholders.

## Icons

New code uses [Lucide](https://lucide.dev) through the `lucide_icons` package
(`<Lucideicons.search />`). Heroicons (`<.icon name="hero-…" />`) are the older
set and remain only in existing code until it is touched; do not add new ones,
and do not mix both libraries inside one component. Icons are 24px in big
buttons and 16px in small ones; an icon that is the only content of a
control needs an accessible label (`icon_button` requires one).

## Components

Every primitive below is imported in all web views and shown with its variants
on `/development/design-system` (development only). Reach for these before
writing markup by hand; a hand-rolled copy of one of them is drift.

### Where components live

- **Web only:** `FirmowidWeb.DesignSystem.Components.*`
  (`lib/firmowid_web/design_system/components/`). Modules start with
  `use FirmowidUI, :html` (the web `:html` entrypoint imports them, which would
  be circular) and are imported for all views in `FirmowidWeb.html_helpers/0`.
- **Web and MCP:** when a feature is shown both in the browser and in an MCP
  widget, its shared UI is the common denominator and lives in
  `FirmowidUI.Components.*` (`lib/firmowid_ui/`), like `Button`, `Link` and
  `Inputs`. `FirmowidUI` never depends on `FirmowidWeb` or `FirmowidMcp`; move a
  web primitive there when its first MCP consumer appears.
- **Feature-specific UI** stays in the feature (`components/` next to its
  views) until a second feature needs the same thing.

### Adding a primitive

1. Extract only what repeats with the same intent (three or more hand-written
   copies), and only the variants those copies actually use.
2. Keep the class format Credo enforces: one literal first, then `*_styles`
   helpers, conditionals and assigns. Accessible names and visible text come
   from attributes the caller fills with `gettext`; primitives contain no copy.
3. Add it to the catalog view (`FirmowidWeb.Development.Views.DesignSystem`) and
   to the table below, then migrate the existing copies.

| Need | Primitive | Notes |
|---|---|---|
| Action | `FirmowidUI.Components.Button.button` / `Link.link kind="button"` | Variants and sizes below. |
| Icon-only action | `icon_button` | `label` is required (accessible name and tooltip); a square, small 30px, big 36px. |
| Row or record actions | `menu` + `menu_item` | Kebab trigger by default; `tone="danger"` for destructive items. Two variants, list and dropdown (see Menus and Dropdowns). |
| Status | `badge` | 24px pill; tones `neutral`, `success`, `danger`, `cost`, `sales`. |
| Inline notice | `alert` | Tones `neutral`, `success`, `danger`; `danger` uses `role="alert"`. Toasts stay for transient feedback. |
| Nothing to show | `empty_state` | Dashed placeholder: icon, title, one sentence, the action that fills it; `small` (24px icon, 14px text) inside panels and lists. |
| Sibling views of a page | `tabs` | Underline links; the selected view lives in the URL. |
| Scope of a list | `segmented_control` | Pills, one active (for example active and archived). |
| Label with value or control | `field_row` | `stacked` for forms, `inline` for detail and settings panels. |
| Search | `search_field` | Grey field with a leading magnifier (`search_icon`, the Figma lens, not Lucide's `search`); small 32px (20px icon), medium 36px (20px icon, beside big buttons) or big 40px (24px icon); a 2px teal-300 border while focused. A short list may hide it behind a square tertiary button that widens (300ms) into a 240px medium field with focus, and narrows back when left empty. |
| Supplementary hint | `tooltip` | Tippy with one delay; never the only place for essential information. |
| One self-contained record | `card` + `card_header` | The flat-by-default exception; never nested. |

### Buttons
Warm and tactile: flat fills, no gradients, quick 100ms colour transitions.
- **Shape:** 4px corners and fixed heights. Big buttons are 36px tall (10px side padding, 16px medium text, 24px icon); small buttons are 30px tall (8px side padding, 14px medium text, 16px icon). Icon and text sit 6px apart.
- **Primary (directional):** a solid rust fill for cost-side actions and a solid teal fill for sales-side actions, with white text. Hover and active step to the deeper shades.
- **Secondary (directional):** a pastel tint with deepest-shade text (rust or teal), or a grey tint for neutral.
- **Special / Tertiary (neutral):** a black fill (hover graphite) or a graphite fill (hover charcoal) with white text. Use these for actions that belong to neither ledger side.
- **Outline / Ghost:** grey-200 border or no border, with charcoal text and a grey-200 hover fill. Ghost inverts to a graphite fill on press.
- **Destructive / Success:** a brick-tint or moss-tint fill with deep text, not solid red or green.
- **Loading:** buttons dim to 75% opacity during LiveView click and submit loading.

### Chips (filters)
- **Style:** pill-shaped, canvas fill, grey-200 border, graphite medium 14px text.
- **State:** active chips invert to a graphite fill with white text. Hover deepens the fill to grey-200.

### Invoice Source Badge (signature)
A small rounded tile (36×24 or 48×32, 3px radius) whose fill names the ledger
side (rust tint for costs, teal tint for sales and KSeF sales) and whose icon
names the source (KSeF, external, drafted in Firmowid). This is the clearest
expression of the Two Sides of the Ledger Rule.

### Cards / Containers
- **When:** only for a self-contained record or settings group; everything else stays flat (see Elevation & Depth).
- **Component:** `FirmowidWeb.Management.Components.Card` (`rounded-md bg-white p-6 shadow`) with `card_header`.
- **Background:** white surface on the canvas.
- **Internal Padding:** 24px standard, 16px compact.

### Inputs / Fields
- **Style:** one style for every field (`FirmowidUI.Components.Inputs.input/1`): 1px grey-200 border, white background (grey-50 for selects), 8px radius, 16px text set tight, 6px by 12px padding, about 34px tall. Placeholders and selects showing their prompt use pale grey text.
- **Focus:** the border deepens to `grey-700` (see Focus).
- **Error:** the border turns red and a brick error bubble with an exclamation icon appears.
- **Checkbox / Radio:** 16px squares with a 3px radius and graphite stroke.
- **Switch:** a 38×24 pill. The grey track fills rust or teal when on, depending on the side it controls.

### Menus and Dropdowns
One primitive (`FirmowidWeb.DesignSystem.Components.Menu`) in two variants.
- **Shared:** 1px grey-200 border, 4px radius, the overlay shadow (`shadow-small`), 4px padding. Items are 36px tall with 12px side padding and 14px text; hover fills them grey-200.
- **List** (`menu` + `menu_item`, actions from a button): white, as wide as its content, 4px under the button.
- **Dropdown** (`dropdown_panel_styles/0` + `dropdown_option/1`, options of a select field): grey-50 like the field, 4px under its trigger. Under a full-width field it is as wide as the field (the project in the time tracker form); under a compact trigger it is as wide as its longest option. The selected option (`aria-selected`) has a check on the right.
- **In use:** the time tracker's project and work mode pickers, in the session rows and in the form.

### Navigation
- **Sidebar:** a black column with the "Firmowid" wordmark and the collapse button on top, then the layer switch (company or the member's own), the inbox and the places of the current layer. Rows are 32px tall with an 18px icon and the label in `grey-300`; the current page sits on a `grey-900` fill. Collapsed, only the icons stay and a label shows as a tooltip.
- **Account:** feedback and the account button sit at the bottom; the account button opens a black menu with the organization switcher, settings and logging out, whose items highlight with graphite/50.
- **Mobile:** below 768px the sticky top bar's menu button slides the sidebar in over the page at full width (see Layout).

### Modals
A white surface with a 6px radius, generous 40px padding, overlay shadow plus
a faint ring, over a black/60 scrim. A low-contrast close "×" sits top right.

## Do's and Don'ts

### Do:
- **Do** colour by ledger side: rust (`rust-*` scale) for costs and purchases, teal (`teal-*` scale) for sales and revenue, everywhere from badges to switches.
- **Do** use the black `special` or graphite `tertiary` button for actions that are neither cost nor sale.
- **Do** prefer pastel tint plus deep-text pairs for secondary actions, pills and statuses.
- **Do** keep surfaces flat: white on the `grey-100` canvas, separated by tone or a `grey-200` line.
- **Do** keep body text at 14px Geist in graphite, and lift emphasis with weight, not colour.
- **Do** use the 8px radius for controls, 6px for small controls and cards, and pills only for filters, toggles and avatars.
- **Do** change colours and text sizes in the DESIGN.md frontmatter and run `mix design.tokens`.
- **Do** go through `FirmowidUI.Components.Button` and its variants instead of hand-rolled button classes.

### Don't:
- **Don't** use rust or teal decoratively or for neutral actions. Their meaning is the ledger side.
- **Don't** rely on the default `variant="primary"` for neutral actions; it renders rust.
- **Don't** introduce new zinc, gray or rose Tailwind palettes. Legacy fields still use them; new work uses the grey, red and green scales from this file's frontmatter.
- **Don't** wrap lists, tables or forms in shadowed cards, and never nest cards. The overlay shadow belongs to floating overlays.
- **Don't** edit `assets/css/design-tokens.css` by hand.
- **Don't** add a second typeface to the app UI or use `font-logo` outside the wordmark. The handwriting face belongs to the landing page only.
- **Don't** use solid red or green blocks for destructive or success buttons. Use the tint fills.
