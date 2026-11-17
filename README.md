# knockout (`ko`)

A small Bash test runner. Tests are plain programs: exit status 0 and empty
stderr means pass, anything else fails. A test can also act as a *testsuite
generator* and emit a list of further test invocations.
See [Writing tests](#writing-tests) to get started.

## Install

```bash
./install.sh          # copies bin/knockout to ~/.local/bin/knockout, ko -> knockout
PREFIX=/usr/local ./install.sh   # install elsewhere; rerun to update
```

## Writing tests

### What a test is

A test is any runnable program: an executable file in any language, or a
non-executable `*.sh` file (run via `bash`).

- It **passes** when it exits with status 0 **and** writes nothing to stderr.
- It is **skipped** when it exits with status 77 and writes nothing to stderr
  (the automake/meson convention). A skip doesn't fail the run; the progress
  line shows `SKIP`.
- Anything else **fails**: another non-zero exit status, or any stderr output,
  even with status 0. knockout then prints the test's stdout, stderr and status.
- Stdout is free for logging; it is captured and shown on failure (or always
  with `-v`). If the first stdout line starts with `# `, the rest of that line
  is shown as the test description.

### Where tests live

Put tests in a directory named `knockout-tests/`, or mark any directory with an
empty `.knockout-tests` file:

```bash
mkdir -p test && touch test/.knockout-tests
```

`ko` finds these test directories anywhere below the current directory (hidden
directories are skipped). Only the files directly inside a test directory are
tests, and each one must be runnable (executable, or `*.sh`): anything else
stops the run. Subdirectories of a test directory are not run, unless they are
marked as test directories themselves, so put helpers and fixtures there (e.g.
`test/lib/`).

### A simple test

`test/greeting-test.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
echo "# greeting says hello"
out="$(echo hello)"          # replace with the command under test
[[ $out == hello ]] || { echo "expected hello, got: $out" >&2; exit 1; }
```

```
$ ko
[T 1/1] test/greeting-test.sh  0.003s  -- greeting says hello
```

If the check fails, the test reports why on stderr and exits non-zero:

```
[T 1/1] test/greeting-test.sh  0.003s  -- greeting says hello
ERROR
test: test/greeting-test.sh
status: 1
--- stdout ---
# greeting says hello
--- stderr ---
expected hello, got: hallo
```

To run a single test, call it directly: `bash test/greeting-test.sh`.

### Many tests in one file

A Bash file named `*.suite.sh` that defines `t_*` functions gives one test per
function; see [Writing suites in Bash](#writing-suites-in-bash). Suites in
other languages implement the [testsuite protocol](#testsuite-protocol).
To run many cases in one process in any language, use a
[worker suite](#worker-suites); Python unittest is built in.

### Tips

- Tests run in the caller's current directory; knockout does not `cd`. Resolve
  paths from the test file, e.g. `here="$(dirname "$0")"`.
- Any stderr output fails a test. Redirect expected noise (`2>/dev/null`), or
  capture it and check it. (Python unittest tests are the exception, see
  [below](#example-python-unittest).)
- To skip a test, e.g. when a tool is missing, print the reason and `exit 77`.
- Let a failing check exit non-zero and say on stderr what went wrong.
- Naming is strict: suites are named `*.suite` or `*.suite.*`; plain tests must
  not be.

## Usage

```bash
ko                          # = ko run: run the project's tests
knockout [run] [-v] [-k] [-t <tap>] [-j <junit.xml>] [-d <dir>]...
knockout fn-suite           # print the bash t_* suite handler
knockout python3-unittest discover [-s START] [-t TOP] [TEST_ID]   # Python unittest worker suite
```

- A positional argument is always a command: `run` (the default),
  `fn-suite` or `python3-unittest`. To run a single test, call it directly.
- Without `-d`, knockout runs every test directory found recursively below
  the current directory: directories named `knockout-tests/`, and
  directories containing an empty marker file `.knockout-tests`
  (e.g. `test/.knockout-tests`). Hidden directories are skipped.
- `-d <dir>` runs only the given directory (repeatable). Directories expand
  to the files they contain (non-recursive).
- Executable files run directly. Non-executable `*.sh` files run via `bash`.
  Anything else is a fatal error.
- `-v` passes test stdout through. `-k` keeps the `.out`/`.err`/`.status`
  files of each test for inspection.
- `-t <file>` writes a TAP version 13 report, `-j <file>` a JUnit XML report
  (for CI). JUnit includes stdout/stderr of failed and skipped tests.

Progress output:

```
[L 1/1] examples/example.suite.sh  0.015s
[T 1/4] test/knockout-test.sh  0.833s
[S 2/4] examples/example.suite.sh::another  0.010s  -- another example test
[S 3/4] examples/example.suite.sh::later  0.009s  SKIP  -- not ready yet
4 tests: 3 passed, 0 failed, 1 skipped, 0 not run, 0 suite errors  0.921s
```

The last line is the summary. *Not run* counts tests of a suite that failed as
a whole; *suite errors* count such suite failures (a broken listing, or a worker
that fails to start or breaks the protocol).

## Testsuite protocol

A file is a testsuite if its name ends in `.suite` or contains `.suite.`
(`math.suite`, `math.suite.sh`, `math.suite.py`, ...); any runnable file
works. Run without arguments, a suite must exit with status **88**, print
`#!testsuite` as its first stdout line and write nothing to stderr. Each
following line is one test invocation of the same file:

- lines containing TABs are split on TABs,
- otherwise they are parsed as Bash words (quoting allowed),
- `# ` description lines and blank lines are ignored.

Phase L lists all suites first, so the total number of tests is known before
any test runs. Phase R then runs everything in argument order with one shared
counter: plain files as `T`, suite cases as `S`.

Naming is strict: a broken suite listing is a failure, and so is a file *not*
named as a suite that emits testsuite output (the error hints to rename it).

### Writing suites in Bash

`knockout fn-suite` prints a handler implementing the protocol for `t_*`
functions. Source it straight from the runner, so there is no library file to
install or locate:

```bash
#!/usr/bin/env bash
set -euo pipefail
source <(knockout fn-suite)

t_hello() { echo "# says hello"; echo "hello $*"; }

testsuite_main "$@"
```

Run without arguments, the script lists its tests and exits 88. Run with a
test name, it calls that function (leading `--options` are skipped).
`TESTSUITE_PREFIX` overrides the `t_` prefix. When run by knockout, the
runner's own directory is put first on `PATH`, so a suite always gets the
handler of the knockout running it, even when knockout is not installed. See
`examples/example.suite.sh`.

### Turbo suites

Name a Bash fn-suite `*.turbo.suite.sh` and knockout sources it **once** into
a worker shell, then runs each case in a subshell (fork, no exec, no
re-sourcing). That is roughly 10x faster per case: on one machine, 500 trivial
cases took 1.0s instead of 9.1s.

- The file must be a Bash suite using `source <(knockout fn-suite)`. It stays
  a normal suite: listing, running it standalone, and the reports all work as
  for `*.suite.sh`.
- Cases are still isolated: variables, `cd`, `set` changes and `exit` stay
  inside the case's subshell. Each case runs with the shell options the suite
  set (e.g. `set -euo pipefail`).
- Differences from forked suites: top-level code runs once per run rather
  than once per case (shared setup, but side effects happen once too); `$0`
  is the worker, not the suite file; stdin is `/dev/null`.
- If sourcing fails (non-zero status or stderr), the suite is reported and
  its tests are not run.

### Worker suites

A file named `*.worker.suite` or `*.worker.suite.*` is a testsuite in any
language that runs all its tests in **one process**, instead of one process
per case. It lists its tests like any suite, and run with a test name it runs
that one test. In phase R knockout starts it once with `KNOCKOUT_WORKER=1`:

- **stdin**: one line per test, `INDEX<TAB>PREFIX<TAB>LINE`. `LINE` is the
  suite's own listing line, verbatim (split on the first two TABs only).
- For each test the worker writes `PREFIX.out`, `PREFIX.err` and
  `PREFIX.status` (the exit status), then reports it.
- **stdout**: `#!worker` once setup succeeded, then `INDEX SECONDS` per finished
  test, in stdin order.
- **stderr**: must stay empty. The worker must report every test and exit 0.

Results are judged from the files exactly as for forked tests. A worker that
prints no `#!worker` line, stops early, writes to stderr, exits non-zero or
reports an unexpected line fails as a suite file, and its unreported tests are
reported as not run.

#### Example: Python unittest

knockout has a built-in worker for Python unittest tests:
`knockout python3-unittest discover [-s START] [-t TOP]` takes the same
arguments as `python3 -m unittest discover`. `examples/python/` is a normal
Python project with unittest tests; knockout is added with one file:

```
examples/python/
  calc.py
  tests/__init__.py
  tests/test_calc.py
  knockout-tests/
    unittest.worker.suite.sh
```

`unittest.worker.suite.sh`:

```bash
#!/usr/bin/env bash
# Runs the project's unittest tests with knockout (one process, fork per test).
cd "$(dirname "$0")/.." && exec knockout python3-unittest discover -s tests -t . "$@"
```

It changes to the project root and runs the same discovery as
`python3 -m unittest discover -s tests -t .` there. `ko` then runs each test as
its own case:

```
[S 1/3] examples/python/knockout-tests/unittest.worker.suite.sh::tests.test_calc.CalcTest.test_add  0.004s  -- adds two numbers
```

> **stderr does not fail a Python test.** Unlike knockout's own rule (any
> stderr output is a failure), unittest decides pass or fail, exactly as with
> `python3 -m unittest`. Logging and warnings don't break tests: a test's stdout
> and stderr both end up in its stdout (`.out`), and `.err` only gets the
> failures.

The worker imports the tests once and forks per test, so each test is isolated
without re-importing. Each test runs with its class and module fixtures
(`setUpClass`, `setUpModule`), so these run once per test. A test's docstring
becomes its description. A failure shows `FAIL: <test>` or `ERROR: <test>` with
the traceback, including the parameters of a failed subtest. A skipped test is
`SKIP` (exit 77, with `skipped: <reason>` on stdout), and an expected failure
passes with `expected failure` on stdout. To run one test, call the suite file
with its id:
`bash examples/python/knockout-tests/unittest.worker.suite.sh tests.test_calc.CalcTest.test_add`.

With 500 trivial unittest cases, the run took 1.5s as a worker suite and 47s
with the same file as a forked suite (`*.suite.sh`).

## Development

```bash
make test
```

Development and test notes (unit vs. integration tests, testing another
implementation via `KO_UNDER_TEST`) are part of the canonical prompt in the
`bin/knockout` header, which is kept verbatim.
