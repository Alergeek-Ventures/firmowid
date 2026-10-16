---
name: accent-translations
description: Write Polish translations into Accent and freeze a pinned snapshot for a commit so translation CI passes. Use when translations must reach Accent, when a snapshot is needed for a commit or PR head, or when mix translations.check or a Gettext plural error fails.
---

# Accent Translations

How Polish text reaches a green build: English source in code, Polish values
written into Accent, an immutable snapshot frozen for one commit SHA, and CI
exporting exactly that snapshot.

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
5. **Never create a snapshot before Accent holds the translations**, and
   validate the latest catalog before freezing one. Snapshots are immutable, so
   a premature one is permanently wrong for its commit.

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

## Credential

Use the write-capable developer credential from Infisical: environment `dev`,
path `/dev`. It can read, export, write translations, and create snapshots.

```sh
ACCENT_KEY=$(infisical get ACCENT_API_KEY \
  --domain https://infisical.alergeek.me --env=dev --path="/dev" --plain)
```

Never print it or write it into a tracked file; unset it after use.

## Procedure

Steps 3 and 4 happen **after** the code change is committed and pushed, because
the snapshot must be tagged with a SHA that already exists.

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

### 4. Verify with the latest catalog export

Export the mutable catalog, project it onto the current POT, and validate it
before freezing anything:

```sh
ROOT="$(pwd)" && SCRATCH="$(mktemp -d)" &&
  mkdir -p "$SCRATCH/gettext/landing-native" &&
  cp priv/gettext/default.pot "$SCRATCH/gettext/landing-native/default.pot" &&
  (cd "$SCRATCH" && ACCENT_API_KEY="$ACCENT_KEY" accent export --config "$ROOT/accent.json") &&
  CANDIDATE_PO="$SCRATCH/exports/pl/default.po" mix run --no-start -e '
candidate = System.fetch_env!("CANDIDATE_PO") |> File.read!() |> Expo.PO.parse_string!()
pot = Expo.PO.parse_file!("priv/gettext/default.pot")
File.write!("priv/gettext/pl/LC_MESSAGES/default.po",
  pot |> Firmowid.Translations.catalog_for_source(candidate, "default") |> Expo.PO.compose())
' && mix translations.check --check-extraction
rm -rf "$SCRATCH"
```

The local candidate has no `# Accent version:` marker, so the check reports
`Accent snapshot: unmarked`; only CI requires that marker. Running
`mix translations.fetch` afterwards replaces it with a pinned catalog, which is
how to reproduce CI locally.

### 5. Freeze a snapshot for the pushed commit

```sh
ACCENT_API_KEY="$ACCENT_KEY" elixir scripts/accent.exs prepare --version "$(git rev-parse HEAD)"
```

- Requires the full 40-character SHA of the pushed commit and is idempotent: it
  reuses an existing snapshot and creates one only when the export returns 404.
  It never syncs or translates; it freezes whatever Accent holds right now, so
  step 4 must pass first.
- On `main`, the workflow does this automatically for pushes not made by
  Dependabot. Doing it locally is for PR heads and for repairing a missing
  `main` snapshot.
- A snapshot that already exists with stale or invalid content cannot be
  repaired. Freeze a new one for a new commit SHA.

### 6. Rerun CI

- Use **Re-run all jobs**. **Re-run failed jobs** reuses the successful
  translation-preparation job and its old PO artifact, so the quality job
  downloads the same stale catalog and fails identically.
- A rerun never picks up a newer PR head: runs are pinned to the head SHA at
  event time. A snapshot for today's head SHA is only used by a fresh run for
  that SHA — close/reopen the PR to trigger one, or push a new commit and
  create a snapshot for that new SHA.
- The preparation job feeds both `Build and Test` and `Elixir Quality Checks` →
  `Validate translation catalogs`, so refreshing only one is not enough.

## Failure modes

| Symptom | Cause | Fix |
| --- | --- | --- |
| `POT/PO identity mismatch ... missing from PO: N` with an old `Accent snapshot: <sha>` | The selected snapshot predates the new source strings | Push Polish, snapshot the PR head SHA (or land a `main` SHA), then **Re-run all jobs** |
| `No Accent snapshot for main commit <sha>` | The fallback SHA has no snapshot, e.g. a Dependabot push to `main` skipped creation | Run `prepare` for that SHA locally, or push again as a human actor |
| `Gettext.PluralFormError: plural form 2 is required for locale "pl"` during compile, extraction, or tests | Accent holds only two forms for that string | See [Damaged plural forms](references/damaged-plurals.md) |
| `missing Polish translation in default: "<msgid>"` | The Accent record exists but is empty; PO import left it empty | Write it with `correctTranslation` and verify |
| HTTP 401 on a write | A read-only credential was used | Use the Infisical `dev` `/dev` credential |

## Damaged plural forms

A sync can remove Polish's third plural form, and Accent cannot recreate it. The
only recovery is exporting the file, patching the damaged entries, and uploading
it back, which replaces the whole document and is dangerous: never do it without
reading [the procedure](references/damaged-plurals.md) first.