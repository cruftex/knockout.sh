# knockout (`ko`)

A small Bash test runner. Tests are plain programs: exit status 0 and empty
stderr means pass, anything else fails. A test can also act as a *testsuite
generator* and emit a list of further test invocations.

## Install

```bash
./install.sh          # symlinks bin/knockout to ~/.local/bin/knockout and ~/.local/bin/ko
                      # (bin/knockout is self-contained; copying it works too)
```

## Usage

```bash
knockout [-v] [-d] <file-or-dir>...
```

- Arguments are files or directories. Directories expand to the files they
  contain (non-recursive).
- Executable files run directly. Non-executable `*.sh` files run via `bash`.
  Anything else is a fatal error.
- `-v` passes test stdout through. `-d` keeps the `.out`/`.err`/`.status`
  files of each test for inspection.
- If the first stdout line starts with `# `, it is shown as the test
  description.

Progress output:

```
[L 1/1] examples/example.suite.sh  0.015s
[T 1/4] test/knockout_test.sh  0.833s
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

## Development

```bash
make test             # black-box suite + dogfooding run of knockout on itself
KO_UNDER_TEST=/path/to/ko bash test/knockout_test.sh   # test another copy
```

The header comment of `bin/knockout` is its canonical generation prompt and is
kept verbatim.
