# KSeF FA(3) reference schemas

These are pinned test inputs, not a runtime download cache. Invoice rendering
tests validate against the official FA(3) schema without requiring gov.pl to be
available. Retrieved on 2026-10-10 from these HTTPS URLs:

- `schemat.xsd`: https://crd.gov.pl/wzor/2025/06/25/13775/schemat.xsd
- `KodyKrajow_v10-0E.xsd`: https://crd.gov.pl/xml/schematy/dziedzinowe/mf/2022/01/05/eD/DefinicjeTypy/KodyKrajow_v10-0E.xsd
- `ElementarneTypyDanych_v10-0E.xsd`: https://crd.gov.pl/xml/schematy/dziedzinowe/mf/2022/01/05/eD/DefinicjeTypy/ElementarneTypyDanych_v10-0E.xsd
- `StrukturyDanych_v10-0E.xsd`: https://crd.gov.pl/xml/schematy/dziedzinowe/mf/2022/01/05/eD/DefinicjeTypy/StrukturyDanych_v10-0E.xsd

The files are unmodified. The test helper resolves `schemaLocation` references
to local filenames through erlsom's include callback. Download SHA-256 hashes:

```text
b646b6b525f51adf1bb2545f111fc8ca6e7aa6dd2f98948f1667d3695c06d958  schemat.xsd
1d41a1b3184188f2d20a51d3afde26204dda182ec5dacf018204dcc9870dc644  KodyKrajow_v10-0E.xsd
8a531cb181d3e298d11b28766655ae91fee2d7851440095932ffc82137ed2be1  ElementarneTypyDanych_v10-0E.xsd
1137ce6e3c11c2b9ef3f05e4e72d6dcd6b4fa94908ea558f2ba15de0259bb2aa  StrukturyDanych_v10-0E.xsd
```

Update these fixtures deliberately when the supported invoice schema changes:
download the official sources, verify XML and checksums, update this provenance,
and run `invoice_renderer_test.exs`.
