#!/usr/bin/env bash
# Install knockout.sh into ~/.local/bin (or $PREFIX/bin): one copy of the
# self-contained script as `knockout.sh`. Rerun to update.
set -euo pipefail
src="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/bin/knockout.sh"
dest="${PREFIX:-$HOME/.local}/bin"
mkdir -p "$dest"
# Remove first: an old install may be a symlink into this checkout, and
# copying through it would overwrite bin/knockout.sh itself.
rm -f "$dest/knockout.sh"
install -m 755 "$src" "$dest/knockout.sh"
echo "$dest/knockout.sh (copy of $src)"

# Earlier versions installed `knockout` and a `ko` symlink. Remove them only if
# they are ours; a foreign `knockout` or `ko` is left alone.
if [[ -L "$dest/ko" && "$(readlink "$dest/ko")" == knockout ]]; then
  rm -f "$dest/ko"
  echo "removed old $dest/ko"
fi
if [[ -f "$dest/knockout" ]] && grep -q 'CANONICAL GENERATION PROMPT' "$dest/knockout"; then
  rm -f "$dest/knockout"
  echo "removed old $dest/knockout"
fi
