# shellcheck shell=bash
# Sourceable library implementing the knockout "#!testsuite" protocol.

# -----------------------------------------------------------------------------
# CONSOLIDATED GENERATION PROMPT (origin: papa-ps testsuite-example.sh)
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
#
# Library usage: source this file from a test script, define t_* functions,
# then call `testsuite_main "$@"` as the last line. TESTSUITE_PREFIX
# overrides the "t_" prefix.

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
