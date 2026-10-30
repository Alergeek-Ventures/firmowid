---
name: user-facing-text
description: User-facing text, UI copy, labels, messages, Gettext, and Accent. Use whenever adding or changing any visible text, even when the request is not about translation.
---

# User-Facing Text

Use this skill whenever adding or changing text shown to a user: UI copy,
labels, messages, validation errors, empty states, accessibility text, and
similar content. Write the English source in Gettext and maintain translations
in Accent. Do not leave new UI text untranslated. Exceptions are proper names,
user-provided content, and technical/internal strings that are not user-facing
(for example logs).

Writing Polish and Ukrainian into Accent and translation CI failures are
documented in `accent-translations`.

## Scope and locale behavior

- English is the source language; the translated locales are Polish (`pl`, the
  default) and Ukrainian (`uk`). `Firmowid.Translations.locales/0` lists them and
  every new or changed string needs a value in both. Users choose the interface
  language from the list in `FirmowidWeb.Infrastructure.Plugs.Locale.languages/0`.
- `Firmowid.Gettext` is the backend Gettext module. In a module that needs
  Gettext macros, use the actual backend declaration:

  ```elixir
  use Gettext, backend: Firmowid.Gettext
  ```

- The default Gettext locale is Polish. Do not add browser-locale detection as
  an assumed part of translating a string.
- User-facing URLs and query parameters remain Polish, independently of UI
  locale.
- This policy applies to new/changed user-facing text broadly. It does not
  request migrating all existing copy, emails, PDFs, or document language.
- Technical identifiers, proper names, and user-provided text are not
  translated.

## Write source strings correctly

Use complete, stable English msgids as the source. Keep the meaning in the
Gettext call rather than composing fragments or interpolating values first:

```elixir
use Gettext, backend: Firmowid.Gettext

gettext("Save")
gettext("Invoice %{number}", number: invoice.number)
pgettext("billing period", "Monthly")
ngettext("%{count} invoice", "%{count} invoices", count)
```

- Use named interpolation bindings and retain placeholders in translations.
- Use `pgettext/2` when context is needed to disambiguate a short or ambiguous
  phrase. Use `ngettext/3` for count-dependent singular/plural phrases.
- Do not split a phrase into translatable word fragments or interpolate values
  into a string before calling Gettext.
- A changed msgid is a new translation identity. Do not edit a translation under
  an old msgid or reuse an unrelated msgid to avoid translation work.
- Keep non-user-facing technical strings out of translation catalogs.

## Required source-to-Polish workflow

Follow these steps in order when changing user-facing text:

1. Write the complete English source in Gettext and run extraction:
   `mix gettext.extract`. Extraction force-compiles the app and updates the
   tracked `priv/gettext/default.pot`; inspect that diff for the intended
   strings, contexts, and placeholders.
2. Write the Polish and Ukrainian wording yourself (or with subagents), unless
   the user supplied their own copy, e.g. from Figma or a design, which is used
   verbatim. Review the latest native Accent document, reuse existing terms and
   preserve existing translations and unrelated entries.
3. Write the Polish and Ukrainian values into Accent following
   `accent-translations` (CI fails until Accent holds them), then commit/push if
   explicitly authorized. Never upload the extracted POT to Accent: it
   rebuilds the Polish plural entries with the English two-form shape.

### Accent structure cautions

- Accent's native document is the source of translation work. Never use a JSON
  bridge or overwrite a whole document from a stale export; preserve contexts,
  metadata, and untouched translations.
- The current native document path is `gettext/landing-native` (configured as
  `gettext/landing-native/*.pot`). The full extracted source catalog is
  `priv/gettext/default.pot`.
- Polish requires three plural forms. An English POT usually has only two
  `msgstr` slots, so do not upload a raw POT as if it were ready to seed Polish
  plural entries. Do not use Accent's built-in machine translation; the
  translations are written by the agent (see `accent-translations`).
- Accent v1.26's contextual-plural export drops `msgctxt`. Prefer an
  uncontextualized plural phrase with distinct English forms until the adapter
  supports it. If contextual plurals are essential, flag the limitation and
  explicitly verify the exported context; never silently lose it.
- The export helper already fixes a specific malformed Polish plural header. Do
  not duplicate that workaround or broadly rewrite/normalize PO headers.

## Catalog snapshots and runtime

- Every CI run exports the current Accent catalog with
  `elixir scripts/accent.exs snapshot --version FULL_SHA`, validates `pl` and `uk`
  against the POT and marks the PO files with that SHA. A PR passes only when
  Accent already holds its new strings in both languages.
- On `main`, CI publishes the validated catalog as `FULL_SHA.tar.gz` in the
  `translation-snapshots` GitHub release; the deployment build installs it with
  `elixir scripts/accent.exs export --version FULL_SHA`. A published snapshot is
  immutable; reruns of that commit reuse it. Accent versions are not used.
- `mix translations.fetch --latest` reproduces the CI export locally;
  `mix translations.fetch [--version FULL_SHA] [--fallback-version FULL_SHA]`
  installs a published snapshot, falling back only when the requested one is not
  published (HTTP 404). Normal builds compile the installed catalogs; there are no
  runtime Accent calls.
- Do not commit generated managed translation PO files, JSON exports, seeds, or
  keys. The tracked POT is source; the downloaded managed Polish and Ukrainian POs are
  generated/ignored runtime build input and is compiled before runtime. Preserve
  legacy catalogs and other PO files outside this managed workflow; do not
  delete them as cleanup.

## Credentials and safe operations

- Accent credential handling is documented in `accent-translations`. A
  translation update needs an authorized write-capable development credential;
  ask for its approved location/permissions if unavailable.
- Follow the `infisical-secrets` skill. Never hardcode, print, or share tokens;
  never use `curl -v` or expose authenticated request headers. Avoid tools or
  CLI failures that echo credentials, and do not dump full translation data
  unnecessarily. Do not use production credentials for translation editing.
- Editing the requested feature's text authorizes that scoped translation work;
  it does not authorize unrelated or destructive Accent changes. Preview changes
  and preserve all unrelated content.

## Verification

After editing source, run `mix gettext.extract`, write the Polish and Ukrainian
values into Accent (`accent-translations`) and push. CI validates extraction and
both catalogs; do not run `mix check` or Dialyzer locally for this.

The local Infisical fallback for `ACCENT_API_KEY` is disabled in CI, production,
and when `AV_SKIP_INFISICAL` is set.

Manually inspect the rendered UI, accessibility/context, interpolation, and
plural behavior (especially counts 0, 1, 2, 5, 12, and 22). Keep existing copy
unchanged unless the request includes it. Do not add tests solely for
translation workflow changes unless requested.
