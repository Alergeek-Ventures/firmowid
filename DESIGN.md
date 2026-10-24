---
name: Firmowid
description: Application UI for running a small Polish company's invoices, money and team in one place.
colors:
  white: "#FFFFFF"
  black: "#000000"
  orangeText: "#8B3F13"
  orangeBg: "#E6D7CE"
  greyButtonBg: "#DDDDDD"
  darkGrey: "#4E4E4E"
  lightGreyBg: "#F5F5F5"
  transparent: "transparent"
  offwhite: "#F0F0F0"
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
  orange-100: "#F0EAE6"
  orange-200: "#E6D7CE"
  orange-300: "#E9C3AC"
  orange-400: "#DEA785"
  orange-500: "#D28F67"
  orange-500-landing: "#D2936D"
  orange-600: "#9C5D39"
  orange-700: "#8B3F13"
  orange-800: "#662905"
  orange-900: "#4E2005"
  greenText: "#475E45"
  greenBg: "#D0E6CE"
  redText: "#A22A2A"
  redBg: "#E6CECE"
  blueText: "#354E4E"
  blueBg: "#CEE6E6"
  green-100: "#ECF5EB"
  green-200: "#D0E6CE"
  green-300: "#B9DDB5"
  green-400: "#9ECD9B"
  green-500: "#89BD85"
  green-600: "#699166"
  green-700: "#475E45"
  green-800: "#2D432B"
  green-900: "#142113"
  red-100: "#FBF4F4"
  red-200: "#E6CECE"
  red-300: "#E5BDBD"
  red-400: "#D69F9F"
  red-500: "#C96E6E"
  red-600: "#BB4A4A"
  red-700: "#A22A2A"
  red-800: "#891515"
  red-900: "#610404"
  oranger-100: "#F0EAE6"
  oranger-200: "#E6D7CE"
  oranger-300: "#E9C3AC"
  oranger-400: "#EAAA84"
  oranger-500: "#E28B58"
  oranger-600: "#A5582B"
  oranger-700: "#8B3F13"
  oranger-800: "#77330C"
  oranger-900: "#4E2005"
  turquoise-100: "#EDF5F5"
  turquoise-200: "#CEE6E6"
  turquoise-300: "#AEDEDE"
  turquoise-400: "#8BC9C9"
  turquoise-500: "#6AAAAA"
  turquoise-600: "#578383"
  turquoise-700: "#455E5E"
  turquoise-800: "#2F4343"
  turquoise-900: "#1D3232"
typography:
  caps-sm:
    fontFamily: "Lexend, ui-sans-serif, system-ui, sans-serif"
    fontSize: "11px"
    fontWeight: 500
    lineHeight: 1.6
  xs:
    fontFamily: "Lexend, ui-sans-serif, system-ui, sans-serif"
    fontSize: "12px"
    fontWeight: 500
    lineHeight: 1.4
  sm:
    fontFamily: "Lexend, ui-sans-serif, system-ui, sans-serif"
    fontSize: "14px"
    fontWeight: 400
    lineHeight: 1.5
  base:
    fontFamily: "Lexend, ui-sans-serif, system-ui, sans-serif"
    fontSize: "16px"
    fontWeight: 400
    lineHeight: 1.25
  h5:
    fontFamily: "Lexend, ui-sans-serif, system-ui, sans-serif"
    fontSize: "18px"
    fontWeight: 500
    lineHeight: 1.4
  lg:
    fontFamily: "Lexend, ui-sans-serif, system-ui, sans-serif"
    fontSize: "20px"
    fontWeight: 600
    lineHeight: 1.4
  xl:
    fontFamily: "Lexend, ui-sans-serif, system-ui, sans-serif"
    fontSize: "23px"
  "2xl":
    fontFamily: "Lexend, ui-sans-serif, system-ui, sans-serif"
    fontSize: "27px"
    fontWeight: 600
    lineHeight: 1.25
  "3xl":
    fontFamily: "Lexend, ui-sans-serif, system-ui, sans-serif"
    fontSize: "40px"
rounded:
  sm: "0.25rem"
  md: "0.375rem"
  lg: "0.5rem"
  xl: "0.75rem"
  2xl: "1rem"
components:
  button-primary-cost:
    backgroundColor: "{colors.orange-700}"
    textColor: "{colors.white}"
    rounded: "{rounded.lg}"
    padding: "8px 11px"
    height: "44px"
  button-primary-cost-hover:
    backgroundColor: "{colors.orange-800}"
  button-primary-sales:
    backgroundColor: "{colors.turquoise-700}"
    textColor: "{colors.white}"
    rounded: "{rounded.lg}"
    padding: "8px 11px"
    height: "44px"
  button-primary-sales-hover:
    backgroundColor: "{colors.turquoise-800}"
  button-secondary-cost:
    backgroundColor: "{colors.orange-200}"
    textColor: "{colors.orange-900}"
    rounded: "{rounded.lg}"
    padding: "8px 11px"
    height: "44px"
  button-secondary-sales:
    backgroundColor: "{colors.turquoise-200}"
    textColor: "{colors.turquoise-900}"
    rounded: "{rounded.lg}"
    padding: "8px 11px"
    height: "44px"
  button-neutral-special:
    backgroundColor: "{colors.black}"
    textColor: "{colors.white}"
    rounded: "{rounded.lg}"
    padding: "8px 11px"
    height: "44px"
  button-neutral-special-hover:
    backgroundColor: "{colors.grey-700}"
  button-neutral-tertiary:
    backgroundColor: "{colors.grey-700}"
    textColor: "{colors.white}"
    rounded: "{rounded.lg}"
    padding: "8px 11px"
    height: "44px"
  button-outline:
    backgroundColor: "{colors.white}"
    textColor: "{colors.grey-900}"
    rounded: "{rounded.lg}"
    padding: "8px 11px"
    height: "44px"
  button-outline-hover:
    backgroundColor: "{colors.grey-200}"
  button-destructive:
    backgroundColor: "{colors.red-200}"
    textColor: "{colors.red-700}"
    rounded: "{rounded.lg}"
    padding: "8px 11px"
    height: "44px"
  button-small:
    rounded: "{rounded.md}"
    padding: "6px 8px"
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
    rounded: "{rounded.lg}"
    padding: "6px 12px"
    typography: "{typography.base}"
  card:
    backgroundColor: "{colors.white}"
    rounded: "{rounded.md}"
    padding: "24px"
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
few places that group a self-contained record. A heavy black navigation bar
frames the workspace like the spine of a ledger. The typeface is Lexend
throughout, a wide, highly legible sans that keeps dense financial tables
readable and friendly.

This document covers the application UI only. The marketing landing page is
an expressive surface with its own hand-drawn vocabulary and is deliberately
out of scope here.

The frontmatter is the source of truth for colours, the text size scale and
radii. Its keys are the Tailwind token names (`orange-700` is `bg-orange-700`,
`sm` under typography is `text-sm`). After editing it, run `mix design.tokens`
to regenerate `assets/css/design-tokens.css`; `mix check` fails while that
file is out of date. Fonts, spacing and animations live in
`assets/css/theme.css`.

**Key Characteristics:**
- Colour has a fixed meaning: rust means costs, teal means sales. Neutral work uses black and graphite.
- Warm, tactile components with pastel tonal fills (secondary buttons, pills, badges).
- Flat by default: white surfaces on the `grey-100` canvas separated by tone or a 1px `grey-200` line. Cards with a shadow are the exception.
- Lexend everywhere. Dense, 14px-led body text with medium weight for emphasis.
- Gentle 8px corners on controls, 6px on small controls and cards, full pills for filters and toggles.

## Colors

A warm, earthy ledger palette: two directional accents on a neutral grey
field, plus moss and brick for outcomes.

### Primary
- **Burnt Rust** (`orange-700`): the colour of costs and purchases. Cost-invoice headers and accents, cost amounts in entry tables, cost-side primary buttons, and cost search results. Darker steps (`orange-800`, `orange-900`) serve hover, active and the text on rust tints.
- **Rust Tint / Rust Wash** (`orange-200`, `orange-100`): pastel backgrounds for cost-side secondary buttons, cost invoice source badges, cost amount cells and cost invoice detail headers.

### Secondary
- **Deep Sea Teal** (`turquoise-700`): the colour of sales and revenue. Sales-invoice accents, income rows, sales-side primary buttons, and date-picker selection. Deeper steps handle hover, active and text on teal tints.
- **Sea Teal Tint / Wash** (`turquoise-200`, `turquoise-100`): pastel backgrounds for sales-side secondary buttons, sales and KSeF source badges, and income cells.

### Tertiary
- **Moss** (`green-700` on `green-200`): positive outcomes such as matched transactions and success states and buttons.
- **Brick** (`red-700` on `red-200`): errors, destructive actions and validation. Destructive buttons are a brick-tint fill with brick text, never a solid red block.

### Neutral
- **Ink** (`black`): the navigation bar, the neutral "special" button and the back-link disc.
- **Charcoal** (`grey-900`): the strongest body text and labels on light surfaces.
- **Graphite** (`grey-700`): the workhorse text colour (by far the most used), neutral tertiary buttons, active filter chips and icon buttons.
- **Pebble** (`grey-500`): secondary and meta text, placeholders and quiet labels.
- **Stone Line** (`grey-200`): the default 1px border on cards, inputs and outline buttons, the neutral secondary fill, and outline-button hover.
- **Field Paper** (`grey-50`): input and select backgrounds, so fields read as slightly recessed paper on white cards.
- **Canvas** (`grey-100`): the application background behind all content.
- **Surface** (`white`): cards, modals, popovers and tables.

### Named Rules
**The Two Sides of the Ledger Rule.** Rust appears only where the subject is a cost or purchase, and teal only where it is a sale or revenue. On an invoice-related screen, the accent follows the invoice's side (`accent={if(@is_cost_invoice, do: "orange", else: "turquoise")}`). Never use rust or teal decoratively.

**The Neutral Action Rule.** Actions that belong to neither side (saving settings, inviting an employee, adding a project) use the black `special` or graphite `tertiary` button, not rust. Note that `<.button variant="primary">` still defaults to the rust accent in code. New neutral actions must pick `special` or `tertiary` explicitly.

**The Pastel Before Solid Rule.** Status and secondary emphasis use the tint plus deep-text pair (for example, `orange-200` with `orange-900`). Solid accent fills are reserved for the one primary action in a view.

## Typography

**Display Font:** Lexend (with ui-sans-serif, system-ui, sans-serif)
**Body Font:** Lexend (same stack)

**Character:** One wide, open, highly legible sans for everything. Lexend's
generous letterforms keep amounts, NIP numbers and dense tables calm, while
weight (medium and semibold) carries hierarchy instead of a second family.

### Hierarchy
The frontmatter `typography` keys are the Tailwind text sizes; only `fontSize`
becomes a CSS token. Weight and line height describe how each role is set.

- **Headline** (`text-2xl`, 27px, 600): page and section titles, used sparingly.
- **Title** (`text-lg`, 20px, 600): card and panel titles, modal headings.
- **Subtitle** (`text-h5`, 18px, 500): sub-panel headings and invoice section headers.
- **Body Large** (`text-base`, 16px): form controls and big buttons, set tight (1.25) so controls stay compact.
- **Body** (`text-sm`, 14px): the default for the whole app. Tables, lists, descriptions and small buttons are 14px.
- **Label** (`text-xs`, 12px, 500): meta text, table annotations and tooltip text.
- **Caps** (`text-caps-sm`, 11px, 500): uppercase micro-labels, table column headers and navigation items. Table headers and main navigation are set in uppercase.
- `text-xl` (23px) and `text-3xl` (40px) are larger steps for headings and big figures.

### Named Rules
**The Weight Carries Hierarchy Rule.** Emphasis comes from medium (500) and semibold (600) Lexend, not from colour or a second typeface. Bold (700) is for figures that must jump out, such as totals and big numbers.

## Layout

The app is a single centred column on the grey canvas. A sticky black navbar
66px tall (108px in the Management area, which adds a sub-navigation row)
sits above `main`, which pads 16px on mobile, 24px from `sm`, and 32px from
`lg`. Wide data views cap around 1140px (`max-w-284`) or 1280px (`max-w-7xl`).
Forms and dialogs use narrow columns (`max-w-md` to `max-w-3xl`).

Spacing follows a 4px rhythm. 8px and 16px gaps dominate, with 12px and 24px
as secondary steps, and 32px or more only between major sections. Card
interiors use 24px padding (16px on compact cards).

Below 768px the main navigation links and account cluster hide, and a
hamburger menu takes over. Employee-facing flows (time tracking, leave,
delegations) must remain fully usable at phone widths.

## Elevation & Depth

The app is flat by default. The canvas is `grey-100`, content sits on white
surfaces, and inputs recede slightly with `grey-50` field paper. Regions are
separated by tone, spacing or a 1px `grey-200` line, not by shadow. Cards are
used only in some places: where a self-contained record or settings group
must read as one object, such as the panels on management detail pages
(`FirmowidWeb.Management.Components.Card`) and admin settlement panels.
Shadows belong to those cards and to overlays that float above the page.

### Shadow Vocabulary
- **Card** (`shadow` on `Card`, `shadow-[0px_1px_6px_0px_rgba(0,0,0,0.1)]` on admin panels): only on the cards described above.
- **Overlay** (`shadow-lg` plus a 1px graphite/10 ring): modals, popovers, dropdowns and toasts.
- **Error tooltip** (`box-shadow: 0 2px 8px rgba(0,0,0,0.15)`): field-level error bubbles.

### Named Rules
**The Flat by Default Rule.** A surface at rest has no shadow. Lists, tables, forms, toolbars and page sections sit flat on the canvas or on white, separated by tone or a `grey-200` line. Reach for a card only when the content is one self-contained record, and never nest cards.

**The Paper on Canvas Rule.** A surface rises by being whiter than what is under it. Reach for `shadow-lg` only for things that float: modals, popovers, dropdowns and toasts.

## Shapes

Gentle, consistent curvature:
- 8px (`rounded-lg`) on big buttons, inputs, selects, textareas and admin panels.
- 6px (`rounded-md`) on small buttons, cards (`Card`), modals and menu items.
- 3px (`rounded-[3px]`) for checkboxes, radio squares, icon buttons and invoice source badges.
- Full pills (`rounded-full`) for filter chips, toggle switches and avatars.

Borders are 1px `grey-200`. Dashed borders mark drop zones and empty
placeholders.

## Components

### Buttons
Warm and tactile: flat fills, no gradients, quick 100ms colour transitions.
- **Shape:** gently rounded. Big buttons are 44px tall with an 8px radius; small buttons use a 6px radius at 14px text. Icons are 20px (big) or 16px (small).
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
- **Style:** 1px grey-200 border, grey-50 background, 8px radius, 16px text set tight, 6px by 12px padding. Placeholders and empty selects use pale grey text.
- **Focus:** the border deepens to a mid grey. Some search fields use a 2px teal focus ring.
- **Error:** the border turns red and a brick error bubble with an exclamation icon appears.
- **Checkbox / Radio:** 16px squares with a 3px radius and graphite stroke.
- **Switch:** a 38×24 pill. The grey track fills rust or teal when on, depending on the side it controls.

### Navigation
- **Style:** a full-width black bar with off-white bold "Firmowid" wordmark on the left and centred uppercase 14px links with icons. Inactive links sit at 50% opacity, the active one at 90%, and hover reaches full opacity.
- **Account cluster:** on the right, opening a black dropdown whose items highlight with graphite/50.
- **Mobile:** below 768px the links collapse into a hamburger menu.

### Modals
A white surface with a 6px radius, generous 40px padding, overlay shadow plus
a faint ring, over a black/60 scrim. A low-contrast close "×" sits top right.

## Do's and Don'ts

### Do:
- **Do** colour by ledger side: rust (`orange-*` scale) for costs and purchases, teal (`turquoise-*` scale) for sales and revenue, everywhere from badges to switches.
- **Do** use the black `special` or graphite `tertiary` button for actions that are neither cost nor sale.
- **Do** prefer pastel tint plus deep-text pairs for secondary actions, pills and statuses.
- **Do** keep surfaces flat: white on the `grey-100` canvas, separated by tone or a `grey-200` line.
- **Do** keep body text at 14px Lexend in graphite, and lift emphasis with weight, not colour.
- **Do** use the 8px radius for controls, 6px for small controls and cards, and pills only for filters, toggles and avatars.
- **Do** change colours and text sizes in the DESIGN.md frontmatter and run `mix design.tokens`.
- **Do** go through `FirmowidUI.Components.Button` and its variants instead of hand-rolled button classes.

### Don't:
- **Don't** use rust or teal decoratively or for neutral actions. Their meaning is the ledger side.
- **Don't** rely on the default `variant="primary"` for neutral actions; it renders rust.
- **Don't** introduce new zinc, gray or rose Tailwind palettes. Legacy fields still use them; new work uses the grey, red and green scales from this file's frontmatter.
- **Don't** wrap lists, tables or forms in shadowed cards, and never nest cards. `shadow-lg` belongs to floating overlays.
- **Don't** edit `assets/css/design-tokens.css` by hand.
- **Don't** add a second typeface to the app UI. Josefin Sans and the handwriting face belong to the landing page.
- **Don't** use solid red or green blocks for destructive or success buttons. Use the tint fills.
