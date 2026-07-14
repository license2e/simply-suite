$ErrorActionPreference = 'Stop'

$RubyVersion = if ($env:RUBY_VERSION) { $env:RUBY_VERSION } else { '3.3.11' }
# RubyInstaller package release suffix (the "-1" in RubyInstaller-3.3.11-1).
$Rel = if ($env:RUBYINSTALLER_REL) { $env:RUBYINSTALLER_REL } else { '1' }

$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Dest = [System.IO.Path]::GetFullPath((Join-Path $Here '..\vendor\ruby'))
$Tmp  = Join-Path $env:TEMP ("ss-ruby-" + [System.Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $Tmp | Out-Null

$Asset = "rubyinstaller-devkit-$RubyVersion-$Rel-x64.exe"
$Url   = "https://github.com/oneclick/rubyinstaller2/releases/download/RubyInstaller-$RubyVersion-$Rel/$Asset"
$Exe   = Join-Path $Tmp $Asset

Write-Host "Downloading $Url"
Invoke-WebRequest -Uri $Url -OutFile $Exe

if (Test-Path $Dest) { Remove-Item -Recurse -Force $Dest }
Write-Host "Installing RubyInstaller+DevKit -> $Dest"
# Inno Setup silent switches. /tasks= (empty) => do NOT touch system PATH or
# file associations; this stays a self-contained, relocatable dir tree.
Start-Process -FilePath $Exe -ArgumentList @('/verysilent','/norestart',"/dir=$Dest",'/tasks=') -Wait

# Ensure the MSYS2 MINGW dev toolchain is present so native gems compile.
& "$Dest\bin\ridk.cmd" install 3

& "$Dest\bin\ruby.exe" -v
& "$Dest\bin\gem.cmd" install bundler --no-document --force
if ($LASTEXITCODE -ne 0) { throw "gem install bundler failed (exit $LASTEXITCODE)" }
Write-Host "Bundled Ruby (Windows) ready."

Remove-Item -Recurse -Force $Tmp
