---
name: accent-translations
description: Write Polish and Ukrainian translations into Accent so translation CI passes. Use when translations must reach Accent, when mix translations.check or the CI translation export fails, or when a Gettext plural error appears.
---

# Accent Translations

How translated text reaches a green build: English source in code, Polish and
Ukrainian values written into Accent, and CI exporting the current Accent catalog,
validating it against the POT and marking it with the commit SHA. On `main`, CI
publishes that validated catalog as `<sha>.tar.gz` in the `translation-snapshots`
GitHub release, which the deployment build installs.

For how to *write* source msgids, contexts, and placeholders, see
`user-facing-text`. For secret handling rules, see `infisical-secrets`.

## Rules

1. **Never upload the extracted POT to Accent, and never run `accent sync` or
   `accent sync --add-translations`.** It maps translations onto the English
   single-plural shape and permanently destroys Polish's third form, which
   Accent cannot recreate, and it removes every key missing from the uploaded
   file. New keys are added only through the peeked passive sync in step 3;
   the other exception is the repair below.
2. **Never use machine translation.** Accent can machine translate (Google
   Translate and DeepL); this project deliberately does not. Polish is written
   by humans and the approved wording comes from Figma.
3. **Always write all three Polish plural slots**, non-empty, even when slot 1
   and slot 2 hold the same value, which is correct for nouns like `%{count}
   dni`. A two-slot entry is always wrong.
4. **Write values with `correctTranslation`, then verify** by re-reading the
   record and exporting. Import endpoints accept uploads and leave records
   empty.
5. **Write the values before CI needs them.** Every CI run exports the current
   Accent catalog and fails when a POT entry lacks a Polish or Ukrainian value.
   A published `main` snapshot is immutable: it never changes for its commit.

## Polish plural forms

| Slot | Counts | Example (`%{count} employee`) |
| --- | --- | --- |
| `msgstr[0]` | exactly 1 | `%{count} pracownik` |
| `msgstr[1]` | 2–4, 22–24, … (not teens) | `%{count} pracownicy` |
| `msgstr[2]` | 0, 5+, 12–14, 25+ | `%{count} pracowników` |

A correct entry keeps the placeholder in every slot, and the three values need
not differ: the paucal and genitive-plural forms are identical for some nouns.
`mix translations.check` requires the slot keys to be exactly `[0, 1, 2]`, every
value non-empty, and placeholders preserved per slot.

```po
msgid "%{count} bank account"
msgid_plural "%{count} bank accounts"
msgstr[0] "%{count} konto bankowe"
msgstr[1] "%{count} konta bankowe"
msgstr[2] "%{count} kont bankowych"
```

## Ukrainian plural forms

Ukrainian also has three forms, with a different rule: slot 0 for counts ending
in 1 except 11 (1, 21, 31…), slot 1 for counts ending in 2–4 except 12–14, slot 2
for the rest (`%{count} рахунок`, `%{count} рахунки`, `%{count} рахунків`). The
same checks apply to `priv/gettext/uk/LC_MESSAGES/default.po`.

## Credential

Use the write-capable developer credential from Infisical: environment `dev`,
path `/dev`. It can read, export and write translations; it cannot add languages.

```sh
ACCENT_KEY=$(infisical secrets get ACCENT_API_KEY \
  --domain https://infisical.alergeek.me --env=dev --path="/dev" --plain)
```

Never print it or write it into a tracked file; unset it after use.

## Procedure

Write the translations (step 3) before pushing, or rerun CI afterwards: the PR's
translation job exports whatever Accent holds when it runs.

### 1. Extract the English source and commit

```sh
mix gettext.extract
```

Read the `priv/gettext/default.pot` diff and note every new msgid, its context,
its placeholders, and whether it is plural. Commit and push only when explicitly
authorized.

### 2. Prepare the Polish text

- Ask the user for the wording and wait for it. Do not invent copy for visible
  product text.
- Read the approved Polish from Figma only when the user asks for it. The Figma
  MCP server is configured here but is expensive; never reach for it on your
  own.
- Draft translations only when the user explicitly asks, then present them with
  the English source and where each string renders and get approval before
  pushing. All three plural forms must be human-written and match the counts
  they serve.

### 3. Write the Polish values into Accent

CI only exports the `gettext/landing-native` catalog.

1. Read the catalog's records (read-only GraphQL query) and resolve the exact
   stored keys. Accent normalizes keys — contexts appear as
   `msgid.__CONTEXT__<context>` — and a stored key can differ from the Gettext
   source. If any key is ambiguous, stop and resolve it before writing
   anything; a partial batch is worse than none.
2. Write each Polish value:

```graphql
mutation {
  correctTranslation(id: "TRANSLATION_RECORD_ID", text: "Wartość po polsku") {
    errors
    translation {
      id
      correctedText
    }
  }
}
```

   `correctTranslation` sets the final text; `updateTranslation` only proposes.
   Always pass the human-approved Polish from step 2.
3. Re-read the records. `correctedText` must be non-empty; `isTranslated: true`
   with empty `correctedText` counts as untranslated.
4. A brand-new identity has no record yet. Create it through the API, then
   re-run steps 1–3:
   - Export the current English master of `gettext/landing-native` (`GET
     /export` with `language=en`, no `version`) and append the new msgids with
     empty `msgstr`. Building on Accent's own export keeps every existing key
     and plural shape; the extracted POT does not.
   - `POST /sync/peek` with `language=en`, `document_format=gettext`,
     `document_path=gettext/landing-native`, `sync_type=passive` and that file.
     Continue only when every operation is `new` (or `renew` for a key Accent
     removed earlier). Any `remove`, `update` or `conflict` means the file is
     wrong: stop.
   - Re-export right before syncing and confirm the master did not change, then
     `POST /sync` with the same parameters. Passive sync still removes keys
     absent from the file, so never send anything but this union.

Do not use the panel's PO import, `/add-translations`, or `--add-translations`.
Uploading a patched file with the panel's sync button is a different operation
and is only for the repair in
[Damaged plural forms](references/damaged-plurals.md).

Call the API with `curl`; Accent rejects some HTTP clients with 403 before
checking the key.

### 4. Verify with the current catalog

```sh
ACCENT_API_KEY="$ACCENT_KEY" mix translations.fetch --latest && mix translations.check --check-extraction
```

`--latest` exports the current Accent catalog, projects it onto the local POT,
validates Polish and Ukrainian and installs both catalogs marked with `HEAD`; it
fails on the first missing value, context, plural form or placeholder. This is
exactly what the CI translation job does.

### 5. Rerun CI

- Use **Re-run all jobs**. **Re-run failed jobs** reuses the successful
  translation job and its old PO artifact, so the quality job downloads the same
  stale catalog and fails identically.
- The translation job feeds `Build and Test`, `Elixir Quality Checks` and the
  Docker check, so refreshing only one is not enough.

## Failure modes

| Symptom | Cause | Fix |
| --- | --- | --- |
| `POT/PO identity mismatch ... missing from PO: N` or `missing Ukrainian translation` in the CI translation job | Accent has no value for a new source string | Write Polish and Ukrainian (step 3), then **Re-run all jobs** |
| `No published translation snapshot for <sha>` in a deployment build or `mix translations.fetch` | The commit is not on `main`, or its CI did not publish (e.g. a Dependabot push) | Use `mix translations.fetch --latest` locally; production deploys with the next `main` commit |
| `Gettext.PluralFormError: plural form 2 is required for locale "pl"` during compile, extraction, or tests | Accent holds only two forms for that string | See [Damaged plural forms](references/damaged-plurals.md) |
| `missing Polish translation in default: "<msgid>"` | The Accent record exists but is empty; PO import left it empty | Write it with `correctTranslation` and verify |
| HTTP 401 on a write | A read-only credential was used | Use the Infisical `dev` `/dev` credential |

## Damaged plural forms

A sync can remove Polish's third plural form, and Accent cannot recreate it. The
only recovery is exporting the file, patching the damaged entries, and uploading
it back, which replaces the whole document and is dangerous: never do it without
reading [the procedure](references/damaged-plurals.md) first.