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
- Anything else **fails**: a non-zero exit status, or any stderr output, even
  with status 0. knockout then prints the test's stdout, stderr and status.
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

### Tips

- Tests run in the caller's current directory; knockout does not `cd`. Resolve
  paths from the test file, e.g. `here="$(dirname "$0")"`.
- Any stderr output fails a test. Redirect expected noise (`2>/dev/null`), or
  capture it and check it.
- Let a failing check exit non-zero and say on stderr what went wrong.
- Naming is strict: suites are named `*.suite` or `*.suite.*`; plain tests must
  not be.

## Usage

```bash
ko                          # = ko run: run the project's tests
knockout [run] [-v] [-k] [-d <dir>]...
knockout fn-suite           # print the bash t_* suite handler
```

- A positional argument is always a command: `run` (the default) or
  `fn-suite`. To run a single test, call it directly.
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

Progress output:

```
[L 1/1] examples/example.suite.sh  0.015s
[T 1/4] test/knockout-test.sh  0.833s
[S 2/4] examples/example.suite.sh::another  0.010s  -- another example test
```

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

## Development

```bash
make test
```

Development and test notes (unit vs. integration tests, testing another
implementation via `KO_UNDER_TEST`) are part of the canonical prompt in the
`bin/knockout` header, which is kept verbatim.
