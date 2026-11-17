#!/usr/bin/env bash
# knockout self-test suite (t_* functions). Runs via knockout (`ko`), a second
# time independently via test/knockout-test.sh, or one case:
#   test/knockout.suite.sh <name>
# Tests another implementation with the normal knockout as harness:
#   KO_UNDER_TEST=/path/to/other ko test/
set -euo pipefail
source <(knockout fn-suite)

# Implementation under test: the knockout running this suite (first on PATH;
# knockout puts itself there), or another one via KO_UNDER_TEST. Resolved to an
# absolute path because tests cd and run with a reduced PATH.
ko_wanted="${KO_UNDER_TEST:-knockout}"
if ! KO_UNDER_TEST="$(type -P "$ko_wanted")"; then
  printf 'knockout under test not found: %s\n' "$ko_wanted" >&2
  exit 2
fi
KO_UNDER_TEST="$(readlink -f "$KO_UNDER_TEST")"

ROOT="$(mktemp -d "${TMPDIR:-/tmp}/ko-test.XXXXXXXXXX")"
trap 'rm -rf "$ROOT"' EXIT

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

t_usage_without_args() {
  echo "# usage without arguments"
  local d out err
  d="$(case_dir usage)"
  out="$d/out"
  err="$d/err"

  # Empty cwd: project mode must find nothing (and never this repo's tests).
  local here="$PWD"
  cd "$d"
  run_ko "$out" "$err"
  cd "$here"
  assert_eq "1" "$RUN_STATUS" "usage should exit 1" || return
  assert_file_empty "$out" || return
  assert_contains "$err" "no test dirs found" || return
  assert_contains "$err" "usage: ${KO_UNDER_TEST##*/} [-v] [-d] [<file-or-dir>...]" || return
}

t_executable_success_and_description() {
  echo "# executable test success and description"
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

t_non_executable_sh_runs_with_bash() {
  echo "# non-executable .sh runs via bash"
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

t_rejects_non_executable_non_sh() {
  echo "# non-executable non-.sh is rejected"
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

t_stderr_marks_failure() {
  echo "# stderr marks test failure"
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

t_nonzero_failure_continues() {
  echo "# nonzero failure reports and continues"
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

t_directory_expansion_is_non_recursive() {
  echo "# directory expansion is non-recursive"
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

t_keep_tmp_writes_artifacts() {
  echo "# -d keeps stdout/stderr/status artifacts"
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

t_verbose_passes_through_stdout() {
  echo "# -v passes through stdout"
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

t_testsuite_runs_generated_cases() {
  echo "# extensionless .suite generates cases with shell and tab parsing"
  local d suite out err
  d="$(case_dir generated-suite)"
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

  run_ko "$out" "$err" "$suite"
  assert_eq "0" "$RUN_STATUS" "generated suite should pass" || return
  assert_file_empty "$err" || return
  assert_contains "$out" "[L 1/1] $suite" || return
  assert_contains "$out" "[S 1/2] $suite::alpha" || return
  assert_contains "$out" "-- alpha generated case" || return
  assert_contains "$out" "::tabbed" || return
  assert_contains "$out" "-- tab generated case" || return
}

t_testsuite_description_lines_are_ignored() {
  echo "# testsuite description lines are ignored"
  local d suite out err
  d="$(case_dir generated-suite-comments)"
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

  run_ko "$out" "$err" "$suite"
  assert_eq "0" "$RUN_STATUS" "description lines in suite output should be ignored" || return
  assert_file_empty "$err" || return
  assert_contains "$out" "[S 1/1] $suite::alpha" || return
  assert_not_contains "$out" "[S 2/2]" || return
}

t_fn_suite_prints_handler() {
  echo "# fn-suite prints a sourceable handler"
  local dir out err
  dir="$(case_dir fn-suite-print)"
  out="$dir/out"
  err="$dir/err"

  run_ko "$out" "$err" fn-suite
  assert_eq "0" "$RUN_STATUS" "fn-suite should exit 0" || return
  assert_file_empty "$err" || return
  bash -n "$out" || { fail_msg "fn-suite output is not valid bash"; return 1; }
  # shellcheck disable=SC1090
  (source "$out" && declare -F testsuite_main >/dev/null) \
    || { fail_msg "fn-suite output does not define testsuite_main"; return 1; }
}

t_fn_suite_sourced_by_suite_without_install() {
  echo "# suite sources fn-suite from the running knockout"
  local dir out err suite
  dir="$(case_dir fn-suite-source)"
  out="$dir/out"
  err="$dir/err"
  suite="$dir/x.suite.sh"

  cat >"$suite" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
source <(knockout fn-suite)
t_one() { echo "# first"; }
t_two() { echo "# second"; }
t_three() { echo "# third"; }
testsuite_main "$@"
SCRIPT
  make_executable "$suite"

  # Minimal PATH without any installed knockout: runner must provide itself.
  PATH="/usr/bin:/bin" run_ko "$out" "$err" "$suite"
  assert_eq "0" "$RUN_STATUS" "suite sourcing fn-suite should pass" || return
  assert_file_empty "$err" || return
  assert_contains "$out" "[S 3/3]" || return
  assert_contains "$out" "-- third" || return
}

t_mixed_run_has_exact_shared_total() {
  echo "# mixed run has exact shared total"
  local dir out err
  dir="$(case_dir mixed-total)"
  out="$dir/out"
  err="$dir/err"

  printf '#!/usr/bin/env bash\necho ok\n' >"$dir/a.sh"
  cat >"$dir/b.suite.sh" <<'SCRIPT'
if [[ "$#" -eq 0 ]]; then printf '#!testsuite\none\ntwo\n'; exit 88; fi
echo "case $1"
SCRIPT
  printf '#!/usr/bin/env bash\necho ok\n' >"$dir/c.sh"

  run_ko "$out" "$err" "$dir/a.sh" "$dir/b.suite.sh" "$dir/c.sh"
  assert_eq "0" "$RUN_STATUS" "mixed run should pass" || return
  assert_file_empty "$err" || return
  assert_contains "$out" "[L 1/1] $dir/b.suite.sh" || return
  assert_contains "$out" "[T 1/4] $dir/a.sh" || return
  assert_contains "$out" "[S 2/4] $dir/b.suite.sh::one" || return
  assert_contains "$out" "[S 3/4] $dir/b.suite.sh::two" || return
  assert_contains "$out" "[T 4/4] $dir/c.sh" || return
}

t_unnamed_suite_output_fails_with_hint() {
  echo "# testsuite output from non-suite name fails with hint"
  local dir out err t
  dir="$(case_dir unnamed-suite)"
  out="$dir/out"
  err="$dir/err"
  t="$dir/sneaky.sh"
  printf '#!/usr/bin/env bash\nprintf "#!testsuite\\none\\n"\nexit 88\n' >"$t"

  run_ko "$out" "$err" "$t"
  assert_eq "1" "$RUN_STATUS" "testsuite output from non-suite name should fail" || return
  assert_contains "$err" "hint: testsuite output from a file not named as testsuite" || return
  assert_not_contains "$out" "[S " || return
}

t_broken_listing_fails_and_continues() {
  echo "# broken suite listings fail and the run continues"
  local dir out err
  dir="$(case_dir broken-listing)"
  out="$dir/out"
  err="$dir/err"

  printf 'echo "no marker"\nexit 0\n' >"$dir/nomarker.suite.sh"
  printf 'printf "#!testsuite\\none\\n"; echo oops >&2; exit 88\n' >"$dir/noisy.suite.sh"
  printf 'echo ok\n' >"$dir/plain.sh"

  run_ko "$out" "$err" "$dir/nomarker.suite.sh" "$dir/noisy.suite.sh" "$dir/plain.sh"
  assert_eq "1" "$RUN_STATUS" "broken listings should fail the run" || return
  assert_contains "$err" "test: $dir/nomarker.suite.sh" || return
  assert_contains "$err" "test: $dir/noisy.suite.sh" || return
  assert_contains "$err" "hint: testsuite listing must exit 88" || return
  assert_contains "$out" "[T 1/1] $dir/plain.sh" || return
  assert_not_contains "$out" "[S " || return
}

t_project_mode_discovers_test_dirs() {
  echo "# no arguments runs test dirs below cwd"
  local d out err here
  d="$(case_dir project-mode)"
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
  assert_eq "0" "$RUN_STATUS" "project mode should pass" || return
  assert_file_empty "$err" || return
  assert_contains "$out" "[T 1/2] knockout-tests/a.sh" || return
  assert_contains "$out" "[T 2/2] sub/b.sh" || return
  assert_not_contains "$out" ".knockout-tests" || return
}

t_marker_file_is_not_a_test() {
  echo "# marker file in a test dir is not a test"
  local d out err
  d="$(case_dir marker-ignored)"
  out="$d/out"
  err="$d/err"
  mkdir -p "$d/t"
  : >"$d/t/.knockout-tests"
  printf 'echo ok\n' >"$d/t/ok.sh"

  run_ko "$out" "$err" "$d/t"
  assert_eq "0" "$RUN_STATUS" "explicit dir with marker should pass" || return
  assert_file_empty "$err" || return
  assert_contains "$out" "[T 1/1] $d/t/ok.sh" || return
}

write_fn_suite() {
  # $1 path; stdin: body (t_* functions and top-level code)
  {
    printf '#!/usr/bin/env bash\nset -euo pipefail\nsource <(knockout fn-suite)\n'
    cat
    printf 'testsuite_main "$@"\n'
  } >"$1"
}

normalize_run() {
  # Strip timings and the suite file name so forked and turbo runs compare equal.
  sed -E 's/  [0-9]+\.[0-9]+s/  Ns/; s#[^ ]*/s\.(turbo\.)?suite\.sh#SUITE#g' "$1"
}

t_turbo_matches_forked() {
  echo "# turbo suite reports exactly like a forked suite"
  local d body
  d="$(case_dir turbo-golden)"
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

  run_ko "$d/f.out" "$d/f.err" "$d/s.suite.sh"
  local forked_status="$RUN_STATUS"
  run_ko "$d/t.out" "$d/t.err" "$d/s.turbo.suite.sh"
  assert_eq "$forked_status" "$RUN_STATUS" "turbo exit status should match forked" || return
  assert_eq "1" "$RUN_STATUS" "suite with failures should fail" || return
  assert_eq "$(normalize_run "$d/f.out")" "$(normalize_run "$d/t.out")" "turbo stdout should match forked" || return
  assert_eq "$(normalize_run "$d/f.err")" "$(normalize_run "$d/t.err")" "turbo error report should match forked" || return
  assert_contains "$d/t.out" "[S 3/4] $d/s.turbo.suite.sh::spaces (a\\ b c)" || return
}

t_turbo_isolates_cases() {
  echo "# turbo suite isolates cases in subshells"
  local d
  d="$(case_dir turbo-isolation)"
  write_fn_suite "$d/i.turbo.suite.sh" <<'BODY'
echo sourced >>"$(dirname "${BASH_SOURCE[0]}")/count"
t_a_set() { SHARED=changed; cd /; echo "# a"; }
t_b_check() { echo "# b"; [[ "${SHARED:-unset}" == unset && "$PWD" != / ]]; }
t_c_exit() { echo "# c"; exit 3; }
t_d_after() { echo "# d"; }
BODY

  run_ko "$d/out" "$d/err" "$d/i.turbo.suite.sh"
  assert_eq "1" "$RUN_STATUS" "exit 3 in one case should fail the run" || return
  assert_contains "$d/out" "[S 4/4] $d/i.turbo.suite.sh::d_after" || return
  assert_contains "$d/err" "test: $d/i.turbo.suite.sh::c_exit" || return
  assert_not_contains "$d/err" "b_check" || return
  # Sourced once for the listing (phase L) and once by the turbo worker.
  assert_eq "2" "$(wc -l <"$d/count")" "top-level code should run once per worker, not per case" || return
}

t_turbo_source_failure() {
  echo "# turbo suite source failure skips its tests"
  local d
  d="$(case_dir turbo-source-fail)"
  write_fn_suite "$d/bad.turbo.suite.sh" <<'BODY'
t_one() { echo "# one"; }
t_two() { echo "# two"; }
[[ "$#" -eq 0 && "${BASH_SOURCE[0]}" == "$0" ]] || { echo "setup broke" >&2; false; }
BODY
  printf 'echo ok\n' >"$d/after.sh"

  run_ko "$d/out" "$d/err" "$d/bad.turbo.suite.sh" "$d/after.sh"
  assert_eq "1" "$RUN_STATUS" "source failure should fail the run" || return
  assert_contains "$d/err" "hint: turbo suite failed while being sourced; its 2 tests were not run" || return
  assert_contains "$d/err" "setup broke" || return
  assert_not_contains "$d/out" "::one" || return
  assert_contains "$d/out" "[T 3/3] $d/after.sh" || return
}

t_suite_cases_get_empty_stdin() {
  echo "# suite cases get empty stdin (forked and turbo)"
  local d f
  d="$(case_dir suite-stdin)"
  for f in "$d/a.suite.sh" "$d/a.turbo.suite.sh"; do
    write_fn_suite "$f" <<'BODY'
t_one() { echo "# one"; [[ -z "$(cat)" ]] || { echo "stdin not empty" >&2; return 1; }; }
t_two() { echo "# two"; [[ -z "$(cat)" ]] || { echo "stdin not empty" >&2; return 1; }; }
BODY
  done

  run_ko "$d/out" "$d/err" "$d/a.suite.sh" "$d/a.turbo.suite.sh"
  assert_eq "0" "$RUN_STATUS" "suite cases should read empty stdin" || return
  assert_file_empty "$d/err" || return
  assert_contains "$d/out" "[S 4/4]" || return
}

testsuite_main "$@"
