---
name: formatting-commits
description: Use when formatting many files, upgrading a formatter, or separating formatting changes in a PR to preserve git blame.
---

# Formatting commits

- Keep bulk formatter output in a separate `style(format): ...` commit. Never
  mix dependency updates, fixes, tests or configuration changes into an ignored
  commit.
- Review the diff: formatter-generated rewrites must preserve behavior. Keep any
  semantic changes outside the formatting commit, even if a tool generated them.
- Wait until the formatting PR is merged before updating
  `.git-blame-ignore-revs`. Rebase merge changes hashes, so use the formatting
  commit's full, final hash from `main`, with a short explanation. Make this
  update in a separate follow-up PR or a separate commit directly on `main` only
  with explicit user approval. Do not add pre-merge hashes in the original PR,
  ignore mixed commits or put a commit's own hash inside itself. Squash merge
  must not combine formatting with semantic changes.
- Enable locally with
  `git config --local blame.ignoreRevsFile .git-blame-ignore-revs`. Other clones
  can use that command or `git blame --ignore-revs-file .git-blame-ignore-revs`.
- Verify every listed hash exists in `main` history and that blame still
  attributes real fixes to their commits. Run the project's normal checks.
- Preserve user changes when splitting an existing PR. Keep a backup of the old
  head and use an explicit `--force-with-lease` if published history must
  change; stop if the remote has moved. Retain the separate formatting commit in
  the merged history, then record its stable hash in the follow-up described
  above.

Reference:
[Ignoring mass reformatting commits with git blame](https://akrabat.com/ignoring-revisions-with-git-blame/).
