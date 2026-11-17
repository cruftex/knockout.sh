#!/usr/bin/env bash
# knockout.sh self-test suite. t_unit_* source the knockout.sh under test and
# call its functions; t_int_* run the complete script. Runs via knockout.sh, a
# second time independently via test/knockout-test.sh, or one case:
#   test/knockout.turbo.suite.sh <name>
# Tests another implementation with the normal knockout.sh as harness:
#   KO_UNDER_TEST=/path/to/other/knockout.sh knockout.sh -d test
set -euo pipefail
source <(knockout.sh fn-suite)

# Implementation under test: the knockout running this suite (first on PATH;
# knockout puts itself there), or another one via KO_UNDER_TEST. Resolved to an
# absolute path because tests cd and run with a reduced PATH.
ko_wanted="${KO_UNDER_TEST:-knockout.sh}"
if ! KO_UNDER_TEST="$(type -P "$ko_wanted")"; then
  printf 'knockout under test not found: %s\n' "$ko_wanted" >&2
  exit 2
fi
KO_UNDER_TEST="$(readlink -f "$KO_UNDER_TEST")"

# Unit tests call knockout's functions directly.
# shellcheck source=../bin/knockout.sh
source "$KO_UNDER_TEST"

KO_RC=0

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
  KO_RC=$?
  set -e
}

# Like run_ko, but in-process: init_run + run_paths of the sourced knockout in a
# subshell (state isolation; die exits only the subshell). Mirrors main: strict
# mode, own dir first on PATH, exit 1 on test errors.
run_unit() {
  local out_file="$1"
  local err_file="$2"
  shift 2
  local kt
  kt="$(mktemp -d "$CASE_ROOT/run.XXXXXX")"

  set +e
  (
    set -euo pipefail
    PATH="$(dirname "$KO_UNDER_TEST"):$PATH"
    init_run "$kt"
    run_paths "$@"
    [[ "$had_test_error" -eq 0 ]]
  ) >"$out_file" 2>"$err_file" </dev/null
  KO_RC=$?
  set -e
}

make_executable() {
  chmod +x "$1"
}

# Per-case temp root, removed when the case ends (every case runs in its own
# subshell or process). Call as: case_dir NAME; d="$CASE_DIR"
CASE_ROOT=""
CASE_DIR=""
case_dir() {
  if [[ -z "$CASE_ROOT" ]]; then
    CASE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/ko-test.XXXXXXXXXX")"
    trap 'rm -rf "$CASE_ROOT"' EXIT
  fi
  CASE_DIR="$CASE_ROOT/$1"
  mkdir -p "$CASE_DIR"
}

t_int_usage_without_args() {
  echo "# usage without arguments"
  local d out err
  case_dir usage; d="$CASE_DIR"
  out="$d/out"
  err="$d/err"

  # Empty cwd: project mode must find nothing (and never this repo's tests).
  local here="$PWD"
  cd "$d"
  run_ko "$out" "$err"
  cd "$here"
  assert_eq "1" "$KO_RC" "usage should exit 1" || return
  assert_file_empty "$out" || return
  assert_contains "$err" "no test dirs found" || return
  assert_contains "$err" "usage: ${KO_UNDER_TEST##*/} [run] [-v] [-k] [-t <tap>] [-j <junit.xml>] [-d <dir>]..." || return
}

t_unit_executable_success_and_description() {
  echo "# executable test success and description"
  local d t out err
  case_dir executable-success; d="$CASE_DIR"
  t="$d/pass"
  out="$d/out"
  err="$d/err"

  cat >"$t" <<'SCRIPT'
#!/usr/bin/env bash
printf '# executable test passed\n'
SCRIPT
  make_executable "$t"

  run_unit "$out" "$err" "$t"
  assert_eq "0" "$KO_RC" "successful executable should exit 0" || return
  assert_file_empty "$err" || return
  assert_contains "$out" "[T 1/1] $t" || return
  assert_contains "$out" "-- executable test passed" || return
}

t_unit_non_executable_sh_runs_with_bash() {
  echo "# non-executable .sh runs via bash"
  local d t out err
  case_dir sh-fallback; d="$CASE_DIR"
  t="$d/pass.sh"
  out="$d/out"
  err="$d/err"

  cat >"$t" <<'SCRIPT'
[[ "abc" == a* ]]
printf '# bash fallback worked\n'
SCRIPT

  run_unit "$out" "$err" "$t"
  assert_eq "0" "$KO_RC" "non-executable .sh should run with bash" || return
  assert_file_empty "$err" || return
  assert_contains "$out" "-- bash fallback worked" || return
}

t_unit_rejects_non_executable_non_sh() {
  echo "# non-executable non-.sh is rejected"
  local d t out err
  case_dir rejects-non-runnable; d="$CASE_DIR"
  t="$d/not-runnable.txt"
  out="$d/out"
  err="$d/err"

  printf 'echo no\n' >"$t"

  run_unit "$out" "$err" "$t"
  assert_eq "1" "$KO_RC" "non-runnable file should exit 1" || return
  assert_file_empty "$out" || return
  assert_contains "$err" "ERROR" || return
  assert_contains "$err" "die: file not executable and not .sh: $t" || return
}

t_unit_stderr_marks_failure() {
  echo "# stderr marks test failure"
  local d t out err
  case_dir stderr-failure; d="$CASE_DIR"
  t="$d/stderr-pass"
  out="$d/out"
  err="$d/err"

  cat >"$t" <<'SCRIPT'
#!/usr/bin/env bash
printf 'stdout body\n'
printf 'stderr body\n' >&2
SCRIPT
  make_executable "$t"

  run_unit "$out" "$err" "$t"
  assert_eq "1" "$KO_RC" "stderr output should fail the run" || return
  assert_contains "$err" "ERROR" || return
  assert_contains "$err" "status: 0" || return
  assert_contains "$err" "stdout body" || return
  assert_contains "$err" "stderr body" || return
}

t_unit_nonzero_failure_continues() {
  echo "# nonzero failure reports and continues"
  local d fail pass out err
  case_dir failure-continues; d="$CASE_DIR"
  fail="$d/01_fail"
  pass="$d/02_pass"
  out="$CASE_ROOT/failure-continues.out"
  err="$CASE_ROOT/failure-continues.err"

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

  run_unit "$out" "$err" "$d"
  assert_eq "1" "$KO_RC" "suite with failing test should exit 1" || return
  assert_contains "$out" "$fail" || return
  assert_contains "$out" "$pass" || return
  assert_line_count_regex "$out" '^\[T [0-9]+/2\]' "2" || return
  assert_contains "$err" "status: 7" || return
  assert_contains "$err" "bad stdout" || return
}

t_unit_directory_expansion_is_non_recursive() {
  echo "# directory expansion is non-recursive"
  local d top nested out err
  case_dir directory-nonrecursive; d="$CASE_DIR"
  mkdir -p "$d/nested"
  top="$d/top"
  nested="$d/nested/should-not-run"
  out="$CASE_ROOT/directory-nonrecursive.out"
  err="$CASE_ROOT/directory-nonrecursive.err"

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

  run_unit "$out" "$err" "$d"
  assert_eq "0" "$KO_RC" "nested files should not be expanded" || return
  assert_file_empty "$err" || return
  assert_contains "$out" "$top" || return
  assert_not_contains "$out" "$nested" || return
}

t_int_options_v_k_d() {
  echo "# -d selects a test dir, -v passes stdout through, -k keeps artifacts, -t/-j write reports"
  local d t out err kept
  case_dir options; d="$CASE_DIR"
  mkdir -p "$d/tests"
  t="$d/tests/pass"
  out="$d/out"
  err="$d/err"

  cat >"$t" <<'SCRIPT'
#!/usr/bin/env bash
printf '# kept artifacts\n'
printf 'visible stdout\n'
SCRIPT
  make_executable "$t"

  run_ko "$out" "$err" -v -k -t "$d/r.tap" -j "$d/r.xml" -d "$d/tests"
  assert_eq "0" "$KO_RC" "-v -k -t -j -d run should pass" || return
  assert_contains "$out" "[T 1/1] $t" || return
  assert_contains "$out" "1 tests: 1 passed, 0 failed, 0 skipped, 0 not run, 0 suite errors  " || return
  assert_contains "$d/r.tap" "ok 1 - $t" || return
  assert_contains "$d/r.xml" "<testcase classname=\"$t\"" || return
  assert_contains "$out" "visible stdout" || return
  assert_contains "$out" "-- kept artifacts" || return
  kept="$(sed -n 's/^keeping tmpdir: //p' "$err" | tail -n 1)"
  [[ -n "$kept" ]] || { fail_msg "missing kept tmpdir line"; return 1; }
  [[ -d "$kept" ]] || { fail_msg "kept tmpdir does not exist: $kept"; return 1; }
  find "$kept" -name '*.out' -print -quit | grep -q . || { fail_msg "missing .out artifact"; return 1; }
  find "$kept" -name '*.err' -print -quit | grep -q . || { fail_msg "missing .err artifact"; return 1; }
  find "$kept" -name '*.status' -print -quit | grep -q . || { fail_msg "missing .status artifact"; return 1; }
  rm -rf "$kept"
}

t_unit_testsuite_runs_generated_cases() {
  echo "# extensionless .suite generates cases with shell and tab parsing"
  local d suite out err
  case_dir generated-suite; d="$CASE_DIR"
  suite="$d/x.suite"
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

  run_unit "$out" "$err" "$suite"
  assert_eq "0" "$KO_RC" "generated suite should pass" || return
  assert_file_empty "$err" || return
  assert_contains "$out" "[L 1/1] $suite" || return
  assert_contains "$out" "[S 1/2] $suite::alpha" || return
  assert_contains "$out" "-- alpha generated case" || return
  assert_contains "$out" "::tabbed" || return
  assert_contains "$out" "-- tab generated case" || return
}

t_unit_testsuite_description_lines_are_ignored() {
  echo "# testsuite description lines are ignored"
  local d suite out err
  case_dir generated-suite-comments; d="$CASE_DIR"
  suite="$d/x.suite"
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

  run_unit "$out" "$err" "$suite"
  assert_eq "0" "$KO_RC" "description lines in suite output should be ignored" || return
  assert_file_empty "$err" || return
  assert_contains "$out" "[S 1/1] $suite::alpha" || return
  assert_not_contains "$out" "[S 2/2]" || return
}

t_int_fn_suite_prints_handler() {
  echo "# fn-suite prints a sourceable handler"
  local dir out err
  case_dir fn-suite-print; dir="$CASE_DIR"
  out="$dir/out"
  err="$dir/err"

  run_ko "$out" "$err" fn-suite
  assert_eq "0" "$KO_RC" "fn-suite should exit 0" || return
  assert_file_empty "$err" || return
  bash -n "$out" || { fail_msg "fn-suite output is not valid bash"; return 1; }
  # shellcheck disable=SC1090
  (source "$out" && declare -F testsuite_main >/dev/null) \
    || { fail_msg "fn-suite output does not define testsuite_main"; return 1; }
}

t_int_fn_suite_sourced_by_suite_without_install() {
  echo "# suite sources fn-suite from the running knockout"
  local dir out err suite
  case_dir fn-suite-source; dir="$CASE_DIR"
  out="$dir/out"
  err="$dir/err"
  mkdir -p "$dir/tests"
  suite="$dir/tests/x.suite.sh"

  cat >"$suite" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
source <(knockout.sh fn-suite)
t_one() { echo "# first"; }
t_two() { echo "# second"; }
t_three() { echo "# third"; }
testsuite_main "$@"
SCRIPT
  make_executable "$suite"

  # Minimal PATH without any installed knockout: runner must provide itself.
  PATH="/usr/bin:/bin" run_ko "$out" "$err" -d "$dir/tests"
  assert_eq "0" "$KO_RC" "suite sourcing fn-suite should pass" || return
  assert_file_empty "$err" || return
  assert_contains "$out" "[S 3/3]" || return
  assert_contains "$out" "-- third" || return
}

t_unit_mixed_run_has_exact_shared_total() {
  echo "# mixed run has exact shared total"
  local dir out err
  case_dir mixed-total; dir="$CASE_DIR"
  out="$dir/out"
  err="$dir/err"

  printf '#!/usr/bin/env bash\necho ok\n' >"$dir/a.sh"
  cat >"$dir/b.suite.sh" <<'SCRIPT'
if [[ "$#" -eq 0 ]]; then printf '#!testsuite\none\ntwo\n'; exit 88; fi
echo "case $1"
SCRIPT
  printf '#!/usr/bin/env bash\necho ok\n' >"$dir/c.sh"

  run_unit "$out" "$err" "$dir/a.sh" "$dir/b.suite.sh" "$dir/c.sh"
  assert_eq "0" "$KO_RC" "mixed run should pass" || return
  assert_file_empty "$err" || return
  assert_contains "$out" "[L 1/1] $dir/b.suite.sh" || return
  assert_contains "$out" "[T 1/4] $dir/a.sh" || return
  assert_contains "$out" "[S 2/4] $dir/b.suite.sh::one" || return
  assert_contains "$out" "[S 3/4] $dir/b.suite.sh::two" || return
  assert_contains "$out" "[T 4/4] $dir/c.sh" || return
}

t_unit_unnamed_suite_output_fails_with_hint() {
  echo "# testsuite output from non-suite name fails with hint"
  local dir out err t
  case_dir unnamed-suite; dir="$CASE_DIR"
  out="$dir/out"
  err="$dir/err"
  t="$dir/sneaky.sh"
  printf '#!/usr/bin/env bash\nprintf "#!testsuite\\none\\n"\nexit 88\n' >"$t"

  run_unit "$out" "$err" "$t"
  assert_eq "1" "$KO_RC" "testsuite output from non-suite name should fail" || return
  assert_contains "$err" "hint: testsuite output from a file not named as testsuite" || return
  assert_not_contains "$out" "[S " || return
}

t_unit_broken_listing_fails_and_continues() {
  echo "# broken suite listings fail and the run continues"
  local dir out err
  case_dir broken-listing; dir="$CASE_DIR"
  out="$dir/out"
  err="$dir/err"

  printf 'echo "no marker"\nexit 0\n' >"$dir/nomarker.suite.sh"
  printf 'printf "#!testsuite\\none\\n"; echo oops >&2; exit 88\n' >"$dir/noisy.suite.sh"
  printf 'echo ok\n' >"$dir/plain.sh"

  run_unit "$out" "$err" "$dir/nomarker.suite.sh" "$dir/noisy.suite.sh" "$dir/plain.sh"
  assert_eq "1" "$KO_RC" "broken listings should fail the run" || return
  assert_contains "$err" "test: $dir/nomarker.suite.sh" || return
  assert_contains "$err" "test: $dir/noisy.suite.sh" || return
  assert_contains "$err" "hint: testsuite listing must exit 88" || return
  assert_contains "$out" "[T 1/1] $dir/plain.sh" || return
  assert_not_contains "$out" "[S " || return
}

t_int_project_mode_discovers_test_dirs() {
  echo "# no arguments runs test dirs below cwd"
  local d out err here
  case_dir project-mode; d="$CASE_DIR"
  out="$d/out"
  err="$d/err"
  mkdir -p "$d/proj/knockout-tests" "$d/proj/sub" "$d/proj/.hidden/knockout-tests" "$d/proj/plain"
  printf 'echo a\n' >"$d/proj/knockout-tests/a.sh"
  : >"$d/proj/sub/.knockout-tests"
  printf 'echo b\n' >"$d/proj/sub/b.sh"
  printf 'echo c >&2; exit 1\n' >"$d/proj/.hidden/knockout-tests/c.sh"
  printf 'echo p >&2; exit 1\n' >"$d/proj/plain/p.sh"

  here="$PWD"
  cd "$d/proj"
  run_ko "$out" "$err"
  cd "$here"
  assert_eq "0" "$KO_RC" "project mode should pass" || return
  assert_file_empty "$err" || return
  assert_contains "$out" "[T 1/2] knockout-tests/a.sh" || return
  assert_contains "$out" "[T 2/2] sub/b.sh" || return
  assert_not_contains "$out" ".knockout-tests" || return
}

t_unit_marker_file_is_not_a_test() {
  echo "# marker file in a test dir is not a test"
  local d out err
  case_dir marker-ignored; d="$CASE_DIR"
  out="$d/out"
  err="$d/err"
  mkdir -p "$d/t"
  : >"$d/t/.knockout-tests"
  printf 'echo ok\n' >"$d/t/ok.sh"

  run_unit "$out" "$err" "$d/t"
  assert_eq "0" "$KO_RC" "explicit dir with marker should pass" || return
  assert_file_empty "$err" || return
  assert_contains "$out" "[T 1/1] $d/t/ok.sh" || return
}

write_fn_suite() {
  # $1 path; stdin: body (t_* functions and top-level code). The handler is
  # embedded from the sourced knockout (no knockout process per fixture run);
  # t_int_fn_suite_sourced_by_suite_without_install covers `knockout.sh fn-suite`.
  {
    printf '#!/usr/bin/env bash\nset -euo pipefail\n'
    print_fn_suite
    cat
    printf 'testsuite_main "$@"\n'
  } >"$1"
}

normalize_run() {
  # Strip timings and the suite file name so forked, turbo and worker runs compare equal.
  sed -E 's/  [0-9]+\.[0-9]+s/  Ns/; s#[^ ]*/s\.(turbo\.|worker\.)?suite\.sh#SUITE#g' "$1"
}

t_unit_turbo_matches_forked() {
  echo "# turbo suite reports exactly like a forked suite"
  local d body
  case_dir turbo-golden; d="$CASE_DIR"
  read -r -d '' body <<'BODY' || true
t_pass() { echo "# passes"; echo "args: $*"; }
t_fail() { echo "# fails"; echo "boom" >&2; }
t_spaces() { echo "# spaces"; [[ "$1" == "a b" && "$2" == "c" ]]; }
t_status() { echo "# status"; return 3; }
BODY
  write_fn_suite "$d/s.suite.sh" <<<"$body"
  write_fn_suite "$d/s.turbo.suite.sh" <<<"$body"
  # Listing with a spaced argument for t_spaces: override the generated listing.
  local f
  for f in "$d/s.suite.sh" "$d/s.turbo.suite.sh"; do
    sed -i 's/^testsuite_main "\$@"$/if (( $# == 0 )) \&\& [[ "${BASH_SOURCE[0]}" == "$0" ]]; then printf "#!testsuite\\npass x\\nfail\\nspaces \\"a b\\" c\\nstatus\\n"; exit 88; fi\ntestsuite_main "$@"/' "$f"
  done

  run_unit "$d/f.out" "$d/f.err" "$d/s.suite.sh"
  local forked_status="$KO_RC"
  run_unit "$d/t.out" "$d/t.err" "$d/s.turbo.suite.sh"
  assert_eq "$forked_status" "$KO_RC" "turbo exit status should match forked" || return
  assert_eq "1" "$KO_RC" "suite with failures should fail" || return
  assert_eq "$(normalize_run "$d/f.out")" "$(normalize_run "$d/t.out")" "turbo stdout should match forked" || return
  assert_eq "$(normalize_run "$d/f.err")" "$(normalize_run "$d/t.err")" "turbo error report should match forked" || return
  assert_contains "$d/t.out" "[S 3/4] $d/s.turbo.suite.sh::spaces (a\\ b c)" || return
}

t_unit_turbo_isolates_cases() {
  echo "# turbo suite isolates cases in subshells"
  local d
  case_dir turbo-isolation; d="$CASE_DIR"
  write_fn_suite "$d/i.turbo.suite.sh" <<'BODY'
echo sourced >>"$(dirname "${BASH_SOURCE[0]}")/count"
t_a_set() { SHARED=changed; cd /; echo "# a"; }
t_b_check() { echo "# b"; [[ "${SHARED:-unset}" == unset && "$PWD" != / ]]; }
t_c_exit() { echo "# c"; exit 3; }
t_d_after() { echo "# d"; }
BODY

  run_unit "$d/out" "$d/err" "$d/i.turbo.suite.sh"
  assert_eq "1" "$KO_RC" "exit 3 in one case should fail the run" || return
  assert_contains "$d/out" "[S 4/4] $d/i.turbo.suite.sh::d_after" || return
  assert_contains "$d/err" "test: $d/i.turbo.suite.sh::c_exit" || return
  assert_not_contains "$d/err" "b_check" || return
  # Sourced once for the listing (phase L) and once by the turbo worker.
  assert_eq "2" "$(wc -l <"$d/count")" "top-level code should run once per worker, not per case" || return
}

t_unit_turbo_source_failure() {
  echo "# turbo suite source failure skips its tests"
  local d
  case_dir turbo-source-fail; d="$CASE_DIR"
  write_fn_suite "$d/bad.turbo.suite.sh" <<'BODY'
t_one() { echo "# one"; }
t_two() { echo "# two"; }
[[ "$#" -eq 0 && "${BASH_SOURCE[0]}" == "$0" ]] || { echo "setup broke" >&2; false; }
BODY
  printf 'echo ok\n' >"$d/after.sh"

  run_unit "$d/out" "$d/err" "$d/bad.turbo.suite.sh" "$d/after.sh"
  assert_eq "1" "$KO_RC" "source failure should fail the run" || return
  assert_contains "$d/err" "hint: turbo suite failed while being sourced; its 2 tests were not run" || return
  assert_contains "$d/err" "setup broke" || return
  assert_not_contains "$d/out" "::one" || return
  assert_contains "$d/out" "[T 3/3] $d/after.sh" || return
}

# Prints a bash worker loop for fixture suites: with KNOCKOUT_WORKER=1 it runs
# each case line in a subshell, writes PREFIX.out/.err/.status, reports "IDX 0.001".
worker_loop() {
  cat <<'LOOP'
if [[ "${KNOCKOUT_WORKER:-}" == 1 ]]; then
  echo "#!worker"
  while IFS=$'\t' read -r idx prefix line; do
    eval "args=($line)"
    st=0
    ( "t_${args[0]}" "${args[@]:1}" ) </dev/null >"$prefix.out" 2>"$prefix.err" || st=$?
    echo "$st" >"$prefix.status"
    echo "$idx 0.001"
  done
  exit 0
fi
LOOP
}

t_unit_worker_matches_forked() {
  echo "# worker suite reports exactly like a forked suite"
  local d body
  case_dir worker-golden; d="$CASE_DIR"
  read -r -d '' body <<'BODY' || true
t_pass() { echo "# passes"; echo "args: $*"; }
t_fail() { echo "# fails"; echo "boom" >&2; }
t_spaces() { echo "# spaces"; [[ "$1" == "a b" && "$2" == "c" ]]; }
t_status() { echo "# status"; return 3; }
if (( $# == 0 )) && [[ -z "${KNOCKOUT_WORKER:-}" ]]; then
  printf '#!testsuite\npass x\nfail\nspaces "a b" c\nstatus\n'; exit 88
fi
BODY
  body+=$'\n'"$(worker_loop)"
  write_fn_suite "$d/s.suite.sh" <<<"$body"
  write_fn_suite "$d/s.worker.suite.sh" <<<"$body"

  run_unit "$d/f.out" "$d/f.err" "$d/s.suite.sh"
  local forked_status="$KO_RC"
  run_unit "$d/w.out" "$d/w.err" "$d/s.worker.suite.sh"
  assert_eq "1" "$forked_status" "suite with failures should fail" || return
  assert_eq "$forked_status" "$KO_RC" "worker exit status should match forked" || return
  assert_eq "$(normalize_run "$d/f.out")" "$(normalize_run "$d/w.out")" "worker stdout should match forked" || return
  assert_eq "$(normalize_run "$d/f.err")" "$(normalize_run "$d/w.err")" "worker error report should match forked" || return
  assert_contains "$d/w.out" "[S 3/4] $d/s.worker.suite.sh::spaces (a\\ b c)  0.001s  -- spaces" || return
}

t_unit_worker_gets_cases_on_stdin() {
  echo "# worker suite gets KNOCKOUT_WORKER=1 and INDEX<TAB>PREFIX<TAB>LINE on stdin"
  local d
  case_dir worker-stdin; d="$CASE_DIR"
  printf 'echo ok\n' >"$d/a.sh"
  write_fn_suite "$d/w.worker.suite.sh" <<'BODY'
t_one() { echo "# one"; }
t_two() { echo "# two"; }
if [[ "${KNOCKOUT_WORKER:-}" == 1 ]]; then
  echo "#!worker"
  while IFS= read -r line; do
    printf '%s\n' "$line" >>"$(dirname "$0")/seen"
    idx="${line%%$'\t'*}" rest="${line#*$'\t'}"
    prefix="${rest%%$'\t'*}"
    : >"$prefix.out"; : >"$prefix.err"; echo 0 >"$prefix.status"
    echo "$idx 0.001"
  done
  exit 0
fi
if (( $# == 0 )); then printf '#!testsuite\none\ntwo\tx y\n'; exit 88; fi
BODY

  run_unit "$d/out" "$d/err" "$d/a.sh" "$d/w.worker.suite.sh"
  assert_eq "0" "$KO_RC" "worker run should pass" || return
  assert_file_empty "$d/err" || return
  assert_eq "2" "$(wc -l <"$d/seen")" "one stdin line per case" || return
  assert_eq "2" "$(cut -f1 "$d/seen" | head -1)" "index continues the shared counter" || return
  assert_eq "/" "$(cut -f2 "$d/seen" | head -1 | cut -c1)" "prefix should be absolute" || return
  assert_eq "one" "$(cut -f3- "$d/seen" | head -1)" "line should be passed verbatim" || return
  assert_eq $'two\tx y' "$(cut -f3- "$d/seen" | tail -1)" "TABs in the line should be kept" || return
  assert_contains "$d/out" "[S 3/3] $d/w.worker.suite.sh::two (x\\ y)  0.001s" || return
}

t_unit_worker_setup_failure() {
  echo "# worker suite without #!worker line skips its tests"
  local d
  case_dir worker-setup-fail; d="$CASE_DIR"
  write_fn_suite "$d/bad.worker.suite.sh" <<'BODY'
t_one() { echo "# one"; }
t_two() { echo "# two"; }
[[ -z "${KNOCKOUT_WORKER:-}" ]] || { echo "setup broke" >&2; exit 4; }
BODY
  printf 'echo ok\n' >"$d/after.sh"

  run_unit "$d/out" "$d/err" "$d/bad.worker.suite.sh" "$d/after.sh"
  assert_eq "1" "$KO_RC" "setup failure should fail the run" || return
  assert_contains "$d/err" 'hint: worker suite printed no "#!worker" line; its 2 tests were not run' || return
  assert_contains "$d/err" "status: 4" || return
  assert_contains "$d/err" "setup broke" || return
  assert_not_contains "$d/out" "::one" || return
  assert_contains "$d/out" "[T 3/3] $d/after.sh" || return
}

t_unit_worker_aborts_early() {
  echo "# worker suite that stops early reports the rest as not run"
  local d
  case_dir worker-abort; d="$CASE_DIR"
  write_fn_suite "$d/w.worker.suite.sh" <<BODY
t_one() { echo "# one"; }
t_two() { echo "# two"; }
t_three() { echo "# three"; exit 1; }
t_after() { echo "# after"; }
$(worker_loop | sed 's/^    echo "\$idx 0.001"$/&; [[ "\$st" -eq 0 ]] || exit 1/')
BODY

  run_unit "$d/out" "$d/err" "$d/w.worker.suite.sh"
  assert_eq "1" "$KO_RC" "aborted worker should fail the run" || return
  assert_contains "$d/out" "[S 1/4] $d/w.worker.suite.sh::after" || return
  assert_contains "$d/out" "[S 3/4] $d/w.worker.suite.sh::three" || return
  assert_contains "$d/err" "hint: worker suite must report every test, write no stderr and exit 0" || return
  assert_contains "$d/err" "test: $d/w.worker.suite.sh::two" || return
  assert_contains "$d/err" "hint: worker aborted before this test ran" || return
}

t_unit_worker_stderr_fails_suite() {
  echo "# worker suite stderr fails the suite file"
  local d
  case_dir worker-stderr; d="$CASE_DIR"
  write_fn_suite "$d/w.worker.suite.sh" <<BODY
t_one() { echo "# one"; }
[[ -z "\${KNOCKOUT_WORKER:-}" ]] || echo "worker noise" >&2
$(worker_loop)
BODY

  run_unit "$d/out" "$d/err" "$d/w.worker.suite.sh"
  assert_eq "1" "$KO_RC" "worker stderr should fail the run" || return
  assert_contains "$d/out" "[S 1/1] $d/w.worker.suite.sh::one" || return
  assert_contains "$d/err" "test: $d/w.worker.suite.sh" || return
  assert_contains "$d/err" "worker noise" || return
}

t_unit_worker_unexpected_report() {
  echo "# worker suite with an unexpected report line fails"
  local d
  case_dir worker-bad-report; d="$CASE_DIR"
  write_fn_suite "$d/w.worker.suite.sh" <<BODY
t_one() { echo "# one"; }
t_two() { echo "# two"; }
$(worker_loop | sed 's/^  echo "#!worker"$/&; echo "stray output"/')
BODY

  run_unit "$d/out" "$d/err" "$d/w.worker.suite.sh"
  assert_eq "1" "$KO_RC" "unexpected report should fail the run" || return
  assert_contains "$d/err" "hint: unexpected worker report: stray output" || return
  assert_contains "$d/err" "test: $d/w.worker.suite.sh::one" || return
  assert_not_contains "$d/out" "::one" || return
}

t_unit_python3_unittest_worker() {
  echo "# knockout.sh python3-unittest runs unittest tests as a worker suite"
  local d s
  case_dir py-unittest; d="$CASE_DIR"
  mkdir -p "$d/proj/tests" "$d/proj/knockout-tests"
  printf 'def twice(x):\n    return 2 * x\n' >"$d/proj/mod.py"
  : >"$d/proj/tests/__init__.py"
  cat >"$d/proj/tests/test_mod.py" <<'PYTEST'
import logging
import sys
import unittest

import mod


def setUpModule():
    global MODULE_READY
    MODULE_READY = True


class ModTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.class_ready = True

    def test_a_pass(self):
        """twice doubles"""
        self.assertEqual(mod.twice(2), 4)

    def test_b_fail(self):
        self.assertEqual(mod.twice(2), 5)

    @unittest.skip("not now")
    def test_c_skip(self):
        pass

    def test_d_fixtures(self):
        self.assertTrue(self.class_ready and MODULE_READY)

    def test_e_stderr(self):
        logging.warning("a logged warning")
        print("plain stderr", file=sys.stderr)

    def test_f_subtest(self):
        for i in range(3):
            with self.subTest(i=i):
                self.assertNotEqual(i, 1)

    @unittest.expectedFailure
    def test_g_xfail(self):
        self.fail()
PYTEST
  printf '%s\n' 'cd "$(dirname "$0")/.." && exec knockout.sh python3-unittest discover -s tests -t . "$@"' \
    >"$d/proj/knockout-tests/u.worker.suite.sh"

  run_unit "$d/out" "$d/err" "$d/proj/knockout-tests"
  s="$d/proj/knockout-tests/u.worker.suite.sh::tests.test_mod.ModTest"
  assert_eq "1" "$KO_RC" "failing unittest should fail the run" || return
  assert_contains "$d/out" "[S 1/7] ${s}.test_a_pass" || return
  assert_contains "$d/out" "-- twice doubles" || return
  assert_contains "$d/out" "[S 3/7] ${s}.test_c_skip  " || return
  assert_line_count_regex "$d/out" '::tests\.test_mod\.ModTest\.test_c_skip  [0-9.]+s  SKIP$' 1 || return
  assert_contains "$d/err" "test: ${s}.test_b_fail" || return
  assert_contains "$d/err" "AssertionError: 4 != 5" || return
  assert_contains "$d/err" "FAIL: test_f_subtest (tests.test_mod.ModTest.test_f_subtest) (i=1)" || return
  # Exactly the two real failures: fixtures ran, stderr output and xfail don't fail.
  assert_line_count_regex "$d/err" '^test: ' 2 || return
  assert_eq "" "$(find "$d/proj" -name __pycache__)" "no bytecode should be written" || return
}

t_unit_skip_exit_77() {
  echo "# exit 77 without stderr is SKIP (plain, suite, turbo); with stderr it fails"
  local d f
  case_dir skip77; d="$CASE_DIR"
  printf 'echo "# plain skip"; exit 77\n' >"$d/a.sh"
  for f in "$d/s.suite.sh" "$d/s.turbo.suite.sh"; do
    write_fn_suite "$f" <<'BODY'
t_skipped() { echo "# case skip"; exit 77; }
t_ok() { echo "# ok"; }
BODY
  done

  run_unit "$d/out" "$d/err" "$d/a.sh" "$d/s.suite.sh" "$d/s.turbo.suite.sh"
  assert_eq "0" "$KO_RC" "skipped tests should not fail the run" || return
  assert_file_empty "$d/err" || return
  assert_contains "$d/out" "$d/a.sh  " || return
  assert_line_count_regex "$d/out" '  [0-9.]+s  SKIP  -- (plain|case) skip$' 3 || return
  assert_line_count_regex "$d/out" 'SKIP' 3 || return

  printf 'echo "# noisy"; echo oops >&2; exit 77\n' >"$d/b.sh"
  run_unit "$d/out2" "$d/err2" "$d/b.sh"
  assert_eq "1" "$KO_RC" "exit 77 with stderr should fail" || return
  assert_not_contains "$d/out2" "SKIP" || return
  assert_contains "$d/err2" "status: 77" || return
}

# Like run_unit, plus finish_run (summary line) and TAP/JUnit reports
# written to $CASE_DIR/r.tap and $CASE_DIR/r.xml.
run_unit_reports() {
  local out_file="$1"
  local err_file="$2"
  shift 2
  local kt
  kt="$(mktemp -d "$CASE_ROOT/run.XXXXXX")"

  set +e
  (
    set -euo pipefail
    PATH="$(dirname "$KO_UNDER_TEST"):$PATH"
    TAP_FILE="$CASE_DIR/r.tap"
    JUNIT_FILE="$CASE_DIR/r.xml"
    init_run "$kt"
    run_paths "$@"
    finish_run
    [[ "$had_test_error" -eq 0 ]]
  ) >"$out_file" 2>"$err_file" </dev/null
  KO_RC=$?
  set -e
}

# Mixed fixture in dir $1 (created): pass, fail (with XML special chars), skip, a "#" in a
# name, and a worker suite whose setup fails (suite error, 2 tests not run).
write_mixed_results() {
  mkdir -p "$1"
  printf 'echo "# passes"\n' >"$1/a-pass.sh"
  printf '%s\n' 'echo "out <&\"> x"; echo "err <&\"> y" >&2; exit 3' >"$1/b-fail.sh"
  printf 'echo "# skips"; exit 77\n' >"$1/c-skip.sh"
  printf 'exit 0\n' >"$1/d-hash#name.sh"
  write_fn_suite "$1/e.worker.suite.sh" <<'BODY'
t_one() { :; }
t_two() { :; }
[[ -z "${KNOCKOUT_WORKER:-}" ]] || exit 4
BODY
}

t_unit_summary_line() {
  echo "# summary line counts passed, failed, skipped, not run and suite errors"
  local d
  case_dir summary; d="$CASE_DIR"
  write_mixed_results "$d/t"

  run_unit_reports "$d/out" "$d/err" "$d/t"
  assert_eq "1" "$KO_RC" "mixed results should fail the run" || return
  assert_line_count_regex "$d/out" \
    '^6 tests: 2 passed, 1 failed, 1 skipped, 2 not run, 1 suite errors  [0-9]+\.[0-9]{3}s$' 1 || return
  assert_eq "6 tests:" "$(tail -n 1 "$d/out" | cut -d' ' -f1-2)" "summary should be the last stdout line" || return
}

t_unit_tap_report() {
  echo "# -t writes a TAP report"
  local d
  case_dir tap; d="$CASE_DIR"
  write_mixed_results "$d/t"

  run_unit_reports "$d/out" "$d/err" "$d/t"
  assert_eq "TAP version 13" "$(head -n 1 "$d/r.tap")" "TAP header" || return
  assert_eq "1..7" "$(tail -n 1 "$d/r.tap")" "TAP plan line at the end" || return
  # Files of a dir run in directory order: match entries, not their numbers.
  assert_line_count_regex "$d/r.tap" "^ok [0-9] - $d/t/a-pass\\.sh\$" 1 || return
  assert_line_count_regex "$d/r.tap" "^not ok [0-9] - $d/t/b-fail\\.sh\$" 1 || return
  assert_line_count_regex "$d/r.tap" "^ok [0-9] - $d/t/c-skip\\.sh # SKIP\$" 1 || return
  assert_line_count_regex "$d/r.tap" "^ok [0-9] - $d/t/d-hash\\\\#name\\.sh\$" 1 || return
  assert_line_count_regex "$d/r.tap" "^not ok [0-9] - $d/t/e\\.worker\\.suite\\.sh\$" 1 || return
  assert_line_count_regex "$d/r.tap" "^not ok [0-9] - $d/t/e\\.worker\\.suite\\.sh::two\$" 1 || return
  assert_line_count_regex "$d/r.tap" '^# notrun, status 4$' 2 || return
  assert_line_count_regex "$d/r.tap" '^(not )?ok [1-7] - ' 7 || return
}

t_unit_junit_report() {
  echo "# -j writes a valid JUnit XML report"
  local d
  case_dir junit; d="$CASE_DIR"
  write_mixed_results "$d/t"

  run_unit_reports "$d/out" "$d/err" "$d/t"
  python3 -c 'import sys, xml.dom.minidom; xml.dom.minidom.parse(sys.argv[1])' "$d/r.xml" \
    || { fail_msg "invalid XML: $d/r.xml"; return 1; }
  assert_contains "$d/r.xml" '<testsuite name="knockout.sh" tests="7" failures="1" errors="3" skipped="1" time="' || return
  assert_contains "$d/r.xml" "<testcase classname=\"$d/t/a-pass.sh\" name=\"$d/t/a-pass.sh\" time=\"" || return
  assert_contains "$d/r.xml" '<failure message="exit status 3">err &lt;&amp;&quot;&gt; y' || return
  assert_contains "$d/r.xml" '<system-out>out &lt;&amp;&quot;&gt; x' || return
  assert_contains "$d/r.xml" '<skipped/>' || return
  assert_contains "$d/r.xml" "<testcase classname=\"$d/t/e.worker.suite.sh\" name=\"two\"" || return
  assert_contains "$d/r.xml" '<error message="notrun, status 4"/>' || return
}

t_unit_suite_cases_get_empty_stdin() {
  echo "# suite cases get empty stdin (forked and turbo)"
  local d f
  case_dir suite-stdin; d="$CASE_DIR"
  for f in "$d/a.suite.sh" "$d/a.turbo.suite.sh"; do
    write_fn_suite "$f" <<'BODY'
t_one() { echo "# one"; [[ -z "$(cat)" ]] || { echo "stdin not empty" >&2; return 1; }; }
t_two() { echo "# two"; [[ -z "$(cat)" ]] || { echo "stdin not empty" >&2; return 1; }; }
BODY
  done

  run_unit "$d/out" "$d/err" "$d/a.suite.sh" "$d/a.turbo.suite.sh"
  assert_eq "0" "$KO_RC" "suite cases should read empty stdin" || return
  assert_file_empty "$d/err" || return
  assert_contains "$d/out" "[S 4/4]" || return
}

t_int_commands() {
  echo "# knockout.sh equals knockout.sh run; a file argument is an unknown command; -d needs a dir; python3-unittest usage"
  local d here
  case_dir commands; d="$CASE_DIR"
  mkdir -p "$d/proj/knockout-tests"
  printf 'echo "# a"\n' >"$d/proj/knockout-tests/a.sh"

  here="$PWD"
  cd "$d/proj"
  run_ko "$d/bare.out" "$d/bare.err"
  local bare_rc="$KO_RC"
  run_ko "$d/run.out" "$d/run.err" run
  local run_rc="$KO_RC"
  run_ko "$d/file.out" "$d/file.err" knockout-tests/a.sh
  local file_rc="$KO_RC"
  run_ko "$d/missing.out" "$d/missing.err" -d nope
  local missing_rc="$KO_RC"
  run_ko "$d/py1.out" "$d/py1.err" python3-unittest
  local py1_rc="$KO_RC"
  run_ko "$d/py2.out" "$d/py2.err" python3-unittest discover -x y
  local py2_rc="$KO_RC"
  cd "$here"

  assert_eq "0 0" "$bare_rc $run_rc" "knockout.sh and knockout.sh run should pass" || return
  assert_eq "$(normalize_run "$d/bare.out")" "$(normalize_run "$d/run.out")" "knockout.sh and knockout.sh run should match" || return
  assert_eq "1" "$file_rc" "file argument should fail" || return
  assert_contains "$d/file.err" "unknown command: knockout-tests/a.sh" || return
  assert_contains "$d/file.err" "usage:" || return
  assert_eq "1" "$missing_rc" "missing -d dir should fail" || return
  assert_contains "$d/missing.err" "die: path not found: nope" || return
  assert_eq "1 1" "$py1_rc $py2_rc" "python3-unittest without discover or with unknown option should fail" || return
  assert_contains "$d/py1.err" "usage: knockout.sh python3-unittest discover" || return
  assert_contains "$d/py2.err" "usage: knockout.sh python3-unittest discover" || return
}

# --- unit tests of single functions ---

t_unit_name_classification() {
  echo "# is_suite / is_turbo / is_sh classify file names"
  local f
  for f in a.suite a.suite.sh a.suite.py dir/a.turbo.suite.sh; do
    is_suite "$f" || { fail_msg "should be a suite: $f"; return 1; }
  done
  for f in .suite suite.sh a.suites a_suite.sh a.sh; do
    ! is_suite "$f" || { fail_msg "should not be a suite: $f"; return 1; }
  done
  is_turbo a.turbo.suite.sh || { fail_msg "a.turbo.suite.sh should be turbo"; return 1; }
  ! is_turbo a.suite.sh || { fail_msg "a.suite.sh should not be turbo"; return 1; }
  ! is_turbo a.turbo.suite || { fail_msg "turbo needs .sh"; return 1; }
  is_sh x.sh && ! is_sh x.bash || { fail_msg "is_sh wrong"; return 1; }
}

t_unit_sanitize_name() {
  echo "# sanitize_name maps designations to safe file names"
  local v
  sanitize_name "dir/a.suite.sh::case (x y)" v
  assert_eq "dir__a.suite.sh__case__x_y_" "$v" || return
  assert_eq "a_b" "$(sanitize_name "a b")" "printing form" || return
}

t_unit_parse_suite_line() {
  echo "# parse_suite_line splits on TABs, else parses bash words"
  parse_suite_line $'tabbed\tthree words\tfour'
  assert_eq "3|tabbed|three words|four" "${#PARSED_ARGS[@]}|${PARSED_ARGS[0]}|${PARSED_ARGS[1]}|${PARSED_ARGS[2]}" || return
  parse_suite_line $'alpha "two words" \'single\' x'
  assert_eq "4|alpha|two words|single|x" "${#PARSED_ARGS[@]}|${PARSED_ARGS[0]}|${PARSED_ARGS[1]}|${PARSED_ARGS[2]}|${PARSED_ARGS[3]}" || return
}

t_unit_case_designation() {
  echo "# suite_case_designation formats name and remaining args"
  suite_case_designation s.suite.sh
  assert_eq "s.suite.sh" "$CASE_DESIGNATION" || return
  suite_case_designation s.suite.sh add
  assert_eq "s.suite.sh::add" "$CASE_DESIGNATION" || return
  suite_case_designation s.suite.sh add "1 2" 3
  assert_eq "s.suite.sh::add (1\\ 2 3)" "$CASE_DESIGNATION" || return
}

t_unit_description_and_progress() {
  echo "# description extraction and progress line format"
  local d desc
  case_dir progress; d="$CASE_DIR"
  printf '# hello world\nmore\n' >"$d/with"
  printf 'no description\n' >"$d/without"
  printf '# no newline' >"$d/nonl"
  extract_description_from_stdout "$d/with" desc
  assert_eq "hello world" "$desc" || return
  extract_description_from_stdout "$d/without" desc
  assert_eq "" "$desc" || return
  extract_description_from_stdout "$d/nonl" desc
  assert_eq "no newline" "$desc" || return
  assert_eq "[S 2/10] f::x  0.012s  -- hi" "$(print_progress S 2 10 f::x 0.012 hi)" || return
  assert_eq "[T 1/1] f  0.000s" "$(print_progress T 1 1 f 0.000 "")" || return
}

t_unit_testsuite_output_helpers() {
  echo "# testsuite marker detection, line extraction and counting"
  local d
  case_dir suite-helpers; d="$CASE_DIR"
  printf '#!testsuite\n# heading\none\n\ntwo x\n' >"$d/out"
  is_testsuite_output "$d/out" || { fail_msg "marker not detected"; return 1; }
  printf 'x\n#!testsuite\n' >"$d/nomark"
  ! is_testsuite_output "$d/nomark" || { fail_msg "marker must be first line"; return 1; }
  write_testsuite_lines "$d/out" "$d/lines"
  assert_eq $'one\n\ntwo x' "$(<"$d/lines")" || return
  assert_eq "2" "$(count_suite_lines "$d/lines")" || return
  : >"$d/empty"
  assert_eq "0" "$(count_suite_lines "$d/empty")" || return
}

t_unit_report_error() {
  echo "# report_error prints status, hint and both streams"
  local d
  case_dir report; d="$CASE_DIR"
  printf 'out no newline' >"$d/out"
  : >"$d/err"
  report_error "x.sh" 3 "$d/out" "$d/err" "some hint" 2>"$d/report"
  assert_eq "1" "$had_test_error" "report_error should flag the run" || return
  assert_eq $'ERROR\ntest: x.sh\nstatus: 3\nhint: some hint\n--- stdout ---\nout no newline\n--- stderr ---\n(empty)' "$(<"$d/report")" || return
}

t_unit_discover_test_dirs() {
  echo "# discover_test_dirs finds named and marked dirs, skips hidden"
  local d
  case_dir discover; d="$CASE_DIR"
  mkdir -p "$d/b/knockout-tests" "$d/a" "$d/.hidden/knockout-tests" "$d/c/.git" "$d/plain"
  : >"$d/a/.knockout-tests"
  : >"$d/c/.git/.knockout-tests"
  assert_eq $'a\nb/knockout-tests' "$(cd "$d" && discover_test_dirs)" || return
}

t_unit_fn_suite_handler() {
  echo "# fn-suite handler lists, skips --options, rejects unknown tests"
  local d
  case_dir handler; d="$CASE_DIR"
  {
    print_fn_suite
    printf 't_b() { echo "b:$*"; }\nt_a() { :; }\ntestsuite_main "$@"\n'
  } >"$d/s.sh"
  local rc=0
  bash "$d/s.sh" >"$d/list" || rc=$?
  assert_eq "88" "$rc" "listing exits 88" || return
  assert_eq $'#!testsuite\na\nb' "$(<"$d/list")" || return
  assert_eq "b:x y" "$(bash "$d/s.sh" --opt -- b x y)" || return
  rc=0
  bash "$d/s.sh" nope 2>"$d/err" || rc=$?
  assert_eq "1" "$rc" "unknown test exits 1" || return
  assert_contains "$d/err" "no such test: nope" || return
}

t_int_sourcing_runs_nothing() {
  echo "# sourcing knockout defines functions only"
  local d
  case_dir sourcing; d="$CASE_DIR"
  bash -c 'source "$1" fn-suite; declare -F run_paths >/dev/null || exit 3; trap -p EXIT' _ "$KO_UNDER_TEST" >"$d/out" 2>"$d/err" \
    || { fail_msg "sourcing failed or run_paths missing"; return 1; }
  assert_file_empty "$d/out" || return
  assert_file_empty "$d/err" || return
}

t_unit_elapsed_secs() {
  echo "# elapsed_secs computes seconds from EPOCHREALTIME values"
  local v
  elapsed_secs 100.000000 100.000000 v; assert_eq "0.000" "$v" "zero" || return
  elapsed_secs 100.000000 101.000000 v; assert_eq "1.000" "$v" "whole second" || return
  elapsed_secs 100.000000 100.012999 v; assert_eq "0.012" "$v" "truncates to ms" || return
  elapsed_secs 100.999500 101.000400 v; assert_eq "0.000" "$v" "carry across decimal point" || return
  elapsed_secs 100.900000 102.150000 v; assert_eq "1.250" "$v" "seconds and ms" || return
  elapsed_secs 100,000000 100,250000 v; assert_eq "0.250" "$v" "comma decimal separator" || return
}

t_unit_elapsed_time_is_plausible() {
  echo "# reported times match a 0.1s sleep (forked and turbo)"
  local d t
  case_dir plausible-time; d="$CASE_DIR"
  printf 'sleep 0.1\n' >"$d/slow.sh"
  write_fn_suite "$d/slow.turbo.suite.sh" <<'BODY'
t_nap() { sleep 0.1; }
BODY

  run_unit "$d/out" "$d/err" "$d/slow.sh" "$d/slow.turbo.suite.sh"
  assert_eq "0" "$KO_RC" "slow tests should pass" || return
  for t in "$d/slow.sh" "$d/slow.turbo.suite.sh::nap"; do
    local secs
    secs="$(sed -nE "s#^\[[TS] [0-9]+/[0-9]+\] ${t//./\\.}  ([0-9]+\.[0-9]{3})s.*#\1#p" "$d/out")"
    [[ -n "$secs" ]] || { fail_msg "no progress line for $t"; sed 's/^/      | /' "$d/out" >&2; return 1; }
    # 0.100 <= secs < 0.300, compared in ms
    local ms=$(( 10#${secs/./} ))
    (( ms >= 100 && ms < 300 )) || { fail_msg "implausible time for $t: ${secs}s"; return 1; }
  done
}

testsuite_main "$@"
