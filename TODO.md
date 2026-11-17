# TODO

## `TMPDIR` leaks into tests depending on the caller's environment

`init_run` in `bin/knockout` stores knockout's own temp dir in `TMPDIR`. Whether tests see it depends
on the caller's environment:

- If `TMPDIR` was already exported, tests inherit knockout's temp dir. Their `mktemp` files land
  there and are removed with it (or kept with `-k`).
- If it wasn't exported, the assignment stays shell-local and tests use `/tmp` as usual.

So test behavior differs between environments.

Options:
- Use an internal variable (e.g. `KO_TMP`) so tests never see knockout's temp dir.
- Export `TMPDIR` on purpose and document that test temp files are cleaned up with the run.

Either way: add a test and update the canonical prompt ("Single temporary directory for all outputs").
