# Cross-platform HTTP load testing CLI: a modern ab/wrk alternative with machine-readable reports for CI/CD
# Install cryload from GitHub Releases (Windows).
#
# Usage (PowerShell):
#   iwr -useb https://raw.githubusercontent.com/sdogruyol/cryload/master/scripts/install.ps1 | iex
#   $env:VERSION = "v3.0.0"; iwr ... | iex
#
# Parameters / environment:
#   -Version    Release tag (e.g. v3.0.0 or 3.0.0); default: latest release
#   -InstallDir Destination folder (default: %USERPROFILE%\.local\bin)
#   -Repo       GitHub repo (default: sdogruyol/cryload)

#Requires -Version 5.1
param(
    [string] $Version = "",
    [string] $InstallDir = "",
    [string] $Repo = "sdogruyol/cryload"
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrEmpty($Version) -and $env:VERSION) {
    $Version = $env:VERSION
}

if ([string]::IsNullOrEmpty($InstallDir) -and $env:INSTALL_DIR) {
    $InstallDir = $env:INSTALL_DIR
}

if (-not $InstallDir) {
    $InstallDir = Join-Path $env:USERPROFILE ".local\bin"
}

if (-not $Version) {
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest"
    $Tag = $release.tag_name
} else {
    $Tag = if ($Version -match '^v') { $Version } else { "v$Version" }
}

$base = "https://github.com/$Repo/releases/download/$Tag"
$asset = "cryload-windows.exe"
$sumAsset = "$asset.sha256"

$tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("cryload-install-" + [Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $tmpDir | Out-Null

try {
    $binPath = Join-Path $tmpDir $asset
    $sumPath = Join-Path $tmpDir $sumAsset
    Invoke-WebRequest -Uri "$base/$asset" -OutFile $binPath -UseBasicParsing
    Invoke-WebRequest -Uri "$base/$sumAsset" -OutFile $sumPath -UseBasicParsing

    $sumLine = (Get-Content $sumPath -Raw).Trim()
    $expected = ($sumLine -split '\s+')[0].ToLower()
    $actual = (Get-FileHash -Algorithm SHA256 $binPath).Hash.ToLower()
    if ($expected -ne $actual) {
        throw "SHA256 mismatch: expected $expected, got $actual"
    }

    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    $dest = Join-Path $InstallDir "cryload.exe"
    Move-Item -Force $binPath $dest

    Write-Host "Installed cryload $Tag -> $dest"
    if (-not ($env:Path -split ';' -contains $InstallDir)) {
        Write-Host ""
        Write-Host "Add to your user PATH (example):"
        Write-Host "  [Environment]::SetEnvironmentVariable('Path', `"$InstallDir;`$env:Path`", 'User')"
    }
    Write-Host ""
    Write-Host "Try: cryload --help"
}
finally {
    Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue
}
