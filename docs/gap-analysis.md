# Gap analysis: knockout.sh vs. bats-core, ShellSpec, shUnit2, bashunit

Status: 2026-11. Feature claims about other tools come from their current docs
([bats-core](https://bats-core.readthedocs.io/en/stable/usage.html),
[ShellSpec](https://github.com/shellspec/shellspec),
[shUnit2](https://github.com/kward/shunit2),
[bashunit](https://bashunit.com/command-line)). The knockout.sh examples were run
with the current `bin/knockout.sh`.

knockout.sh is a *runner* with a process contract (exit status, stderr, exit 77).
The others are shell *frameworks* with a DSL, assertions and lifecycle hooks. Many
gaps below are deliberate (KISS, YAGNI). Each section says whether a gap has a
workaround, is a candidate for a feature, or is out of scope.

## Summary

| Gap | Who has it | knockout.sh today | Verdict |
|---|---|---|---|
| [Assertions](#assertions) | all four | plain shell, bring your own | by design |
| [Setup / teardown hooks](#setup-and-teardown) | all four | suite top level, `trap … EXIT` | workaround |
| [Parameterized tests](#parameterized-tests) | ShellSpec, bashunit | testsuite protocol listing lines with arguments | covered |
| [Mocks and spies](#mocks-and-spies) | ShellSpec, bashunit | `PATH` stubs, function overrides | workaround |
| [Select by name or tag](#selecting-tests) | bats, ShellSpec, bashunit | `run PATH…` (dir or file), call a single test directly | gap |
| [Parallel runs](#parallel-runs) | bats, ShellSpec, bashunit | none | gap |
| [Fail fast](#fail-fast) | bats, ShellSpec, bashunit | none | gap |
| [Coverage](#coverage) | ShellSpec (kcov), bashunit | none | out of scope for now |
| [Snapshot tests](#snapshot-tests) | bashunit | none | workaround |
| [Watch mode](#watch-mode) | bashunit | none | out of scope |
| [Timeouts](#timeouts) | bashunit | none | workaround |
| [Portability](#portability) | ShellSpec, shUnit2 (POSIX sh) | bash 5, GNU tools on Linux | by design |

And the other direction, see [Where knockout.sh is ahead](#where-knockoutsh-is-ahead): tests in
any language, failing on stderr, the worker protocol, the total known up front, and a single file
with nothing to install.

---

## Assertions

The others ship assertion functions with readable diffs. knockout.sh judges only
the exit status and stderr.

bats-core (with the bats-assert add-on):

```bash
load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

@test "adds two numbers" {
  run add 1 2
  assert_success
  assert_output 3
}
```

ShellSpec:

```sh
Describe 'add'
  It 'adds two numbers'
    When call add 1 2
    The output should eq 3
  End
End
```

shUnit2:

```sh
testAdd() { assertEquals 3 "$(add 1 2)"; }
. shunit2
```

bashunit:

```bash
function test_add() { assert_same 3 "$(add 1 2)"; }
```

knockout.sh: plain shell. A failing check writes to stderr and exits non-zero.
A helper is a few lines, written in the suite or a sourced file:

```bash
#!/usr/bin/env bash
set -euo pipefail
source <(knockout.sh fn-suite)
source "$TESTSUITE_DIR/../lib/add.sh"

expect_eq() {  # expect_eq ACTUAL EXPECTED
  [[ $1 == "$2" ]] || { printf 'expected: %s\n  actual: %s\n' "$2" "$1" >&2; return 1; }
}

t_add() { expect_eq "$(add 1 2)" 3; }

testsuite_main "$@"
```

**Verdict: by design.** knockout.sh stays assertion-free, but any assertion
library that reports on stderr works. Possible later: a documented recipe, not a
built-in.

## Setup and teardown

| | per test | once per file |
|---|---|---|
| bats-core | `setup` / `teardown` | `setup_file` / `teardown_file` |
| ShellSpec | `BeforeEach` / `AfterEach` | `BeforeAll` / `AfterAll` |
| shUnit2 | `setUp` / `tearDown` | `oneTimeSetUp` / `oneTimeTearDown` |
| bashunit | `set_up` / `tear_down` | `set_up_before_script` / `tear_down_after_script` |

knockout.sh has no hooks. The suite type decides when top-level code runs:

- a forked `*.suite.sh` runs its top level for **every case**: per-test setup.
- a `*.turbo.suite.sh` runs its top level **once**: per-file setup. Each case
  then runs in its own subshell.

Teardown is a `trap` in the case. It fires when the case's process or subshell
exits, also on failure:

```bash
t_writes_config() {
  local dir; dir=$(mktemp -d)
  trap "rm -rf '$dir'" EXIT
  write_config "$dir/app.conf"
  [[ -s $dir/app.conf ]] || { echo "config is empty" >&2; exit 1; }
}
```

There is no per-file teardown in a turbo suite. Clean up per case instead.

**Verdict: workaround.** The trap pattern is worth a README tip.

## Parameterized tests

ShellSpec:

```sh
Describe 'add'
  Parameters
    1 2 3
    2 2 4
  End
  It "adds $1 and $2"
    When call add "$1" "$2"
    The output should eq "$3"
  End
End
```

bashunit:

```bash
# @data_provider sums
function test_add() { assert_same "$3" "$(add "$1" "$2")"; }
function sums() { bashunit::data_set 1 2 3; bashunit::data_set 2 2 4; }
```

knockout.sh: the testsuite protocol *is* a data provider. Every listing line is
one case with its own arguments. A suite written by hand needs no handler:

```bash
#!/usr/bin/env bash
# t/math.suite.sh
set -euo pipefail
if (( $# == 0 )); then
  echo '#!testsuite'
  printf '%s\n' 'add 1 2 3' 'add 2 2 4' 'add -1 1 0'
  exit 88
fi
case "$1" in
  add) got=$(( $2 + $3 ))
       [[ $got == "$4" ]] || { echo "add $2 $3: expected $4, got $got" >&2; exit 1; } ;;
  *) echo "unknown test: $1" >&2; exit 2 ;;
esac
```

```
[S 2/4] t/math.suite.sh::add (1 2 3)  0.002s
[S 3/4] t/math.suite.sh::add (2 2 4)  0.003s
[S 4/4] t/math.suite.sh::add (-1 1 0)  0.002s
```

The built-in `fn-suite` handler lists only function names. Each `t_*` function is
one case without arguments.

**Verdict: covered** through the protocol. Possible later: let `fn-suite` take
parameter lines (e.g. a `t_add_params` function). Only add this when a real suite
needs it.

## Mocks and spies

ShellSpec:

```sh
It 'uses the stubbed year'
  Mock date
    echo 1999
  End
  When call year
  The output should eq 1999
End
```

bashunit:

```bash
function test_year() {
  bashunit::mock date echo 1999
  assert_same 1999 "$(year)"
}
function test_calls_git() {
  bashunit::spy git
  publish
  assert_have_been_called_with git "push origin main"
}
```

knockout.sh: no mock API. Plain shell covers most of it. Override a function, or
put a stub command first on `PATH`. In a turbo suite each case runs in a subshell,
so the change can't leak into other cases:

```bash
#!/usr/bin/env bash
# t/year.turbo.suite.sh
set -euo pipefail
source <(knockout.sh fn-suite)

year() { date +%Y; }   # code under test

stub() {  # stub NAME OUTPUT: fake command for this case only
  local dir; dir=$(mktemp -d)
  printf '#!/bin/sh\necho %s\n' "$2" > "$dir/$1"; chmod +x "$dir/$1"
  PATH="$dir:$PATH"
  trap "rm -rf '$dir'" EXIT
}

t_year_is_stubbed() {
  stub date 1999
  [[ $(year) == 1999 ]] || { echo "got $(year)" >&2; exit 1; }
}

testsuite_main "$@"
```

A spy is the same stub with an extra line that appends `"$@"` to a log file.

**Verdict: workaround.** No built-in, by design. A recipe in the README would help.

## Selecting tests

- bats-core: `bats --filter 'add' test/`, `--filter-tags slow`, with tags set by
  `# bats test_tags=slow`
- ShellSpec: `shellspec spec/math_spec.sh:12` (by line), `--example 'adds'`
- bashunit: `bashunit --filter add tests/`, `--tag`, `--exclude-tag`

knockout.sh: select directories or test files with `run PATH…`. Run a single case
directly, without the runner:

```bash
knockout.sh run test/math                # one directory
knockout.sh run t/math.suite.sh          # one suite
bash t/math.suite.sh add 2 2 4           # one case, exactly as the runner calls it
```

There is no name filter across a run, and no tags.

**Verdict: gap.** A name filter (e.g. a glob on the designation, applied after
phase L) is the most likely real need here. It would be a behavior change, so it
starts as a prompt change in the `bin/knockout.sh` header.

## Parallel runs

- bats-core: `bats --jobs 4 test/` (needs GNU parallel or rush)
- ShellSpec: `shellspec --jobs 4`
- bashunit: `bashunit --parallel tests/`

knockout.sh runs everything sequentially, with one shared counter in argument
order. You can still split by directory and run several processes yourself, each
with its own report:

```bash
knockout.sh --junit-report unit.xml run test/unit & knockout.sh --junit-report slow.xml run test/slow & wait
```

Their progress output interleaves, and the exit status needs separate `wait`s.

**Verdict: gap.** Turbo and worker suites already remove most of the per-case
cost (500 cases: 9.1s → 1.0s turbo; Python 47s → 1.5s worker). Measure first, as
AGENTS.md says, before adding parallelism. It would also change the ordered
progress output.

## Fail fast

- bats-core: `--abort`
- ShellSpec: `--fail-fast`
- bashunit: `--stop-on-failure`

knockout.sh always runs everything and reports at the end.

**Verdict: gap,** small. Wait for a real need (YAGNI).

## Coverage

- ShellSpec: `shellspec --kcov`
- bashunit: `--coverage`, `--coverage-report-html`, `--coverage-min 80`

knockout.sh: none. Tests are arbitrary programs, so there is no general coverage.
kcov can wrap a single test by hand (`kcov out/ bash t/math.suite.sh add 1 2 3`),
but the results aren't merged.

**Verdict: out of scope for now.**

## Snapshot tests

bashunit:

```bash
function test_help() { assert_match_snapshot "$(mytool --help)"; }
```

knockout.sh: compare against a checked-in file:

```bash
t_help() { diff -u "$TESTSUITE_DIR/snapshots/help.txt" <(mytool --help) >&2; }
```

`diff` prints the difference, and `>&2` moves it to stderr, so the case fails with
a readable diff. Update the snapshot with `mytool --help > test/snapshots/help.txt`.

**Verdict: workaround.**

## Watch mode

bashunit: `bashunit watch tests/`. knockout.sh: none. Use an external watcher,
e.g. `ls -d src/* test/* | entr knockout.sh discover`.

**Verdict: out of scope.**

## Timeouts

bashunit: `--test-timeout`. knockout.sh: none. A test that hangs stops the run.
Wrap the slow command in the test, e.g. `timeout 10 ./server-check`. GNU `timeout`
exits 124, which fails the test.

**Verdict: workaround.** A runner-wide timeout is a candidate if hangs in CI
become a real problem.

## Portability

ShellSpec and shUnit2 run on POSIX shells (dash, ksh, zsh, busybox ash, …).
bats-core and bashunit need bash. knockout.sh needs bash 5 and GNU tools on Linux
(`$EPOCHREALTIME`, `mapfile`, GNU `find`).

**Verdict: by design.** The runner's platform doesn't limit the tests: they can be
written in any language that runs there.

---

## Where knockout.sh is ahead

**Tests in any language.** Every executable is a test, with no adapter:

```bash
$ ls test/
api_test.py  cli-test.sh  knockout-tests/  parser_test  # a compiled binary
```

**Failing on stderr.** Unexpected warnings fail the test, even with exit 0. With the
frameworks, a `cmd 2>&1` or a missed warning goes unnoticed.

**Suites and workers in any language.** The [testsuite protocol](../README.md#testsuite-protocol)
and the [worker protocol](../README.md#worker-suites) are a few lines of stdin and
stdout. Python unittest is built in and runs without changes to the project:

```bash
# knockout-tests/unittest.worker.suite.sh
cd "$(dirname "$0")/.." && exec knockout.sh python3-unittest discover -s tests -t . "$@"
```

**Each test runs standalone.** Every case can run without the runner, exactly as
the runner calls it (`bash t/math.suite.sh add 1 2 3`). Debugging needs no
framework mode.

**The total is known up front.** Phase L lists every suite before anything runs,
so progress is `[S 3/58]` from the first line on.

**One file, nothing to install.** Suites get their handler with
`source <(knockout.sh fn-suite)`, from the running copy, so CI needs nothing but
the one script.

**Standard reports.** TAP 13 and JUnit XML, which are on par with bats-core,
ShellSpec and bashunit and ahead of shUnit2 (no TAP, JUnit unreleased).

## Candidate follow-ups

Ordered by likely value. None is planned: each starts as a prompt change and
needs a real use case first (YAGNI).

1. Select tests by name across a run (filter on the designation after phase L).
2. README recipes: `trap` teardown, `PATH` stubs, snapshot with `diff`.
3. A runner-wide per-test timeout.
4. Parameter lines for `fn-suite`.
5. Fail fast.
