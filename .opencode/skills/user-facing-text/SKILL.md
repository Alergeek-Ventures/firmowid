---
name: user-facing-text
description: User-facing text, UI copy, labels, messages, Gettext, and Accent. Use whenever adding or changing any visible text, even when the request is not about translation.
---

# User-Facing Text

Use this skill whenever adding or changing text shown to a user: UI copy, labels,
messages, validation errors, empty states, accessibility text, and similar content.
Write the English source in Gettext and maintain translations in Accent. Do not
leave new UI text untranslated. Exceptions are proper names, user-provided content,
and technical/internal strings that are not user-facing (for example logs).

## Scope and locale behavior

- The managed locale is Polish (`pl`); English is the source language. Current
  tooling and Accent catalog are configured for `en`/`pl`, not arbitrary locales.
- `FirmowidWeb.Core.Gettext` is the backend Gettext module. In a module that
  needs Gettext macros, use the actual backend declaration:

  ```elixir
  use Gettext, backend: FirmowidWeb.Core.Gettext
  ```
- The default Gettext locale is Polish. Do not add browser-locale detection or an
  English UI-language switcher as an assumed part of translating a string.
- User-facing URLs and query parameters remain Polish, independently of UI locale.
- This policy applies to new/changed user-facing text broadly. It does not request
  migrating all existing copy, emails, PDFs, or document language.
- Technical identifiers, proper names, and user-provided text are not translated.

## Write source strings correctly

Use complete, stable English msgids as the source. Keep the meaning in the
Gettext call rather than composing fragments or interpolating values first:

```elixir
use Gettext, backend: FirmowidWeb.Core.Gettext

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
   `mix gettext.extract`. Extraction force-compiles the app and
   updates the tracked `priv/gettext/default.pot`; inspect that diff for the
   intended strings, contexts, and placeholders.
2. Prepare the exact Polish wording, even when the requested wording was
   supplied in Polish. Review the latest native Accent document and preserve
   existing translations and unrelated entries.
3. Before writing translations, sync the extracted latest source to Accent using its
   native authenticated API/official CLI flow, with a credential permitted to
   sync/merge. Preview/peek first when available. Do not assume the repository's
   `accent.json` source glob is itself a sync command: the export helper stages
   the POT in an isolated scratch directory.
4. Populate the Polish entries with context and plural data intact. Verify an
   unversioned/latest Accent export contains the exact values and validate its
   technical structure/placeholders. Editorial translation review belongs in
   Accent. Use this candidate export to validate the uncommitted source; do not
   create a snapshot for the old HEAD as a proxy for the new source.
5. Only after the latest source and translations are complete and validated,
   commit/push if explicitly authorized. CI creates or reuses the snapshot for
   the pushed commit SHA. Fetch that exact SHA and check the compiled/rendered
   result. Do not manually create a snapshot for the uncommitted change.

### Accent structure cautions

- Accent's native document is the source of translation work. Use native
  `gettext` operations (for example `/sync`, `/add-translations`, and `/export`)
  against the project/document path and language, with version selection where
  applicable. Never use a JSON bridge or overwrite a whole document from a
  stale export; preserve contexts, metadata, and untouched translations.
- The current native document path is `gettext/landing-native` (configured as
  `gettext/landing-native/*.pot`). The full extracted source catalog is
  `priv/gettext/default.pot`.
- Polish requires three plural forms. An English POT usually has only two
  `msgstr` slots, so do not upload a raw POT as if it were ready to seed Polish
  plural entries. Preserve Accent's native three-slot plural representation.
- Accent v1.26's contextual-plural export drops `msgctxt`. Prefer an
  uncontextualized plural phrase with distinct English forms until the adapter
  supports it. If contextual plurals are essential, flag the limitation and
  explicitly verify the exported context; never silently lose it.
- The export helper already fixes a specific malformed Polish plural header.
  Do not duplicate that workaround or broadly rewrite/normalize PO headers.

## Pinned catalog snapshots and runtime

- `scripts/accent.exs prepare --version FULL_SHA` only checks whether that
  version exists (creating it if absent) and exports it. It does **not** sync
  changed English source or translate it.
- CI creates/reuses an immutable Accent snapshot for the full pushed commit
  SHA. A newly extracted string must be synced and translated before the push
  that creates its snapshot.
- If a snapshot already exists with stale content, do not edit/delete it, force
  a fallback to latest, or pretend prepare syncs it. Sync and translate the
  latest catalog, then use a new commit SHA for a fresh snapshot; a merge commit
  naturally has a new SHA but is not required as a workaround. Do not amend,
  rewrite, or force-push history without explicit permission.
- `mix translations.fetch [--version FULL_SHA]` exports a pinned version; it
  does not create a snapshot or fall back to latest. Normal builds use the
  pinned artifact; there are no runtime Accent API calls.
- Do not commit generated managed translation PO files, JSON exports, seeds, or
  keys. The tracked POT is source; the downloaded managed Polish PO is
  generated/ignored runtime build input and is compiled before runtime. Preserve
  legacy catalogs and other PO files outside this managed workflow; do not
  delete them as cleanup.

## Credentials and safe operations

- CI's `ACCENT_SNAPSHOT_API_KEY` is for read/export and snapshot creation only;
  it is not permission to sync or merge translations.
- Local/prod Infisical `/app` `ACCENT_API_KEY` is read-only. A translation
  update needs an authorized write-capable development credential; ask for its
  approved location/permissions if unavailable. Do not assume a write key or
  admin permission exists.
- Follow the `infisical-secrets` skill. Never hardcode, print, or share tokens;
  never use `curl -v` or expose authenticated request headers. Avoid tools or
  CLI failures that echo credentials, and do not dump full translation data
  unnecessarily. Do not use production credentials for translation editing.
- Editing the requested feature's text authorizes that scoped translation work;
  it does not authorize unrelated or destructive Accent changes. Preview
  changes and preserve all unrelated content.

## Verification

After editing source, use the repository's actual extraction/export/check flow.
Before commit/push, export the latest unversioned candidate from Accent to the
ignored managed Polish PO and validate it; after CI creates the snapshot, fetch
and validate the exact pushed SHA:

```sh
mix gettext.extract
# Export latest candidate using the authenticated native Accent export flow.
mix translations.check --check-extraction
# After authorized commit/push and CI snapshot creation:
mix translations.fetch --version FULL_SHA
mix translations.check --check-extraction
mix check
```

`mix translations.fetch` defaults to current Git HEAD; specify the full SHA when
checking a particular snapshot. The standalone `elixir scripts/accent.exs
export --version FULL_SHA` also requires the pinned SHA and credentials. Its
local Infisical fallback is disabled in CI, production, and when
`AV_SKIP_INFISICAL` is set. Do not treat `prepare` as a local sync substitute.

Manually inspect the rendered UI, accessibility/context, interpolation, and
plural behavior (especially counts 0, 1, 2, 5, 12, and 22). Keep existing copy
unchanged unless the request includes it. Do not add tests solely for
translation workflow changes unless requested.
