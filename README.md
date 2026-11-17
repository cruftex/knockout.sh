# knockout (`ko`)

A small Bash test runner. Tests are plain programs: exit status 0 and empty
stderr means pass, anything else fails. A test can also act as a *testsuite
generator* and emit a list of further test invocations.

## Install

```bash
./install.sh          # symlinks bin/knockout to ~/.local/bin/knockout and ~/.local/bin/ko
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
[T 1/1] examples/example-suite.sh  0.011s
[S 1/3] examples/example-suite.sh::another  0.008s  -- another example test
```

## Testsuite protocol

A test is a testsuite generator if it exits with status **88** and its stdout
starts with the line `#!testsuite`. Each following line is one test
invocation of the same file:

- lines containing TABs are split on TABs,
- otherwise they are parsed as Bash words (quoting allowed),
- `# ` description lines and blank lines are ignored.

Phase T runs every file once and collects suites. Phase S runs the generated
cases.

### Writing suites in Bash

`lib/testsuite.sh` implements the protocol for `t_*` functions:

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/testsuite.sh"

t_hello() { echo "# says hello"; echo "hello $*"; }

testsuite_main "$@"
```

Run without arguments, the script lists its tests and exits 88. Run with a
test name, it calls that function (leading `--options` are skipped). See
`examples/example-suite.sh`.

## Development

```bash
make test             # black-box suite + dogfooding run of knockout on itself
KO_UNDER_TEST=/path/to/ko bash test/knockout_test.sh   # test another copy
```

The header comment of `bin/knockout` is its canonical generation prompt and is
kept verbatim.
