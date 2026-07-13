#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"          # repo root
RUBY_DIR="$HERE/../vendor/ruby-linux"

if [ ! -x "$RUBY_DIR/bin/ruby" ]; then
  echo "Bundled Ruby not found — run build/stage-ruby-linux.sh first." >&2
  exit 1
fi

export PATH="$RUBY_DIR/bin:$PATH"
cd "$ROOT"
echo "Vendoring production gems with $(ruby -v)"

# Isolate bundler's config to a throwaway dir (BUNDLE_APP_CONFIG) so `bundle
# config set --local` does NOT clobber the repo's own .bundle/config (which
# carries the dev BUNDLE_WITHOUT etc). Gems still install to ./vendor/bundle.
export BUNDLE_APP_CONFIG="$(mktemp -d)"
trap 'rm -rf "$BUNDLE_APP_CONFIG"' EXIT

bundle config set --local path 'vendor/bundle'
bundle config set --local without 'development test'
bundle install --standalone

test -f vendor/bundle/bundler/setup.rb && echo "Standalone bundle ready."
