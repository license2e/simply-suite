#!/usr/bin/env bash
set -euo pipefail

RUBY_VERSION="${RUBY_VERSION:-3.3.11}"
HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="$HERE/../vendor/ruby"
BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT

# macOS ships neither an OpenSSL nor a libyaml that Ruby's configure finds by
# default (and Homebrew's openssl@3 is keg-only). Install and point at them.
if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is required to build Ruby on macOS." >&2
  exit 1
fi
brew list openssl@3 >/dev/null 2>&1 || brew install openssl@3
brew list libyaml   >/dev/null 2>&1 || brew install libyaml
OPENSSL_DIR="$(brew --prefix openssl@3)"
LIBYAML_DIR="$(brew --prefix libyaml)"
export PKG_CONFIG_PATH="$OPENSSL_DIR/lib/pkgconfig:$LIBYAML_DIR/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"

echo "Building relocatable Ruby $RUBY_VERSION ($(uname -m)) -> $DEST"
curl -fsSL "https://cache.ruby-lang.org/pub/ruby/${RUBY_VERSION%.*}/ruby-${RUBY_VERSION}.tar.gz" -o "$BUILD/ruby.tar.gz"
tar -xzf "$BUILD/ruby.tar.gz" -C "$BUILD"
cd "$BUILD/ruby-${RUBY_VERSION}"

# --disable-shared: static libruby => relocatable inside the .app.
# --enable-load-relative: stdlib located relative to the executable.
./configure --prefix="$DEST" \
  --disable-shared --enable-load-relative --disable-install-doc \
  --with-openssl-dir="$OPENSSL_DIR" \
  --with-libyaml-dir="$LIBYAML_DIR"
make -j"$(sysctl -n hw.ncpu)"
rm -rf "$DEST"
make install

"$DEST/bin/ruby" -v
"$DEST/bin/ruby" -ropenssl -e 'puts "openssl ok: #{OpenSSL::OPENSSL_VERSION}"'
"$DEST/bin/ruby" -rpsych  -e 'puts "psych/libyaml ok: #{Psych::LIBYAML_VERSION}"'
"$DEST/bin/gem" install bundler --no-document --force
echo "Bundled Ruby (macOS) ready."
