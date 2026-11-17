#!/usr/bin/env bash
# Example knockout testsuite: run directly or with `knockout.sh -d examples`.
set -euo pipefail
source <(knockout.sh fn-suite)

t_test() {
  echo "# basic test example"
  echo "running test; args: $*"
}

t_hello() {
  echo "# says hello"
  echo "hello; args: $*"
}

t_another() {
  echo "# another example test"
  echo "another; args: $*"
}

testsuite_main "$@"
