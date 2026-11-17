#!/usr/bin/env bash
# Runs knockout.turbo.suite.sh a second time, independent of any knockout code:
# source it with knockout and its dispatcher stubbed out, then call every
# t_* function directly.
set -euo pipefail
echo "# knockout.turbo.suite.sh via embedded runner"

# Standalone there is no harness knockout on PATH: default to this checkout.
KO_UNDER_TEST="${KO_UNDER_TEST:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/knockout.sh}"
export KO_UNDER_TEST

knockout.sh() { :; }     # source <(knockout.sh fn-suite) sources nothing
testsuite_main() { :; }  # the suite's trailing dispatcher call does nothing
source "$(dirname "${BASH_SOURCE[0]}")/knockout.turbo.suite.sh"

pass=0
fail=0
runner_tmp="$(mktemp -d)"
trap 'rm -rf "$runner_tmp"' EXIT
out="$runner_tmp/out"
err="$runner_tmp/err"
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
