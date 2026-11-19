#!/usr/bin/env bash
# Install knockout.sh into ~/.local/bin (or $PREFIX/bin): one copy of the
# self-contained script as `knockout.sh`. Rerun to update.
set -euo pipefail
src="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/bin/knockout.sh"
dest="${PREFIX:-$HOME/.local}/bin"
version="$("$src" -v)"
mkdir -p "$dest"
# Stage beside the destination so the move replaces even an old symlink.
staged="$(mktemp "$dest/.knockout.sh.XXXXXX")"
trap 'rm -f -- "$staged"' EXIT
sed "s/^KNOCKOUT_VERSION='GIT'$/KNOCKOUT_VERSION='$version'/" "$src" >"$staged"
chmod 755 "$staged"
mv -fT -- "$staged" "$dest/knockout.sh"
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
