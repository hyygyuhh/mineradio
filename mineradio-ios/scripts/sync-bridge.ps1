$ErrorActionPreference = "Stop"
$iosRoot = Split-Path -Parent $MyInvocation.MyCommand.Path | Split-Path -Parent
$repoRoot = Split-Path -Parent $iosRoot
$bridgeSrc = Join-Path $repoRoot "Mineradio-Bridge-1.4.1"
$androidInject = Join-Path $repoRoot "mineradio-android\app\src\main\assets\host\inject.js"
$iconSrc = Join-Path $repoRoot "assets\mr-icon-1024.png"

if (-not (Test-Path $bridgeSrc)) { throw "Bridge source missing: $bridgeSrc" }

# --- Target projects to sync into ---
$projects = @(
  @{ Name = "MineRadioWeb"; BridgeDst = Join-Path $iosRoot "MineRadioWeb\Resources\bridge"; HostDst = Join-Path $iosRoot "MineRadioWeb\Resources\host"; IconDst = Join-Path $iosRoot "MineRadioWeb\Assets.xcassets\AppIcon.appiconset\mr-icon-1024.png"; OverwriteInject = $false },
  @{ Name = "Mineradio";     BridgeDst = Join-Path $iosRoot "Mineradio\Mineradio\Resources\bridge"; HostDst = Join-Path $iosRoot "Mineradio\Mineradio\Resources\host"; IconDst = $null; OverwriteInject = $true }
)

foreach ($proj in $projects) {
  $bridgeDst = $proj.BridgeDst
  $hostDst = $proj.HostDst
  Write-Host "[sync-bridge] $($proj.Name): syncing bridge -> $bridgeDst"

  if (Test-Path $bridgeDst) { Remove-Item $bridgeDst -Recurse -Force }
  New-Item -ItemType Directory -Path $bridgeDst -Force | Out-Null
  Copy-Item "$bridgeSrc\*" $bridgeDst -Recurse -Force
  Remove-Item "$bridgeDst\README.md" -Force -ErrorAction SilentlyContinue
  Remove-Item "$bridgeDst\icons\README.md" -Force -ErrorAction SilentlyContinue

  New-Item -ItemType Directory -Path $hostDst -Force | Out-Null

  if ($proj.OverwriteInject -and (Test-Path $androidInject)) {
    Copy-Item $androidInject (Join-Path $hostDst "inject.js") -Force
    $injectPath = Join-Path $hostDst "inject.js"
    $inject = Get-Content $injectPath -Raw -Encoding UTF8
    $inject = $inject -replace "mineradio-android", "mineradio-ios"
    $inject = $inject -replace "routes API calls through Electron", "routes API calls through iOS host"
    Set-Content -Path $injectPath -Value $inject -Encoding UTF8 -NoNewline
  } else {
    Write-Host "[sync-bridge] $($proj.Name): keeping iOS-specific host/inject.js"
  }

  if (-not (Test-Path (Join-Path $hostDst "runner.html"))) {
    Write-Warning "$($proj.Name): runner.html missing — keep the iOS host/runner.html in repo"
  }

  if ($proj.IconDst -and (Test-Path $iconSrc)) {
    $iconDir = Split-Path -Parent $proj.IconDst
    New-Item -ItemType Directory -Path $iconDir -Force | Out-Null
    Copy-Item $iconSrc $proj.IconDst -Force
    Write-Host "[sync-bridge] $($proj.Name): copied icon -> $($proj.IconDst)"
  }

  Write-Host "[sync-bridge] $($proj.Name): done. Host assets -> $hostDst"
}
