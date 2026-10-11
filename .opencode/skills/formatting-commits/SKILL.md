---
name: formatting-commits
description: Use when formatting many files, upgrading a formatter, or separating formatting changes in a PR to preserve git blame.
---

# Formatting commits

- Keep bulk formatter output in a separate `style(format): ...` commit. Never mix
  dependency updates, fixes, tests or configuration changes into an ignored commit.
- Review the diff: formatter-generated rewrites must preserve behavior. Keep any
  semantic changes outside the formatting commit, even if a tool generated them.
- After committing, add its full commit hash with a short explanation to the
  repository-root `.git-blame-ignore-revs` in a subsequent commit. Never ignore a
  mixed commit or try to put a commit's own hash inside itself.
- Enable locally with `git config --local blame.ignoreRevsFile .git-blame-ignore-revs`.
  Other clones can use that command or `git blame --ignore-revs-file .git-blame-ignore-revs`.
- Verify every listed hash exists and that blame still attributes real fixes to
  their commits. Run the project's normal checks.
- Preserve user changes when splitting an existing PR. Keep a backup of the old
  head and use an explicit `--force-with-lease` if published history must change;
  stop if the remote has moved. Squashing/rebasing changes hashes: retain the
  formatting commit in the merged history or update the ignore file accordingly.

Reference: [Ignoring mass reformatting commits with git blame](https://akrabat.com/ignoring-revisions-with-git-blame/).
