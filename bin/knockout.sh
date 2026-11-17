#!/usr/bin/env bash
set -euo pipefail

# CANONICAL GENERATION PROMPT
#
# The text below is the authoritative prompt for this script.
# It MUST be copied verbatim into the generated script header.
# Only add the leading "# " comment prefix; do not reword or reorder.
#
# Test Runner (Bash)
#
# Runs the test files of test directories. Directories are expanded to their
# contained files (non-recursive). All files are collected first before execution.
#
# Commands (a positional argument is always a command):
# - run (default): run the test directories given with -d, or, without -d,
#   all test directories found below the current directory (project mode).
# - fn-suite: print the bash t_* testsuite handler (see below).
# - python3-unittest discover [-s START] [-t TOP] [TEST_ID]: run Python unittest
#   tests as a worker testsuite (see "Python unittest worker" below).
# - Anything else: print usage and exit 1. Single tests are run by calling them directly.
#
# Execution rules:
# - Executable files are run directly.
# - Non-executable *.sh files are run via bash.
# - Missing test directories or non-runnable files cause a fatal error ("die").
#
# Test protocol (simple tests):
# - A test is a normal program or script.
# - Exit status 0 means success.
# - Any non-zero exit status means failure.
# - Any output on stderr means failure.
# - Exit status 77 with no stderr output means skipped: shown as SKIP, counted as
#   skipped, and not a failure. This holds for testsuite and worker cases too.
# - Standard output and standard error and exit status are collected in temporary
#   files named after test designations
# - Standard output, standard error, and exit status are written to separate
#   temporary files named after the test designation (e.g. .out, .err, .status).
#   This can be used for later inspection (with parameter -d)
#
# Phases:
# - Phase L: run each testsuite file once without arguments to list its tests.
#   After phase L the total number of tests is known.
# - Phase R: run all tests in argument order: simple tests once (shown as T),
#   testsuite files as their listed tests (shown as S), one shared counter.
#
# Testsuite protocol:
# - A file is a testsuite if its name ends in ".suite" or contains ".suite."
#   (e.g. math.suite, math.suite.sh, math.suite.py); any runnable file type works.
# - Listing a testsuite must exit with status 88, print "#!testsuite" as the
#   first stdout line and write nothing to stderr; otherwise it is a failure
#   and contributes no tests.
# - A file not named as testsuite that produces testsuite output (status 88 and
#   "#!testsuite") is a failure; the error hints to rename it.
# - Each following stdout line defines one test invocation.
# - Argument parsing:
#     * lines containing TABs are split on TABs
#     * otherwise parsed as normal bash words (with quoting)
# - Description lines ("# ") are ignored for testsuite generators.
#
# Progress output (one line per test):
#
#   [L 1/1] ./test_math.suite  0.004s
#   [T 1/3] ./test_basic  0.012s
#   [S 2/3] ./test_math.suite::add (1 2)  0.000s
#   [S 3/3] ./test_math.suite::div (4 2)  0.000s  -- division works
#
# - Format: [PHASE CURRENT/TOTAL] DESIGNATION  TIME [SKIP] [-- DESCRIPTION]
# - TIME is seconds with up to 3 decimals, unit immediately appended (e.g. 12.345s).
# - DESIGNATION = filename + optional test name + remaining arguments
#   (test name is not repeated inside arguments)
# - If stdout first line starts with "# ", the rest is shown as DESCRIPTION.
#
# Errors:
# - If a test writes to stderr or exits non-zero (except testsuite exit 88):
#     * print "ERROR" and full stdout/stderr/status to stderr
#     * continue running remaining tests
# - Final exit status is non-zero if any test failed.
# - After all tests, print one summary line to stdout:
#     51 tests: 48 passed, 1 failed, 1 skipped, 1 not run, 0 suite errors  12.345s
#   (all fields always present). Suite errors are failures of a suite file itself
#   (listing, worker setup or worker protocol).
#
# Optional parameters:
# - -v : pass test stdout/stderr through in addition to capturing
# - -k : keep temporary directory after execution
# - -d <dir> : test directory to run (repeatable); disables project mode
# - -t <file> : write a TAP version 13 report (ok/not ok per test, "# SKIP",
#   suite errors as "not ok", plan line "1..N" at the end)
# - -j <file> : write a JUnit XML report: one <testsuite name="knockout.sh">, one
#   <testcase classname="FILE" name="TEST AND ARGS" time="..."> per test, with
#   <failure> (status and stderr), <error> (not run / suite error, with hint) or
#   <skipped/>, and <system-out>/<system-err> for failed and skipped tests.
#
# Project mode (run without -d):
# - Run all test directories found recursively below the current directory:
#     * directories named "knockout-tests"
#     * directories containing a marker file ".knockout-tests"
#   Hidden directories are skipped. Order is sorted.
# - If no test directory is found, print an explanatory error and usage.
# - Directory expansion never treats ".knockout-tests" as a test.
#
# Sourceable:
# - When sourced, the script only defines its functions and defaults; nothing
#   runs and no traps are set. When executed, main parses options and runs.
#
# Name:
# - The script and its command are named "knockout.sh", the project name; there
#   is no other command name. Suites call "knockout.sh fn-suite" and
#   "knockout.sh python3-unittest". The runner puts its own directory first on
#   PATH, so these resolve to the running copy, installed or not.
#
# Development and tests:
# - test/knockout.turbo.suite.sh sources the knockout under test (KO_UNDER_TEST,
#   default: the knockout running the suite) and calls its functions directly
#   (unit tests). Only a few integration tests run the complete script.
# - test/knockout-test.sh runs the same t_* functions a second time without
#   any knockout as harness, so a runner bug cannot hide failing tests.
# - Testing another implementation: KO_UNDER_TEST=/path/to/knockout.sh knockout.sh -d test
#
# Turbo testsuites:
# - Files named "*.turbo.suite.sh" are bash fn-suites that are listed like any
#   testsuite, but in phase R are sourced once into a separate worker bash.
# - Each listed test runs in a subshell of the worker (no exec, no re-sourcing),
#   with the shell options the suite set at source time.
# - Per test: stdout, stderr and status are captured and reported exactly like
#   forked tests; progress lines and timing are identical in format.
# - If sourcing fails (non-zero status or stderr output), that is a failure of
#   the suite file and its tests are reported as not run.
#
# Worker testsuites:
# - Files named "*.worker.suite" or containing ".worker.suite." are testsuites in any
#   language that run all their listed tests in one process. Listing (phase L) is
#   unchanged. Run with a test name and without KNOCKOUT_WORKER, a worker suite runs
#   that single test like any testsuite.
# - In phase R the file is started once, with the environment variable
#   KNOCKOUT_WORKER=1 and these streams:
#     * stdin: one line per test, in listing order: INDEX<TAB>PREFIX<TAB>LINE
#       INDEX is the progress counter value, PREFIX an absolute path prefix, LINE
#       the listing line verbatim (split on the first two TABs only).
#     * stdout: reports. First the line "#!worker" once setup succeeded, then one
#       line "INDEX SECONDS" (e.g. "3 0.012") per finished test, in stdin order.
#     * stderr: worker errors; any output is a failure of the suite file.
# - Per test the worker writes PREFIX.out, PREFIX.err and PREFIX.status (the exit
#   status as a decimal number) before reporting it. Pass/fail, description and
#   error report are evaluated from these files exactly as for forked tests.
# - With -v, the captured stdout/stderr of each test is printed after its report.
# - No "#!worker" line: the suite file fails and its tests are reported as not run.
#   Worker exits early, exits non-zero, or reports an unexpected line: the suite
#   file fails and unreported tests are reported as not run.
#
# Python unittest worker:
# - knockout contains the Python code (stdlib only) for a worker testsuite and runs
#   it with python3 -c, passing on its arguments and the environment.
# - Arguments mirror "python3 -m unittest discover": -s start dir (default "."),
#   -t top-level dir (default: the start dir), pattern "test*.py". Relative paths
#   are relative to the current directory. Other arguments are an error.
# - Without TEST_ID and KNOCKOUT_WORKER: list the unittest test ids (exit 88).
#   With TEST_ID: run that one test. With KNOCKOUT_WORKER=1: worker protocol;
#   tests are imported once, each test runs in a forked child.
# - Unlike the knockout convention ("any output on stderr means failure"), stderr
#   output of a Python test does NOT fail it: pass/fail is decided by unittest,
#   as with "python3 -m unittest", so logging and warnings don't break tests.
# - Per test: the test runs inside a TestSuite, so class and module fixtures
#   run. The first docstring line is printed as "# " description. The test's own
#   stdout and stderr both go to stdout; .err only gets failures and errors, each
#   as "FAIL: <test>" or "ERROR: <test>" (including subtest parameters) plus the
#   traceback (exit 1). Skipped: "skipped: <reason>" on stdout, exit 77.
#   Expected failure: "expected failure" on stdout, exit 0.
# - Usage in a worker testsuite file (e.g. knockout-tests/unittest.worker.suite.sh):
#     cd "$(dirname "$0")/.." && exec knockout.sh python3-unittest discover -s tests -t . "$@"
#
# Shell strictness:
# - Runner uses: set -euo pipefail
# - Runner logic failures abort immediately.
# - Test failures are explicitly handled and must not trigger set -e.
#
# Environment:
# - GNU tools on Linux (Ubuntu)
# - Single temporary directory for all outputs
#
# Please avoid bugs:
#
# - The runner MUST explicitly capture and propagate the exit status of each test
#   execution. Testsuite detection MUST NOT rely on the implicit shell `$?`
#   outside the immediate execution context. (this is added because ChatGPT introduced a bug)
# - Don't do something like: printf '--- stdout ---\n'
#   This results in an error: printf: --: invalid option
#
# Prompt reproduction rule:
#
# It MUST be copied verbatim (byte-for-byte), into the generated script header.
# However, if not yet prefixed with "# ", add a comment prefix.

# -----------------------------------------------------------------------------
# CONSOLIDATED GENERATION PROMPT for `knockout.sh fn-suite` (origin: papa-ps testsuite-example.sh)
#
# Bash testsuite runner with the following semantics:
#
# - Tests are bash functions with a configurable prefix (default: "t_")
#
# - If the script is *sourced*:
#     * Do nothing
#
# - If the script is *executed without arguments*:
#     * Print the literal line: "#!testsuite"
#     * Print a list of all defined test functions
#       - Functions are discovered via `declare -F`
#       - Only functions whose names start with the prefix are listed
#       - The prefix is stripped from the printed names
#       - The list is prepared using exactly ONE awk invocation
#     * Exit with status code 88
#
# - If the script is *executed with arguments*:
#     * Skip leading arguments matching "--something"
#     * Stop skipping when:
#         - "--" is encountered (consume it), OR
#         - a non "--*" argument is encountered
#     * The first remaining argument is the test name (without prefix)
#     * Call the corresponding test function (prefix + name)
#     * Pass all remaining arguments verbatim to the test function
#
# - Test functions should emit a compact one-line description as their
#   FIRST line of output, starting with "# "
#
# - The dispatch logic must live in a single function at the top of the file
#   so it can be moved into a shared library later.
#
# - Example test functions:
#     t_test, t_hello, t_another
# -----------------------------------------------------------------------------

print_fn_suite() {
  cat <<'FN_SUITE'
# shellcheck shell=bash
# knockout.sh fn-suite: "#!testsuite" protocol for t_* functions.
# Usage: source <(knockout.sh fn-suite); define t_* functions; end with: testsuite_main "$@"
# TESTSUITE_PREFIX overrides the "t_" prefix.

# Entrypoint for a testsuite script. Must be called from the script itself.
testsuite_main() {
  local prefix="${TESTSUITE_PREFIX:-t_}"

  # If the calling script was sourced: do nothing.
  if [[ "${BASH_SOURCE[1]}" != "$0" ]]; then
    return 0
  fi
  # If executed without args: print testsuite listing and exit 88.
  if (( $# == 0 )); then
    echo "#!testsuite"
    declare -F | awk -v p="$prefix" '
      { name = $3 }
      index(name, p) == 1 {
        sub("^" p, "", name)
        print name
      }
    '
    exit 88
  fi

  # Skip leading --something arguments
  while (( $# )); do
    case "$1" in
      --) shift; break ;;   # end-of-options marker
      --*) shift ;;         # skip option
      *) break ;;           # first non-option is test name
    esac
  done

  (( $# )) || { echo "Error: no test specified" >&2; exit 2; }

  local name="$1"
  shift
  local fn="${prefix}${name}"

  if ! declare -F "$fn" >/dev/null 2>&1; then
    echo "Error: no such test: $name" >&2
    exit 1
  fi

  "$fn" "$@"
}
FN_SUITE
}

# Python code of `knockout.sh python3-unittest`, run with python3 -c (stdin carries
# the worker cases). See "Python unittest worker" above.
print_python3_unittest() {
  cat <<'PYTHON3_UNITTEST'
import os
import sys
import time
import unittest

USAGE = "usage: knockout.sh python3-unittest discover [-s START] [-t TOP] [TEST_ID]"


def parse_args(args):
    if not args or args[0] != "discover":
        sys.exit(USAGE)
    start, top, rest = ".", None, args[1:]
    while rest and rest[0] in ("-s", "-t"):
        if len(rest) < 2:
            sys.exit(USAGE)
        if rest[0] == "-s":
            start = rest[1]
        else:
            top = rest[1]
        rest = rest[2:]
    if len(rest) > 1 or (rest and rest[0].startswith("-")):
        sys.exit(USAGE)
    return start, top, rest[0] if rest else None


def discover(start, top):
    tests = {}
    pending = [unittest.defaultTestLoader.discover(start, top_level_dir=top)]
    while pending:
        item = pending.pop()
        if isinstance(item, unittest.TestSuite):
            pending.extend(item)
        else:
            tests[item.id()] = item
    return tests


def run_test(test, report):
    """Runs one test; failure blocks go to report. Returns the exit status:
    0 passed, 1 failed, 77 skipped."""
    doc = test.shortDescription()
    if doc:
        print("# " + doc, flush=True)
    result = unittest.TestResult()
    unittest.TestSuite([test]).run(result)
    sys.stdout.flush()
    sys.stderr.flush()
    for _, reason in result.skipped:
        print("skipped: " + reason)
    for _ in result.expectedFailures:
        print("expected failure")
    for kind, entries in (("ERROR", result.errors), ("FAIL", result.failures)):
        for failed, trace in entries:
            report.write("%s: %s\n%s" % (kind, failed, trace))
    for passed in result.unexpectedSuccesses:
        report.write("FAIL: %s\nunexpected success\n" % passed)
    sys.stdout.flush()
    report.flush()
    if not result.wasSuccessful():
        return 1
    return 77 if result.skipped else 0


def worker(tests):
    print("#!worker", flush=True)
    for line in sys.stdin:
        idx, prefix, test_id = line.rstrip("\n").split("\t", 2)
        t0 = time.monotonic()
        pid = os.fork()
        if pid == 0:
            status = 1
            try:
                # The test's stdout and stderr both go to .out; .err only gets
                # failure blocks, so stderr output alone doesn't fail a test.
                os.dup2(os.open(os.devnull, os.O_RDONLY), 0)
                flags = os.O_WRONLY | os.O_CREAT | os.O_TRUNC
                os.dup2(os.open(prefix + ".out", flags, 0o644), 1)
                os.dup2(1, 2)
                sys.stdout.reconfigure(line_buffering=True)
                report = os.fdopen(os.open(prefix + ".err", flags, 0o644), "w")
                test = tests.get(test_id)
                if test is None:
                    report.write("no such test: %s\n" % test_id)
                    report.flush()
                else:
                    status = run_test(test, report)
            finally:
                os._exit(status)
        status = os.waitstatus_to_exitcode(os.waitpid(pid, 0)[1])
        if status < 0:
            status = 128 - status
        with open(prefix + ".status", "w") as f:
            f.write("%d\n" % status)
        print("%s %.3f" % (idx, time.monotonic() - t0), flush=True)


def main():
    sys.dont_write_bytecode = True
    start, top, test_id = parse_args(sys.argv[1:])
    tests = discover(start, top)
    if os.environ.get("KNOCKOUT_WORKER") == "1":
        worker(tests)
    elif test_id is None:
        print("#!testsuite")
        for name in sorted(tests):
            print(name)
        sys.exit(88)
    elif test_id in tests:
        sys.exit(run_test(tests[test_id], sys.stderr))
    else:
        sys.exit("no such test: " + test_id)


main()
PYTHON3_UNITTEST
}

usage() {
  printf 'usage: %s [run] [-v] [-k] [-t <tap>] [-j <junit.xml>] [-d <dir>]...   # default: test dirs below cwd\n' "${0##*/}" >&2
  printf '       %s fn-suite   # print t_* suite handler; use: source <(knockout.sh fn-suite)\n' "${0##*/}" >&2
  printf '       %s python3-unittest discover [-s START] [-t TOP] [TEST_ID]   # Python unittest worker suite\n' "${0##*/}" >&2
  exit 1
}

# Project mode: test dirs below cwd, marked by name or by a marker file.
discover_test_dirs() {
  find . -mindepth 1 \
    \( -type d -name '.*' -prune \) \
    -o \( -type d -name knockout-tests -print \) \
    -o \( -type f -name .knockout-tests -printf '%h\n' \) \
    | sed 's#^\./##' | LC_ALL=C sort -u
}

V_PASS=0
KEEP_TMP=0
had_test_error=0

cleanup() {
  if [[ "$KEEP_TMP" -eq 0 ]]; then
    rm -rf "$TMPDIR"
  else
    printf 'keeping tmpdir: %s\n' "$TMPDIR" >&2
  fi
}

# Fresh run state. Without argument: own temp dir, removed on exit.
# With a directory (tests): use it, no trap; the caller owns it.
init_run() {
  if [[ -n "${1:-}" ]]; then
    TMPDIR="$1"
  else
    TMPDIR="$(mktemp -d)"
    trap cleanup EXIT
  fi
  had_test_error=0
  TOTAL_TESTS=0
  RUN_IDX=0
  SUITE_LINES_FILE=()
  COUNT_PASS=0 COUNT_FAIL=0 COUNT_SKIP=0 COUNT_NOTRUN=0 COUNT_SUITEERR=0
  REPORT_N=0
  RUN_T0="$EPOCHREALTIME"
  if [[ -n "$TAP_FILE" ]]; then
    printf 'TAP version 13\n' >"$TAP_FILE"
  fi
  if [[ -n "$JUNIT_FILE" ]]; then
    : >"$TMPDIR/junit.cases"
  fi
}

die() {
  printf 'ERROR\n' >&2
  printf 'die: %s\n' "$1" >&2
  exit 1
}

sanitize_name() {
  local __s="$1"
  __s="${__s//\//__}"
  __s="${__s// /_}"
  __s="${__s//:/_}"
  __s="${__s//[^A-Za-z0-9._-]/_}"
  # With $2: assign to that variable instead of printing (no subshell).
  if [[ -n "${2:-}" ]]; then
    printf -v "$2" '%s' "$__s"
  else
    printf '%s' "$__s"
  fi
}

is_sh() { [[ "$1" == *.sh ]]; }

# Testsuite by name: basename ends in ".suite" or contains ".suite.".
is_suite() {
  local b="${1##*/}"
  [[ "$b" == *?.suite || "$b" == *?.suite.* ]]
}

# Turbo testsuite: bash fn-suite sourced once into a worker, see run_turbo_suite.
is_turbo() { [[ "${1##*/}" == *?.turbo.suite.sh ]]; }

# Worker testsuite: any language, runs all cases in one process, see run_worker_suite.
is_worker() {
  local b="${1##*/}"
  [[ "$b" == *?.worker.suite || "$b" == *?.worker.suite.* ]]
}

ensure_dir_ok_or_die() {
  local d="$1"
  [[ -e "$d" ]] || die "path not found: $d"
  [[ -d "$d" ]] || die "expected directory, got file: $d"
  [[ -x "$d" ]] || die "directory not executable: $d"
}

ensure_runnable_file_or_die() {
  local f="$1"
  [[ -e "$f" ]] || die "path not found: $f"
  [[ -d "$f" ]] && die "expected file, got directory: $f"
  if [[ -x "$f" ]]; then
    return 0
  fi
  if is_sh "$f"; then
    return 0
  fi
  die "file not executable and not .sh: $f"
}

report_error() {
  # $1 designation, $2 status, $3 stdout_file, $4 stderr_file, [$5 hint]
  printf 'ERROR\n' >&2
  printf 'test: %s\n' "$1" >&2
  printf 'status: %s\n' "$2" >&2
  if [[ -n "${5:-}" ]]; then
    printf 'hint: %s\n' "$5" >&2
  fi

  printf '%s\n' '--- stdout ---' >&2
  if [[ -s "$3" ]]; then
    cat "$3" >&2
    tail -c 1 "$3" | od -An -tx1 | grep -qi '0a' || printf '\n' >&2
  else
    printf '(empty)\n' >&2
  fi

  printf '%s\n' '--- stderr ---' >&2
  if [[ -s "$4" ]]; then
    cat "$4" >&2
    tail -c 1 "$4" | od -An -tx1 | grep -qi '0a' || printf '\n' >&2
  else
    printf '(empty)\n' >&2
  fi

  had_test_error=1
}

# --- results: counters, summary, TAP and JUnit reports ---
COUNT_PASS=0 COUNT_FAIL=0 COUNT_SKIP=0 COUNT_NOTRUN=0 COUNT_SUITEERR=0
REPORT_N=0
RUN_T0=""
TAP_FILE=""
JUNIT_FILE=""

# Outcome of a finished test into variable $3: stderr output or a status other
# than 0 and 77 is "fail", 77 is "skip", 0 is "pass". $1 status, $2 stderr file.
classify_outcome() {
  local __o=fail
  if [[ ! -s "$2" ]]; then
    case "$1" in
      0) __o=pass ;;
      77) __o=skip ;;
    esac
  fi
  printf -v "$3" '%s' "$__o"
}

# Records one result. $1 designation, $2 outcome: pass, fail, skip, notrun,
# notrun-quiet (not run, explained by a suite error already) or suiteerror.
# $3 status, $4 seconds, $5 stdout file, $6 stderr file, [$7 hint].
record_result() {
  case "$2" in
    pass) COUNT_PASS=$((COUNT_PASS + 1)) ;;
    skip) COUNT_SKIP=$((COUNT_SKIP + 1)) ;;
    fail) COUNT_FAIL=$((COUNT_FAIL + 1)); report_error "$1" "$3" "$5" "$6" "${7:-}" ;;
    notrun) COUNT_NOTRUN=$((COUNT_NOTRUN + 1)); report_error "$1" "$3" "$5" "$6" "${7:-}" ;;
    notrun-quiet) COUNT_NOTRUN=$((COUNT_NOTRUN + 1)) ;;
    suiteerror) COUNT_SUITEERR=$((COUNT_SUITEERR + 1)); report_error "$1" "$3" "$5" "$6" "${7:-}" ;;
    *) die "unknown outcome: $2" ;;
  esac
  REPORT_N=$((REPORT_N + 1))
  if [[ -n "$TAP_FILE" ]]; then
    tap_entry "$@"
  fi
  if [[ -n "$JUNIT_FILE" ]]; then
    junit_entry "$@"
  fi
}

tap_entry() {
  local hash='\#' name
  name="${1//[#]/"$hash"}"
  case "$2" in
    pass) printf 'ok %d - %s\n' "$REPORT_N" "$name" ;;
    skip) printf 'ok %d - %s # SKIP\n' "$REPORT_N" "$name" ;;
    *)
      printf 'not ok %d - %s\n' "$REPORT_N" "$name"
      printf '# %s, status %s\n' "${2%-quiet}" "$3"
      if [[ -n "${7:-}" ]]; then
        printf '# %s\n' "$7"
      fi
      ;;
  esac >>"$TAP_FILE"
}

XML_BAD_CHARS=$'[\001-\010\013\014\016-\037]'

# XML-escapes $1 into variable $2 (no subshell). Drops characters XML forbids.
xml_escape() {
  local __s="$1" __amp='&amp;' __lt='&lt;' __gt='&gt;' __quot='&quot;'
  __s="${__s//&/"$__amp"}"
  __s="${__s//</"$__lt"}"
  __s="${__s//>/"$__gt"}"
  __s="${__s//\"/"$__quot"}"
  __s="${__s//$XML_BAD_CHARS/}"
  printf -v "$2" '%s' "$__s"
}

# XML-escaped content of file $1 into variable $2.
xml_escape_file() {
  local __c=""
  IFS= read -r -d '' __c <"$1" || true
  xml_escape "$__c" "$2"
}

junit_entry() {
  local class name time="$4" msg body sout serr
  if [[ "$1" == *::* ]]; then
    xml_escape "${1%%::*}" class
    xml_escape "${1#*::}" name
  else
    xml_escape "$1" class
    name="$class"
  fi
  [[ "$time" == [0-9]* ]] || time=0
  {
    printf '    <testcase classname="%s" name="%s" time="%s">\n' "$class" "$name" "$time"
    case "$2" in
      pass) ;;
      skip) printf '      <skipped/>\n' ;;
      fail)
        xml_escape "exit status $3${7:+: $7}" msg
        xml_escape_file "$6" body
        printf '      <failure message="%s">%s</failure>\n' "$msg" "$body"
        ;;
      *)
        xml_escape "${2%-quiet}, status $3${7:+: $7}" msg
        printf '      <error message="%s"/>\n' "$msg"
        ;;
    esac
    if [[ "$2" != pass ]]; then
      xml_escape_file "$5" sout
      xml_escape_file "$6" serr
      printf '      <system-out>%s</system-out>\n' "$sout"
      printf '      <system-err>%s</system-err>\n' "$serr"
    fi
    printf '    </testcase>\n'
  } >>"$TMPDIR/junit.cases"
}

# After all tests: TAP plan line, JUnit file, summary line on stdout.
finish_run() {
  local secs total
  elapsed_secs "$RUN_T0" "$EPOCHREALTIME" secs
  total=$((COUNT_PASS + COUNT_FAIL + COUNT_SKIP + COUNT_NOTRUN))
  if [[ -n "$TAP_FILE" ]]; then
    printf '1..%d\n' "$REPORT_N" >>"$TAP_FILE"
  fi
  if [[ -n "$JUNIT_FILE" ]]; then
    {
      printf '<?xml version="1.0" encoding="UTF-8"?>\n<testsuites>\n'
      printf '  <testsuite name="knockout.sh" tests="%d" failures="%d" errors="%d" skipped="%d" time="%s">\n' \
        "$REPORT_N" "$COUNT_FAIL" $((COUNT_NOTRUN + COUNT_SUITEERR)) "$COUNT_SKIP" "$secs"
      cat "$TMPDIR/junit.cases"
      printf '  </testsuite>\n</testsuites>\n'
    } >"$JUNIT_FILE"
  fi
  printf '%d tests: %d passed, %d failed, %d skipped, %d not run, %d suite errors  %ss\n' \
    "$total" "$COUNT_PASS" "$COUNT_FAIL" "$COUNT_SKIP" "$COUNT_NOTRUN" "$COUNT_SUITEERR" "$secs"
}

# --- testsuite line parsing ---
PARSED_ARGS=()

parse_suite_line() {
  local line="$1"
  PARSED_ARGS=()

  if [[ "$line" == *$'\t'* ]]; then
    local IFS=$'\t'
    # shellcheck disable=SC2206
    PARSED_ARGS=($line)
    return 0
  fi

  # Bash-style parsing via eval; suite output is assumed trusted input.
  eval "PARSED_ARGS=($line)"
}

format_args_for_designation() {
  local -a args=("$@")
  if [[ "${#args[@]}" -eq 0 ]]; then
    printf ''
    return 0
  fi
  printf '%q ' "${args[@]}" | sed 's/ $//'
}

extract_description_from_stdout() {
  # $1 stdout file, $2 variable to assign the description to (no subshell).
  local __first="" __desc=""
  IFS= read -r __first <"$1" || true
  if [[ "$__first" == '# '* ]]; then
    __desc="${__first:2}"
  fi
  printf -v "$2" '%s' "$__desc"
}

is_testsuite_output() {
  local first=""
  IFS= read -r first <"$1" || true
  [[ "$first" == "#!testsuite" ]]
}

write_testsuite_lines() {
  # Drop the "#!testsuite" marker and "# " description lines.
  local line skip=1
  {
    while IFS= read -r line || [[ -n "$line" ]]; do
      if (( skip )); then skip=0; continue; fi
      [[ "$line" == '# '* ]] && continue
      printf '%s\n' "$line"
    done <"$1"
  } >"$2"
}

# --- execution wrapper ---
RUN_STATUS=0
RUN_DT="0.000000"
RUN_DESC=""

run_once_capture() {
  # $1 file, $2 designation, $3 phase, $4 idx, $5 total, $6 out, $7 err, $8 status_file, $@ args
  local file="$1"
  local designation="$2"
  local phase="$3"
  local idx="$4"
  local total="$5"
  local out_file="$6"
  local err_file="$7"
  local status_file="$8"
  shift 8

  : >"$out_file"
  : >"$err_file"
  : >"$status_file"

  local start end
  start="$EPOCHREALTIME"

  set +e
  if [[ -x "$file" ]]; then
    if [[ "$V_PASS" -eq 1 ]]; then
      "$file" "$@" > >(tee "$out_file") 2> >(tee "$err_file" >&2)
    else
      "$file" "$@" >"$out_file" 2>"$err_file"
    fi
  else
    if [[ "$V_PASS" -eq 1 ]]; then
      bash "$file" "$@" > >(tee "$out_file") 2> >(tee "$err_file" >&2)
    else
      bash "$file" "$@" >"$out_file" 2>"$err_file"
    fi
  fi
  RUN_STATUS=$?
  set -e

  printf '%s\n' "$RUN_STATUS" >"$status_file"

  end="$EPOCHREALTIME"
  elapsed_secs "$start" "$end" RUN_DT

  if [[ "$RUN_STATUS" -eq 88 ]] && is_testsuite_output "$out_file"; then
    RUN_DESC=""
  else
    extract_description_from_stdout "$out_file" RUN_DESC
  fi

  local mark=""
  if [[ "$phase" != L && "$RUN_STATUS" -eq 77 && ! -s "$err_file" ]]; then
    mark=SKIP
  fi
  print_progress "$phase" "$idx" "$total" "$designation" "$RUN_DT" "$RUN_DESC" "$mark"
}

print_progress() {
  # $1 phase, $2 idx, $3 total, $4 designation, $5 seconds, $6 description, [$7 SKIP]
  local mark="${7:+  $7}"
  if [[ -n "$6" ]]; then
    printf '[%s %d/%d] %s  %ss%s  -- %s\n' "$1" "$2" "$3" "$4" "$5" "$mark" "$6"
  else
    printf '[%s %d/%d] %s  %ss%s\n' "$1" "$2" "$3" "$4" "$5" "$mark"
  fi
}

FILES=()
collect_files_or_die() {
  FILES=()
  local arg
  for arg in "$@"; do
    [[ -e "$arg" ]] || die "path not found: $arg"
    if [[ -d "$arg" ]]; then
      ensure_dir_ok_or_die "$arg"
      while IFS= read -r -d '' f; do
        FILES+=("$f")
      done < <(find "$arg" -maxdepth 1 -type f ! -name .knockout-tests -print0)
    else
      FILES+=("$arg")
    fi
  done
}

declare -gA SUITE_LINES_FILE
TOTAL_TESTS=0

# Count runnable test invocations in a suite lines file.
count_suite_lines() {
  local line c=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "${line//[[:space:]]/}" ]] && c=$((c + 1))
  done <"$1"
  printf '%d' "$c"
}

# Elapsed seconds (3 decimals) between two $EPOCHREALTIME values into variable $3.
elapsed_secs() {
  local us=$(( ${2//[.,]/} - ${1//[.,]/} ))
  printf -v "$3" '%d.%03d' $(( us / 1000000 )) $(( us % 1000000 / 1000 ))
}

phase_L() {
  local -a suites=()
  local f
  for f in "${FILES[@]}"; do
    ensure_runnable_file_or_die "$f"
    if is_suite "$f"; then
      suites+=("$f")
    else
      TOTAL_TESTS=$((TOTAL_TESTS + 1))
    fi
  done

  local i n
  for i in "${!suites[@]}"; do
    f="${suites[$i]}"
    n=$((i + 1))

    local base out err st suite_lines
    sanitize_name "$f" base
    out="$TMPDIR/${base}.out"
    err="$TMPDIR/${base}.err"
    st="$TMPDIR/${base}.status"
    suite_lines="$TMPDIR/${base}.suite"
    : >"$suite_lines"
    SUITE_LINES_FILE["$f"]="$suite_lines"

    run_once_capture "$f" "$f" "L" "$n" "${#suites[@]}" "$out" "$err" "$st"
    local status
    status="$(<"$st")"

    if [[ "$status" -ne 88 ]] || ! is_testsuite_output "$out" || [[ -s "$err" ]]; then
      record_result "$f" suiteerror "$status" "$RUN_DT" "$out" "$err" \
        'testsuite listing must exit 88, start stdout with "#!testsuite" and write no stderr'
      continue
    fi

    write_testsuite_lines "$out" "$suite_lines"
    TOTAL_TESTS=$((TOTAL_TESTS + $(count_suite_lines "$suite_lines")))
  done
}

RUN_IDX=0

run_simple() {
  local f="$1"
  RUN_IDX=$((RUN_IDX + 1))

  local base out err st
  sanitize_name "$f" base
  out="$TMPDIR/${base}.out"
  err="$TMPDIR/${base}.err"
  st="$TMPDIR/${base}.status"

  run_once_capture "$f" "$f" "T" "$RUN_IDX" "$TOTAL_TESTS" "$out" "$err" "$st"
  local status
  status="$(<"$st")"

  if [[ "$status" -eq 88 ]] && is_testsuite_output "$out"; then
    record_result "$f" fail "$status" "$RUN_DT" "$out" "$err" \
      'testsuite output from a file not named as testsuite; rename it to *.suite or *.suite.<ext>'
  else
    local outcome
    classify_outcome "$status" "$err" outcome
    record_result "$f" "$outcome" "$status" "$RUN_DT" "$out" "$err"
  fi
}

# Sets CASE_DESIGNATION for a suite file and one parsed invocation.
CASE_DESIGNATION=""
suite_case_designation() {
  local suite="$1"
  shift
  local testname="${1:-}" rest_argstr=""
  if [[ "$#" -gt 1 ]]; then
    rest_argstr="$(format_args_for_designation "${@:2}")"
  fi
  if [[ -z "$testname" ]]; then
    CASE_DESIGNATION="$suite"
  elif [[ -n "$rest_argstr" ]]; then
    CASE_DESIGNATION="${suite}::${testname} (${rest_argstr})"
  else
    CASE_DESIGNATION="${suite}::${testname}"
  fi
}

run_suite() {
  local suite="$1"
  local suite_lines="${SUITE_LINES_FILE[$suite]}"

  local line
  while IFS= read -r line; do
    [[ -z "${line//[[:space:]]/}" ]] && continue

    parse_suite_line "$line"
    local -a args=("${PARSED_ARGS[@]}")

    RUN_IDX=$((RUN_IDX + 1))

    suite_case_designation "$suite" "${args[@]}"
    local designation="$CASE_DESIGNATION"

    local base out err st
    sanitize_name "$designation" base
    out="$TMPDIR/${base}.out"
    err="$TMPDIR/${base}.err"
    st="$TMPDIR/${base}.status"

    # stdin /dev/null: the loop's stdin is the suite lines file (same as turbo cases).
    run_once_capture "$suite" "$designation" "S" "$RUN_IDX" "$TOTAL_TESTS" "$out" "$err" "$st" "${args[@]}" </dev/null
    local status
    status="$(<"$st")"

    local outcome
    classify_outcome "$status" "$err" outcome
    record_result "$designation" "$outcome" "$status" "$RUN_DT" "$out" "$err"
  done <"$suite_lines"
}

# Worker for turbo suites. Runs as: bash -c "$TURBO_WORKER" ko-turbo SUITE CASES TMPDIR V_PASS SRCBASE
# Reads cases (NUL separated: idx base argc args...) from fd 5, reports on fd 3:
#   "SOURCED" once after a clean source, then "idx seconds" per finished case.
read -r -d '' TURBO_WORKER <<'WORKER' || true
__ko_suite="$1" __ko_cases="$2" __ko_tmp="$3" __ko_vpass="$4" __ko_src="$5"
set --
source "$__ko_suite" >"$__ko_src.out" 2>"$__ko_src.err"
__ko_rc=$?
__ko_opts="$(set +o)"
__ko_shopts="$(shopt -p)"
set +euo pipefail
trap - ERR EXIT
[[ "$__ko_rc" -eq 0 && ! -s "$__ko_src.err" ]] || exit "$(( __ko_rc ? __ko_rc : 1 ))"
printf 'SOURCED\n' >&3


exec 5<"$__ko_cases"
while IFS= read -r -d '' -u 5 __ko_idx && IFS= read -r -d '' -u 5 __ko_base \
      && IFS= read -r -d '' -u 5 __ko_argc; do
  __ko_args=()
  for (( __ko_i = 0; __ko_i < __ko_argc; __ko_i++ )); do
    IFS= read -r -d '' -u 5 __ko_a
    __ko_args+=("$__ko_a")
  done
  # Same argument handling as testsuite_main: skip leading --options.
  while (( ${#__ko_args[@]} )); do
    case "${__ko_args[0]}" in
      --) __ko_args=("${__ko_args[@]:1}"); break ;;
      --*) __ko_args=("${__ko_args[@]:1}") ;;
      *) break ;;
    esac
  done
  __ko_out="$__ko_tmp/$__ko_base.out"
  __ko_err="$__ko_tmp/$__ko_base.err"
  __ko_fn="${TESTSUITE_PREFIX:-t_}${__ko_args[0]:-}"

  __ko_t0=$EPOCHREALTIME
  if (( ${#__ko_args[@]} )) && declare -F "$__ko_fn" >/dev/null; then
    if [[ "$__ko_vpass" -eq 1 ]]; then
      ( exec 3>&- 5<&-; eval "$__ko_opts"; eval "$__ko_shopts"; "$__ko_fn" "${__ko_args[@]:1}" ) \
        </dev/null > >(tee "$__ko_out") 2> >(tee "$__ko_err" >&2)
    else
      ( exec 3>&- 5<&-; eval "$__ko_opts"; eval "$__ko_shopts"; "$__ko_fn" "${__ko_args[@]:1}" ) \
        </dev/null >"$__ko_out" 2>"$__ko_err"
    fi
    __ko_st=$?
  else
    : >"$__ko_out"
    printf 'Error: no such test: %s\n' "${__ko_args[0]:-}" >"$__ko_err"
    __ko_st=1
  fi
  __ko_t1=$EPOCHREALTIME

  printf '%s\n' "$__ko_st" >"$__ko_tmp/$__ko_base.status"
  __ko_us=$(( ${__ko_t1//[.,]/} - ${__ko_t0//[.,]/} ))
  printf '%s %d.%03d\n' "$__ko_idx" $(( __ko_us / 1000000 )) $(( __ko_us % 1000000 / 1000 )) >&3
done
WORKER

run_turbo_suite() {
  local suite="$1"
  local suite_lines="${SUITE_LINES_FILE[$suite]}"
  local sbase cases wst src
  sanitize_name "$suite" sbase
  cases="$TMPDIR/${sbase}.cases"
  wst="$TMPDIR/${sbase}.worker-status"
  src="$TMPDIR/${sbase}.source"
  : >"$cases"

  REPORT_DESIGNATIONS=()
  REPORT_BASES=()
  local line idx="$RUN_IDX"
  local first=$((RUN_IDX + 1))
  while IFS= read -r line; do
    [[ -z "${line//[[:space:]]/}" ]] && continue
    parse_suite_line "$line"
    idx=$((idx + 1))
    suite_case_designation "$suite" "${PARSED_ARGS[@]}"
    REPORT_DESIGNATIONS[idx]="$CASE_DESIGNATION"
    sanitize_name "$CASE_DESIGNATION" "REPORT_BASES[$idx]"
    printf '%s\0%s\0%s\0' "$idx" "${REPORT_BASES[idx]}" "${#PARSED_ARGS[@]}" >>"$cases"
    if [[ "${#PARSED_ARGS[@]}" -gt 0 ]]; then
      printf '%s\0' "${PARSED_ARGS[@]}" >>"$cases"
    fi
  done <"$suite_lines"
  local last="$idx"
  [[ "$last" -ge "$first" ]] || return 0

  exec 4>&1
  read_worker_reports SOURCED 0 < <(
    bash -c "$TURBO_WORKER" ko-turbo "$suite" "$cases" "$TMPDIR" "$V_PASS" "$src" 3>&1 1>&4
    printf '%s\n' "$?" >"$wst"
  )
  wait "$!" || true
  exec 4>&-

  local wstatus
  wstatus="$(cat "$wst" 2>/dev/null || printf '?')"
  if [[ "$REPORT_SETUP" -eq 0 && -z "$REPORT_BAD" ]]; then
    record_result "$suite" suiteerror "$wstatus" 0 "$src.out" "$src.err" \
      "turbo suite failed while being sourced; its $((last - first + 1)) tests were not run"
    report_unreported "$last" "$wstatus" "" quiet
    return 0
  elif [[ -n "$REPORT_BAD" ]]; then
    record_result "$suite" suiteerror "$wstatus" 0 /dev/null /dev/null "unexpected worker report: $REPORT_BAD"
  fi
  report_unreported "$last" "$wstatus" "turbo worker aborted before this test ran"
}

# Reads worker reports from stdin: the setup token once, then "INDEX SECONDS" per
# finished case, in order. Per report: progress line and error report from the
# case's .out/.err/.status files. $1 setup token, $2 1 = print captured output
# (worker suites with -v). Uses REPORT_DESIGNATIONS and REPORT_BASES (by index).
# Sets REPORT_SETUP (1 once the token was read) and REPORT_BAD (unexpected line).
REPORT_DESIGNATIONS=()
REPORT_BASES=()
REPORT_SETUP=0
REPORT_BAD=""
read_worker_reports() {
  local token="$1" show="$2" line got dt status out err st desc outcome mark
  REPORT_SETUP=0
  REPORT_BAD=""
  while IFS= read -r line; do
    if [[ "$REPORT_SETUP" -eq 0 && "$line" == "$token" ]]; then
      REPORT_SETUP=1
      continue
    fi
    got="${line%% *}"
    dt="${line#* }"
    if [[ "$REPORT_SETUP" -eq 0 || "$line" != *' '* || "$got" != "$((RUN_IDX + 1))" \
          || ! "$dt" =~ ^[0-9]+(\.[0-9]+)?$ || -z "${REPORT_BASES[got]:-}" ]]; then
      REPORT_BAD="$line"
      break
    fi
    RUN_IDX="$got"
    out="$TMPDIR/${REPORT_BASES[got]}.out"
    err="$TMPDIR/${REPORT_BASES[got]}.err"
    st="$TMPDIR/${REPORT_BASES[got]}.status"
    status="$(<"$st")"
    if [[ "$show" -eq 1 ]]; then
      cat "$out"
      cat "$err" >&2
    fi
    extract_description_from_stdout "$out" desc
    classify_outcome "$status" "$err" outcome
    mark=""
    [[ "$outcome" != skip ]] || mark=SKIP
    print_progress "S" "$RUN_IDX" "$TOTAL_TESTS" "${REPORT_DESIGNATIONS[got]}" "$dt" "$desc" "$mark"
    record_result "${REPORT_DESIGNATIONS[got]}" "$outcome" "$status" "$dt" "$out" "$err"
  done
}

# Records the cases after RUN_IDX up to $1 as not run, then sets RUN_IDX to $1.
# $2 worker status, $3 hint, [$4 "quiet": no error report per case].
report_unreported() {
  local last="$1" idx outcome=notrun
  [[ "${4:-}" != quiet ]] || outcome=notrun-quiet
  for (( idx = RUN_IDX + 1; idx <= last; idx++ )); do
    record_result "${REPORT_DESIGNATIONS[idx]}" "$outcome" "$2" 0 /dev/null /dev/null "$3"
  done
  RUN_IDX="$last"
}

# Worker suite: started once with KNOCKOUT_WORKER=1, cases on stdin as
# "INDEX<TAB>PREFIX<TAB>LINE", reports on stdout (see "Worker testsuites" above).
run_worker_suite() {
  local suite="$1"
  local suite_lines="${SUITE_LINES_FILE[$suite]}"
  local sbase cases wst werr tmp
  sanitize_name "$suite" sbase
  cases="$TMPDIR/${sbase}.cases"
  wst="$TMPDIR/${sbase}.worker-status"
  werr="$TMPDIR/${sbase}.worker.err"
  tmp="$TMPDIR"
  [[ "$tmp" == /* ]] || tmp="$PWD/$tmp"

  REPORT_DESIGNATIONS=()
  REPORT_BASES=()
  local line idx="$RUN_IDX"
  local first=$((RUN_IDX + 1))
  {
    while IFS= read -r line; do
      [[ -z "${line//[[:space:]]/}" ]] && continue
      parse_suite_line "$line"
      idx=$((idx + 1))
      suite_case_designation "$suite" "${PARSED_ARGS[@]}"
      REPORT_DESIGNATIONS[idx]="$CASE_DESIGNATION"
      sanitize_name "$CASE_DESIGNATION" "REPORT_BASES[$idx]"
      printf '%s\t%s\t%s\n' "$idx" "$tmp/${REPORT_BASES[idx]}" "$line"
    done <"$suite_lines"
  } >"$cases"
  local last="$idx"
  [[ "$last" -ge "$first" ]] || return 0

  read_worker_reports '#!worker' "$V_PASS" < <(
    rc=0
    if [[ -x "$suite" ]]; then
      KNOCKOUT_WORKER=1 "$suite" <"$cases" 2>"$werr" || rc=$?
    else
      KNOCKOUT_WORKER=1 bash "$suite" <"$cases" 2>"$werr" || rc=$?
    fi
    printf '%s\n' "$rc" >"$wst"
  )
  wait "$!" || true

  local wstatus
  wstatus="$(cat "$wst" 2>/dev/null || printf '?')"
  if [[ -n "$REPORT_BAD" ]]; then
    record_result "$suite" suiteerror "$wstatus" 0 /dev/null "$werr" "unexpected worker report: $REPORT_BAD"
  elif [[ "$REPORT_SETUP" -eq 0 ]]; then
    record_result "$suite" suiteerror "$wstatus" 0 /dev/null "$werr" \
      "worker suite printed no \"#!worker\" line; its $((last - first + 1)) tests were not run"
    report_unreported "$last" "$wstatus" "" quiet
    return 0
  elif [[ "$wstatus" != 0 || -s "$werr" || "$RUN_IDX" -lt "$last" ]]; then
    record_result "$suite" suiteerror "$wstatus" 0 /dev/null "$werr" \
      'worker suite must report every test, write no stderr and exit 0'
  fi
  report_unreported "$last" "$wstatus" "worker aborted before this test ran"
}

phase_R() {
  local f
  for f in "${FILES[@]}"; do
    if is_turbo "$f"; then
      run_turbo_suite "$f"
    elif is_worker "$f"; then
      run_worker_suite "$f"
    elif is_suite "$f"; then
      run_suite "$f"
    else
      run_simple "$f"
    fi
  done
}

# Run the given files/dirs: collect, phase L, phase R. Requires init_run.
run_paths() {
  collect_files_or_die "$@"
  phase_L
  phase_R
}

TEST_DIRS=()
OPT_SHIFT=0

# Parse -v -k -d <dir>; sets OPT_SHIFT to the number of consumed arguments.
parse_options() {
  local opt OPTIND=1
  while getopts ":vkd:t:j:" opt; do
    case "$opt" in
      v) V_PASS=1 ;;
      k) KEEP_TMP=1 ;;
      d) TEST_DIRS+=("$OPTARG") ;;
      t) TAP_FILE="$OPTARG" ;;
      j) JUNIT_FILE="$OPTARG" ;;
      *) usage ;;
    esac
  done
  OPT_SHIFT=$((OPTIND - 1))
}

main() {
  parse_options "$@"
  shift "$OPT_SHIFT"

  local cmd="${1:-run}"
  [[ "$#" -eq 0 ]] || shift
  case "$cmd" in
    fn-suite)
      [[ "$#" -eq 0 ]] || usage
      print_fn_suite
      exit 0
      ;;
    python3-unittest)
      exec python3 -c "$(print_python3_unittest)" "$@"
      ;;
    run) ;;
    *)
      printf 'unknown command: %s\n' "$cmd" >&2
      usage
      ;;
  esac

  parse_options "$@"
  shift "$OPT_SHIFT"
  [[ "$#" -eq 0 ]] || { printf 'unexpected argument: %s\n' "$1" >&2; usage; }

  local d
  if [[ "${#TEST_DIRS[@]}" -eq 0 ]]; then
    mapfile -t TEST_DIRS < <(discover_test_dirs)
    if [[ "${#TEST_DIRS[@]}" -eq 0 ]]; then
      printf 'no test dirs found (knockout-tests/ or .knockout-tests) below %s\n' "$PWD" >&2
      usage
    fi
  else
    for d in "${TEST_DIRS[@]}"; do
      [[ -e "$d" ]] || die "path not found: $d"
      [[ -d "$d" ]] || die "expected directory, got file: $d"
    done
  fi

  # Suites calling `knockout.sh fn-suite` get this same knockout.sh, installed or not.
  PATH="$(dirname "$(readlink -f "$0")"):$PATH"
  export PATH

  init_run
  run_paths "${TEST_DIRS[@]}"
  finish_run

  if [[ "$had_test_error" -ne 0 ]]; then
    exit 1
  fi
  exit 0
}

# Sourced: define functions and defaults only.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
