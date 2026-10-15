# Damaged plural forms: cause and recovery

Read this before touching Accent's source file. The recovery uploads a patched
copy of the whole document.

## Cause

Uploading the English source to Accent maps translations onto the English
shape, and English has a single plural form, so Polish's third form is removed.
It cannot be brought back the ordinary way:

- `correctTranslation` only updates records that already exist.
- PO import discards `msgstr[2]`, even with a correct `nplurals=3` header.
- The panel has no control for adding a plural form.

The only workaround is to export, patch, and upload the file. Accent offers no
guard against the cause, so prevention is the rule in the skill: never upload the
extracted POT.

## Detection

Export the Polish catalog and count slots. Every plural must export `msgstr[0]`,
`msgstr[1]`, and `msgstr[2]`. A two-slot entry surfaces as:

```text
Gettext.PluralFormError: plural form 2 is required for locale "pl" but is missing
```

during compilation, extraction, or tests.

## Recovery

1. A human logs in to the Accent admin panel and opens project Firmowid → files
   → `gettext/landing-native`.
2. Export the file. Patch only the damaged plural entries by adding an empty
   third slot, leaving `msgid` and `msgid_plural` untouched:

   ```po
   msgid "%{count} employee"
   msgid_plural "%{count} employees"
   msgstr[0] ""
   msgstr[1] ""
   msgstr[2] ""
   ```

3. Upload the patched file with the panel's sync button.
4. Write the Polish third form, which is writable again only after this.
5. Export Polish, confirm every plural has slots `[0, 1, 2]`, run
   `mix translations.check`.
6. Commit, then freeze a new snapshot for that commit SHA. Existing snapshots
   stay broken.

## Why this is dangerous

The uploaded file replaces the whole document, so anything edited between the
export and the upload is silently reverted. A colleague's translation made in
that window would be lost.

- Export and upload back to back.
- Tell the user the round trip is happening and why.
- Change nothing except the plural slots.
- Re-export afterwards to confirm no other entry changed.
- If more than a few minutes pass between export and upload, or anyone else may
  be editing translations, stop and ask the user first.

Two things that look wrong but are not: slots 1 and 2 may legitimately hold the
same Polish value (`%{count} dni` serves both 2–4 and 5+), and the patched file
must keep empty slots empty — filling them would push unreviewed Polish.