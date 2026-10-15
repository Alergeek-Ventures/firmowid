---
name: secret-scanning
description: Use when adding or moving credential-like literals (passwords, tokens, DSNs, database URLs, keys) in code, tests, fixtures, seeds or config, or when the Betterleaks CI job fails.
---

# Secret scanning

- CI scans the full git history with Betterleaks (`secret-scan` job in
  `.github/workflows/elixir-build-and-test.yml`). Run the same scan locally
  before pushing a change that adds or moves credential-like literals:

  ```bash
  betterleaks git . --validation=false --redact --no-banner --no-color
  ```

  `betterleaks` comes from the devenv shell.
- A real secret must not be committed. Move it to Infisical (see the
  `infisical-secrets` skill) instead of suppressing the finding.
- For a reviewed false positive (test fixtures, seed passwords, local
  development defaults), suppress it in the same commit that introduces it:
  - the finding's fingerprint (`commit:path:rule:line`, printed by the scan)
    in `.betterleaksignore`, or
  - a narrow rule in `.betterleaks.toml` that matches both the file and the
    exact value, with a comment saying why the value is not a credential.
- Never disable a rule or ignore a whole path.
