#!/usr/bin/env bash
# Runs knockout.suite.sh a second time, independent of any knockout code:
# source it with knockout and its dispatcher stubbed out, then call every
# t_* function directly.
set -euo pipefail
echo "# knockout.suite.sh via embedded runner"

knockout() { :; }        # source <(knockout fn-suite) sources nothing
testsuite_main() { :; }  # the suite's trailing dispatcher call does nothing
source "$(dirname "${BASH_SOURCE[0]}")/knockout.suite.sh"

pass=0
fail=0
out="$ROOT/runner.out"
err="$ROOT/runner.err"
for fn in $(declare -F | awk '$3 ~ /^t_/ { print $3 }'); do
  set +e
  ( "$fn" ) >"$out" 2>"$err"
  status=$?
  set -e
  if [[ "$status" -eq 0 && ! -s "$err" ]]; then
    pass=$((pass + 1))
    echo "PASS ${fn#t_}"
  else
    fail=$((fail + 1))
    echo "FAIL ${fn#t_}"
    { echo "FAIL ${fn#t_} (status $status)"; sed 's/^/    /' "$err"; } >&2
  fi
done

echo "$pass passed, $fail failed"
if [[ "$fail" -ne 0 || "$pass" -eq 0 ]]; then
  echo "$pass passed, $fail failed" >&2
  exit 1
fi
