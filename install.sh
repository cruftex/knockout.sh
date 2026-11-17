#!/usr/bin/env bash
# Symlink knockout into ~/.local/bin (or $PREFIX/bin) as `knockout` and `ko`.
set -euo pipefail
src="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/bin/knockout"
dest="${PREFIX:-$HOME/.local}/bin"
mkdir -p "$dest"
for name in knockout ko; do
  ln -sfn "$src" "$dest/$name"
  echo "$dest/$name -> $src"
done
