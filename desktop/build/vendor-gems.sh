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
bundle config set --local path 'vendor/bundle'
bundle config set --local without 'development test'
bundle install --standalone

test -f vendor/bundle/bundler/setup.rb && echo "Standalone bundle ready."
