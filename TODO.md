# TODO

- [ ] `TMPDIR` leaks into tests depending on the caller's environment: `init_run` in `bin/knockout`
  stores knockout's own temp dir in `TMPDIR`. If `TMPDIR` was already exported, tests inherit it,
  so their `mktemp` files land there and are removed with it (or kept with `-k`). If it wasn't,
  tests use `/tmp`. Fix: use an internal variable (e.g. `KO_TMP`), or export `TMPDIR` on purpose
  and document it. Either way, add a test and update the canonical prompt ("Single temporary
  directory for all outputs").
- [ ] Files of a test directory run in `find` order, not sorted: `collect_files_or_die` in
  `bin/knockout` uses `find -maxdepth 1` without sorting, so run and report order can differ
  between machines and file systems. Project mode sorts the directories, but not their files.
  Sort them (`LC_ALL=C`), add a test, and say so in the canonical prompt.
