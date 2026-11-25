# AGENTS.md

Rules for working on knockout.sh, a small Bash test runner. They record decisions already made;
follow them unless the user decides otherwise.

## Governance

- If there are findings unreleated to the current objective, add it to
  TODO.md

## Source of truth

- The header comment of `bin/knockout.sh` is the **canonical generation prompt**. It is authoritative
  for behavior and is kept verbatim: never reword, reorder or "tidy" it on your own.
- Behavior changes start with the prompt. Draft the new or changed prompt text, get the user's OK,
  then implement code and prompt together.
- Development and test notes belong in the prompt ("Development and tests" section), not in the
  README. The README covers usage and points to the header for development.

## Design principles

- **YAGNI.** No options, arguments or env vars until they are actually needed.
- **No surprising behavior.** Example: project mode searches only the current directory. There is no
  git-root lookup and no `cd`.
- **Strict conventions over guessing.** Example: suites are recognized by file name only. A misnamed
  suite is a failure with a hint, not silently detected.
- **One self-contained file.** `bin/knockout.sh` has no library files and no install location. Anything
  that suites need is emitted by knockout.sh itself (`knockout.sh fn-suite`).
- **Positional arguments are commands** (`run`, the default, `fn-suite` and `python3-unittest`); anything else is an
  error. Tests are selected by directory (`-d <dir>`, repeatable) or by discovery. A single test is
  run by calling it directly, never through `knockout.sh`.

## Conventions

| What | Convention |
|---|---|
| Testsuite | name ends in `.suite` or contains `.suite.` (`x.suite`, `x.suite.sh`, `x.suite.py`); any runnable file |
| Turbo suite | `*.turbo.suite.sh`: bash fn-suite, sourced once, each case runs in a subshell |
| Worker suite | `*.worker.suite*`: any language; started once with `KNOCKOUT_WORKER=1`, cases on stdin, reports on stdout (protocol in the header) |
| Bash suite | `source <(knockout.sh fn-suite)`, `t_*` functions, last line `testsuite_main "$@"`; load code under test via `"$TESTSUITE_DIR/…"` |
| Skip | exit 77 with no stderr: `SKIP`, not a failure |
| Python worker | `knockout.sh python3-unittest discover …`: stderr is **not** a failure, unittest decides |
| Test description | first stdout line starting with `# ` |
| Test directories | a `knockout-tests/` dir, or an empty `.knockout-tests` marker in any dir |
| `knockout.sh` = `knockout.sh run` | runs all test dirs below the cwd (hidden dirs skipped, sorted) |
| `knockout.sh -d <dir>` | runs only the given dir(s), non-recursive; `--verbose` pass-through, `-k` keep tmpdir, `--tap-report`/`--junit-report <file>` reports; `-j` is reserved for parallel jobs |
| `knockout.sh -v` | prints the resolved Git version or the version stamped into the installed copy |
| `knockout_version` | prints the same version for Bash callers that source the runner |

## Shell rules (from the prompt, project wide)

- `set -euo pipefail` everywhere. Handle test failures explicitly; they must not trigger `set -e`.
- Target GNU tools on Linux (Ubuntu) and bash 5 (`$EPOCHREALTIME`, `printf -v`, `mapfile`).
- Capture and propagate exit statuses explicitly. Never rely on an implicit `$?` outside the
  immediate execution context.
- Don't start a printf format with dashes: use `printf '%s\n' '--- stdout ---'`, not
  `printf '--- stdout ---\n'`.

## Performance

- Keep per-test work in the runner free of subshells and external processes. Prefer builtins over
  `date`, `awk`, `head`, `tail` and `grep` in hot paths.
- Return values through variables instead of `$(...)`: `func ARGS VAR` with `printf -v "$VAR"`.
  Prefix the helper's locals with `__`, so they can't shadow the caller's variable name.
- Measure before optimizing (`strace -f -c -e trace=clone,execve`, timings), and report the numbers.

## Runner semantics worth protecting

- Phase L lists all suites first, so the total is known up front. Phase R runs everything in argument
  order with one shared counter.
- Suite cases get `/dev/null` as stdin (forked and turbo alike).
- Turbo suites must report exactly like forked ones. Only the speed may differ.
- `bin/knockout.sh` is sourceable: when sourced it only defines functions and defaults; `main` runs only
  when executed.

## Tests

- **Layout:**
  - `test/knockout.turbo.suite.sh`: the self-test suite. `t_unit_*` source the knockout.sh under test
    and call its functions (`init_run DIR` + `run_paths …` for whole runs). `t_int_*` run the
    complete script; keep these few.
  - `test/knockout-test.sh`: a second, independent run of the same `t_*` functions. It stubs
    `knockout.sh` and `testsuite_main` as no-ops, so no knockout.sh code acts as harness.
- **Implementation under test:** by default the knockout.sh that runs the suite. Test another one with
  `KO_UNDER_TEST=/path/to/knockout.sh knockout.sh -d test`. The copy must be named `knockout.sh`.
- **Every case cleans up after itself:** use `case_dir NAME; d="$CASE_DIR"`. Never use
  `d="$(case_dir …)"`, because the subshell would remove the dir immediately.
- **Never run the complete script without arguments from the repo.** It would find the repo's own
  tests and recurse. `cd` into an empty case dir first.
- **Fixture suites:** when a test needs a throwaway bash suite as test data, create it with
  `write_fn_suite PATH <<'BODY' … BODY`. It pastes the fn-suite handler into the file (from
  `print_fn_suite` of the sourced knockout.sh) instead of writing `source <(knockout.sh fn-suite)`, which
  would start a knockout.sh process on every listing and case. The real `source <(knockout.sh fn-suite)`
  line is covered once, by `t_int_fn_suite_sourced_by_suite_without_install`; keep that test using it.
- **Prove that a new test can fail** (break the code in a scratch copy, not in the repo), and check
  that no `ko-test.*` dirs are left behind.
- **Done means:** `env PATH=/usr/bin:/bin make test` passes, which proves it works with no knockout.sh
  installed.

## Workflow

- Don't commit unless asked; the user commits.
- When an edit tool or a text replace touches heredoc-heavy test files, check that only the intended
  occurrences changed: function definitions and dispatcher lines also appear inside fixtures.
