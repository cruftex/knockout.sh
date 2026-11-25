# TODO

- [ ] improve release.sh
  - Add another step with a codex call to create a summary since last release
  - release.sh finilise DIR should do the final release
  - release.sh release v1.2.3 shoud do the complete workflow
- [ ] Implement Fail Fast semantics, parameter: --stop-on-error and env var KNOCKOUT_STOP_ON_ERROR=true
- [ ] Assertions: Scan popular public projects with shell tests suites and propose a generic useful assertion library in docs/design/assertions-draft.md
- [ ] Assertions: A failure cannot be pinned down to a line number. However, a failing assertion could print the line number. Define standard err pattern for a failure location.
- [ ] When executing all tests in a directory an editor backup file like, xy~, might be executed as test or fail, do
  some research what file patterns should be ignored on directory scanning and implement a filter
- [ ] `TMPDIR` leaks into tests depending on the caller's environment: `init_run` in `bin/knockout.sh`
  stores knockout.sh's own temp dir in `TMPDIR`. If `TMPDIR` was already exported, tests inherit it,
  so their `mktemp` files land there and are removed with it (or kept with `-k`). If it wasn't,
  tests use `/tmp`. Fix: use an internal variable (e.g. `KO_TMP`), or export `TMPDIR` on purpose
  and document it. Either way, add a test and update the canonical prompt ("Single temporary
  directory for all outputs").
- [ ] Files of a test directory run in `find` order, not sorted: `collect_files_or_die` in
  `bin/knockout.sh` uses `find -maxdepth 1` without sorting, so run and report order can differ
  between machines and file systems. Project mode sorts the directories, but not their files.
  Sort them (`LC_ALL=C`), add a test, and say so in the canonical prompt.
