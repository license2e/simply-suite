$ErrorActionPreference = 'Stop'

$Here    = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root    = [System.IO.Path]::GetFullPath((Join-Path $Here '..\..'))       # repo root
$RubyDir = [System.IO.Path]::GetFullPath((Join-Path $Here '..\vendor\ruby'))

if (-not (Test-Path "$RubyDir\bin\ruby.exe")) {
  Write-Error "Bundled Ruby not found - run build\stage-ruby-win.ps1 first."
}

# Put the bundled Ruby first on PATH for this process. RubyInstaller-2 auto-loads
# its MSYS2 build environment for native gems, so no explicit `ridk enable`.
$env:PATH = "$RubyDir\bin;$env:PATH"

# Isolate bundler config so `bundle config set --local` does NOT clobber the
# repo's own .bundle/config.
$env:BUNDLE_APP_CONFIG = (Join-Path $env:TEMP ("ss-bundle-" + [System.Guid]::NewGuid().ToString()))
New-Item -ItemType Directory -Path $env:BUNDLE_APP_CONFIG | Out-Null

Set-Location $Root
Write-Host "Vendoring production gems with $(& "$RubyDir\bin\ruby.exe" -v)"

& "$RubyDir\bin\bundle.cmd" config set --local path 'vendor/bundle'
& "$RubyDir\bin\bundle.cmd" config set --local without 'development test'
& "$RubyDir\bin\bundle.cmd" install --standalone

if (Test-Path "$Root\vendor\bundle\bundler\setup.rb") { Write-Host "Standalone bundle ready." }
Remove-Item -Recurse -Force $env:BUNDLE_APP_CONFIG
