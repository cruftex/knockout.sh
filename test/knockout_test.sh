#!/usr/bin/env bash
set -euo pipefail

KO_UNDER_TEST="${KO_UNDER_TEST:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/knockout}"

ROOT="$(mktemp -d "${TMPDIR:-/tmp}/ko-test.XXXXXXXXXX")"
trap 'rm -rf "$ROOT"' EXIT

PASS_COUNT=0
FAIL_COUNT=0
XFAIL_COUNT=0
XPASS_COUNT=0
RUN_STATUS=0

fail_msg() {
  printf '    %s\n' "$*" >&2
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local label="${3:-values differ}"

  if [[ "$expected" != "$actual" ]]; then
    fail_msg "$label"
    fail_msg "expected: $expected"
    fail_msg "actual:   $actual"
    return 1
  fi
}

assert_file_empty() {
  local path="$1"
  if [[ -s "$path" ]]; then
    fail_msg "expected empty file: $path"
    sed 's/^/      | /' "$path" >&2
    return 1
  fi
}

assert_contains() {
  local path="$1"
  local needle="$2"

  if ! grep -Fq -- "$needle" "$path"; then
    fail_msg "expected $path to contain: $needle"
    sed 's/^/      | /' "$path" >&2
    return 1
  fi
}

assert_not_contains() {
  local path="$1"
  local needle="$2"

  if grep -Fq -- "$needle" "$path"; then
    fail_msg "expected $path not to contain: $needle"
    sed 's/^/      | /' "$path" >&2
    return 1
  fi
}

assert_line_count_regex() {
  local path="$1"
  local regex="$2"
  local expected="$3"
  local count

  count="$(grep -Ec -- "$regex" "$path" || true)"
  assert_eq "$expected" "$count" "unexpected matching line count for $regex"
}

run_ko() {
  local out_file="$1"
  local err_file="$2"
  shift 2

  : >"$out_file"
  : >"$err_file"

  set +e
  "$KO_UNDER_TEST" "$@" >"$out_file" 2>"$err_file"
  RUN_STATUS=$?
  set -e
}

make_executable() {
  chmod +x "$1"
}

case_dir() {
  local name="$1"
  mkdir -p "$ROOT/$name"
  printf '%s' "$ROOT/$name"
}

run_case() {
  local name="$1"
  local fn="$2"

  printf 'TEST %s\n' "$name"
  if "$fn"; then
    PASS_COUNT=$((PASS_COUNT + 1))
    printf '  PASS\n'
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    printf '  FAIL\n'
  fi
}

run_xfail_case() {
  local name="$1"
  local fn="$2"
  local diag
  diag="$(mktemp "$ROOT/xfail.XXXXXXXXXX")"

  printf 'TEST %s\n' "$name"
  if "$fn" 2>"$diag"; then
    XPASS_COUNT=$((XPASS_COUNT + 1))
    printf '  XPASS\n'
    if [[ -s "$diag" ]]; then
      sed 's/^/    /' "$diag" >&2
    fi
  else
    XFAIL_COUNT=$((XFAIL_COUNT + 1))
    printf '  XFAIL\n'
    if [[ -s "$diag" ]]; then
      sed 's/^/    expected failure: /' "$diag"
    fi
  fi
}

test_usage_without_args() {
  local d out err
  d="$(case_dir usage)"
  out="$d/out"
  err="$d/err"

  run_ko "$out" "$err"
  assert_eq "1" "$RUN_STATUS" "usage should exit 1" || return
  assert_file_empty "$out" || return
  assert_contains "$err" "usage: ${KO_UNDER_TEST##*/} [-v] [-d] <file-or-dir>..." || return
}

test_executable_success_and_description() {
  local d t out err
  d="$(case_dir executable-success)"
  t="$d/pass"
  out="$d/out"
  err="$d/err"

  cat >"$t" <<'SCRIPT'
#!/usr/bin/env bash
printf '# executable test passed\n'
SCRIPT
  make_executable "$t"

  run_ko "$out" "$err" "$t"
  assert_eq "0" "$RUN_STATUS" "successful executable should exit 0" || return
  assert_file_empty "$err" || return
  assert_contains "$out" "[T 1/1] $t" || return
  assert_contains "$out" "-- executable test passed" || return
}

test_non_executable_sh_runs_with_bash() {
  local d t out err
  d="$(case_dir sh-fallback)"
  t="$d/pass.sh"
  out="$d/out"
  err="$d/err"

  cat >"$t" <<'SCRIPT'
[[ "abc" == a* ]]
printf '# bash fallback worked\n'
SCRIPT

  run_ko "$out" "$err" "$t"
  assert_eq "0" "$RUN_STATUS" "non-executable .sh should run with bash" || return
  assert_file_empty "$err" || return
  assert_contains "$out" "-- bash fallback worked" || return
}

test_rejects_non_executable_non_sh() {
  local d t out err
  d="$(case_dir rejects-non-runnable)"
  t="$d/not-runnable.txt"
  out="$d/out"
  err="$d/err"

  printf 'echo no\n' >"$t"

  run_ko "$out" "$err" "$t"
  assert_eq "1" "$RUN_STATUS" "non-runnable file should exit 1" || return
  assert_file_empty "$out" || return
  assert_contains "$err" "ERROR" || return
  assert_contains "$err" "die: file not executable and not .sh: $t" || return
}

test_stderr_marks_failure() {
  local d t out err
  d="$(case_dir stderr-failure)"
  t="$d/stderr-pass"
  out="$d/out"
  err="$d/err"

  cat >"$t" <<'SCRIPT'
#!/usr/bin/env bash
printf 'stdout body\n'
printf 'stderr body\n' >&2
SCRIPT
  make_executable "$t"

  run_ko "$out" "$err" "$t"
  assert_eq "1" "$RUN_STATUS" "stderr output should fail the run" || return
  assert_contains "$err" "ERROR" || return
  assert_contains "$err" "status: 0" || return
  assert_contains "$err" "stdout body" || return
  assert_contains "$err" "stderr body" || return
}

test_nonzero_failure_continues() {
  local d fail pass out err
  d="$(case_dir failure-continues)"
  fail="$d/01_fail"
  pass="$d/02_pass"
  out="$ROOT/failure-continues.out"
  err="$ROOT/failure-continues.err"

  cat >"$fail" <<'SCRIPT'
#!/usr/bin/env bash
printf 'bad stdout\n'
exit 7
SCRIPT
  cat >"$pass" <<'SCRIPT'
#!/usr/bin/env bash
printf '# later test still ran\n'
SCRIPT
  make_executable "$fail"
  make_executable "$pass"

  run_ko "$out" "$err" "$d"
  assert_eq "1" "$RUN_STATUS" "suite with failing test should exit 1" || return
  assert_contains "$out" "$fail" || return
  assert_contains "$out" "$pass" || return
  assert_line_count_regex "$out" '^\[T [0-9]+/2\]' "2" || return
  assert_contains "$err" "status: 7" || return
  assert_contains "$err" "bad stdout" || return
}

test_directory_expansion_is_non_recursive() {
  local d top nested out err
  d="$(case_dir directory-nonrecursive)"
  mkdir -p "$d/nested"
  top="$d/top"
  nested="$d/nested/should-not-run"
  out="$ROOT/directory-nonrecursive.out"
  err="$ROOT/directory-nonrecursive.err"

  cat >"$top" <<'SCRIPT'
#!/usr/bin/env bash
printf '# top-level file ran\n'
SCRIPT
  cat >"$nested" <<'SCRIPT'
#!/usr/bin/env bash
printf 'nested ran\n' >&2
exit 99
SCRIPT
  make_executable "$top"
  make_executable "$nested"

  run_ko "$out" "$err" "$d"
  assert_eq "0" "$RUN_STATUS" "nested files should not be expanded" || return
  assert_file_empty "$err" || return
  assert_contains "$out" "$top" || return
  assert_not_contains "$out" "$nested" || return
}

test_keep_tmp_writes_artifacts() {
  local d t out err kept
  d="$(case_dir keep-tmp)"
  t="$d/pass"
  out="$d/out"
  err="$d/err"

  cat >"$t" <<'SCRIPT'
#!/usr/bin/env bash
printf '# kept artifacts\n'
SCRIPT
  make_executable "$t"

  run_ko "$out" "$err" -d "$t"
  assert_eq "0" "$RUN_STATUS" "-d run should pass" || return
  kept="$(sed -n 's/^keeping tmpdir: //p' "$err" | tail -n 1)"
  [[ -n "$kept" ]] || { fail_msg "missing kept tmpdir line"; return 1; }
  [[ -d "$kept" ]] || { fail_msg "kept tmpdir does not exist: $kept"; return 1; }
  find "$kept" -name '*.out' -print -quit | grep -q . || { fail_msg "missing .out artifact"; return 1; }
  find "$kept" -name '*.err' -print -quit | grep -q . || { fail_msg "missing .err artifact"; return 1; }
  find "$kept" -name '*.status' -print -quit | grep -q . || { fail_msg "missing .status artifact"; return 1; }
  rm -rf "$kept"
}

test_verbose_passes_through_stdout() {
  local d t out err
  d="$(case_dir verbose)"
  t="$d/pass"
  out="$d/out"
  err="$d/err"

  cat >"$t" <<'SCRIPT'
#!/usr/bin/env bash
printf '# visible description\n'
printf 'visible stdout\n'
SCRIPT
  make_executable "$t"

  run_ko "$out" "$err" -v "$t"
  assert_eq "0" "$RUN_STATUS" "-v run should pass" || return
  assert_file_empty "$err" || return
  assert_contains "$out" "visible stdout" || return
  assert_contains "$out" "-- visible description" || return
}

test_testsuite_runs_generated_cases() {
  local d suite out err
  d="$(case_dir generated-suite)"
  suite="$d/suite"
  out="$d/out"
  err="$d/err"

  cat >"$suite" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -eq 0 ]]; then
  printf '#!testsuite\n'
  printf 'alpha "two words"\n'
  printf 'tabbed\tthree words\tfour\n'
  exit 88
fi

case "$1" in
  alpha)
    [[ "$2" == "two words" ]]
    printf '# alpha generated case\n'
    ;;
  tabbed)
    [[ "$2" == "three words" ]]
    [[ "$3" == "four" ]]
    printf '# tab generated case\n'
    ;;
  *)
    printf 'unexpected generated args: %s\n' "$*" >&2
    exit 9
    ;;
esac
SCRIPT
  make_executable "$suite"

  run_ko "$out" "$err" "$suite"
  assert_eq "0" "$RUN_STATUS" "generated suite should pass" || return
  assert_file_empty "$err" || return
  assert_contains "$out" "[T 1/1] $suite" || return
  assert_contains "$out" "[S 1/2] $suite::alpha" || return
  assert_contains "$out" "-- alpha generated case" || return
  assert_contains "$out" "::tabbed" || return
  assert_contains "$out" "-- tab generated case" || return
}

test_testsuite_description_lines_are_ignored() {
  local d suite out err
  d="$(case_dir generated-suite-comments)"
  suite="$d/suite"
  out="$d/out"
  err="$d/err"

  cat >"$suite" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -eq 0 ]]; then
  printf '#!testsuite\n'
  printf '# group heading\n'
  printf 'alpha\n'
  exit 88
fi

case "$1" in
  alpha)
    printf '# alpha generated case\n'
    ;;
  *)
    printf 'unexpected generated args: %s\n' "$*" >&2
    exit 9
    ;;
esac
SCRIPT
  make_executable "$suite"

  run_ko "$out" "$err" "$suite"
  assert_eq "0" "$RUN_STATUS" "description lines in suite output should be ignored" || return
  assert_file_empty "$err" || return
  assert_contains "$out" "[S 1/1] $suite::alpha" || return
  assert_not_contains "$out" "[S 2/2]" || return
}

if [[ ! -x "$KO_UNDER_TEST" ]]; then
  printf 'ko under test is not executable: %s\n' "$KO_UNDER_TEST" >&2
  exit 2
fi

run_case "usage without arguments" test_usage_without_args
run_case "executable test success and description" test_executable_success_and_description
run_case "non-executable .sh runs via bash" test_non_executable_sh_runs_with_bash
run_case "non-executable non-.sh is rejected" test_rejects_non_executable_non_sh
run_case "stderr marks test failure" test_stderr_marks_failure
run_case "nonzero failure reports and continues" test_nonzero_failure_continues
run_case "directory expansion is non-recursive" test_directory_expansion_is_non_recursive
run_case "-d keeps stdout/stderr/status artifacts" test_keep_tmp_writes_artifacts
run_case "-v passes through stdout" test_verbose_passes_through_stdout
run_case "testsuite generated cases support shell and tab parsing" test_testsuite_runs_generated_cases

run_case "testsuite description lines are ignored" test_testsuite_description_lines_are_ignored

printf '\nsummary: %d passed, %d failed, %d xfailed, %d xpassed\n' \
  "$PASS_COUNT" "$FAIL_COUNT" "$XFAIL_COUNT" "$XPASS_COUNT"

if [[ "$FAIL_COUNT" -ne 0 || "$XPASS_COUNT" -ne 0 ]]; then
  exit 1
fi
