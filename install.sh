#!/usr/bin/env bash
# Install knockout into ~/.local/bin (or $PREFIX/bin): one copy of the
# self-contained script as `knockout`, plus `ko` as a symlink to it.
set -euo pipefail
src="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/bin/knockout"
dest="${PREFIX:-$HOME/.local}/bin"
mkdir -p "$dest"
# Remove first: an old install may be a symlink into this checkout, and
# copying through it would overwrite bin/knockout itself.
rm -f "$dest/knockout"
install -m 755 "$src" "$dest/knockout"
ln -sfn knockout "$dest/ko"
echo "$dest/knockout (copy of $src)"
echo "$dest/ko -> knockout"
