#!/usr/bin/env bash
set -euo pipefail

RUBY_VERSION="${RUBY_VERSION:-3.3.11}"
HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="$HERE/../vendor/ruby"
BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT

echo "Building relocatable Ruby $RUBY_VERSION -> $DEST"
curl -fsSL "https://cache.ruby-lang.org/pub/ruby/${RUBY_VERSION%.*}/ruby-${RUBY_VERSION}.tar.gz" -o "$BUILD/ruby.tar.gz"
tar -xzf "$BUILD/ruby.tar.gz" -C "$BUILD"
cd "$BUILD/ruby-${RUBY_VERSION}"

# --disable-shared: statically link libruby into the binary => fully relocatable
# --enable-load-relative: locate the stdlib relative to the executable
./configure --prefix="$DEST" --disable-shared --enable-load-relative --disable-install-doc
make -j"$(nproc)"
rm -rf "$DEST"
make install

"$DEST/bin/ruby" -v
"$DEST/bin/gem" install bundler --no-document
echo "Bundled Ruby ready."
