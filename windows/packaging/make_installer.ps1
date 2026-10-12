# Builds the app and packs it into "dist\Usage Monitor Setup <version>.exe",
# plus a zip of the same files. Needs Flutter and Inno Setup 6
# (winget install JRSoftware.InnoSetup).
$ErrorActionPreference = 'Stop'
Set-Location (Resolve-Path "$PSScriptRoot\..\..")

$version = (Select-String -Path pubspec.yaml -Pattern '^version:\s*([^+\s]+)').Matches[0].Groups[1].Value

flutter build windows --release
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# Flutter builds for the machine's own architecture.
$arm = $env:PROCESSOR_ARCHITECTURE -eq 'ARM64'
$build = Join-Path $PWD "build\windows\$(if ($arm) { 'arm64' } else { 'x64' })\runner\Release"

$iscc = (Get-Command iscc -ErrorAction SilentlyContinue).Source
if (-not $iscc) {
  $iscc = @(
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
  ) | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $iscc) { throw 'Inno Setup 6 not found. Install it with: winget install JRSoftware.InnoSetup' }

$suffix = if ($arm) { ' (arm64)' } else { '' }
& $iscc /Q "/DAppVersion=$version" "/DBuildDir=$build" "/DArch=$(if ($arm) { 'arm64' } else { 'x64compatible' })" "/DSuffix=$suffix" windows\packaging\installer.iss
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Compress-Archive -Path "$build\*" -DestinationPath "dist\Usage Monitor $version$suffix.zip" -Force

Get-ChildItem dist -Filter "Usage Monitor*$version*" | ForEach-Object { $_.FullName }
