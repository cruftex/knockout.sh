---
name: release-summary
description: Draft knockout.sh release notes from the changes since the last published release.
---

Use the current `HEAD` as the release candidate. If the user supplies a base
tag, use its local Git ref and skip GitHub lookup. Otherwise, use
`gh api --paginate --slurp 'repos/cruftex/knockout.sh/releases?per_page=100'`
to find the tag of the most recently published release by `published_at`,
excluding drafts and prereleases. A successful lookup with no qualifying
releases means this is the first release. If the lookup fails, report the
failure and ask for a base tag if one is available.

Resolve the base tag locally and ensure it is an ancestor of `HEAD` before
comparing. If it is missing locally, tell the user to fetch it or provide
another base tag. If it is not an ancestor, report the mismatch. If there is
no base because this is the first release, inspect the committed tree and
its available history to summarize the shipped features. Flag a shallow
checkout if it prevents a reliable comparison.

Review the commit range and net diff, checking the CLI documentation and
tests where needed to confirm behavior. Describe user-visible outcomes and
migration steps. Omit reverted changes and internal work without a
user-visible effect. Keep all three Markdown headings in this order:

- `## Incompatible Changes` for changes that require action by existing users.
  Use `None.` here for the first release.
- `## Highlights` for new features and other notable improvements.
- `## Bug Fixes` for corrected behavior.

Use concise bullets and put each change in one section. Use `None.` for
any empty section. Return the Markdown in chat so the user can paste it
into their GitHub draft. Keep the repository and GitHub release unchanged.
