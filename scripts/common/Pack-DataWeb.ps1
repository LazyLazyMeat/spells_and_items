#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$WebDir,
    [string]$OutputZip,
    [string]$FolderName = 'spells-and-items-web',
    [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
try {
    [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
    $OutputEncoding           = New-Object System.Text.UTF8Encoding($false)
} catch { }

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not $WebDir)    { $WebDir    = Join-Path $projectRoot 'web' }
if (-not $OutputZip) { $OutputZip = Join-Path $projectRoot 'dist/spells-and-items-web.zip' }
if (-not [System.IO.Path]::IsPathRooted($WebDir))    { $WebDir    = Join-Path $projectRoot $WebDir }
if (-not [System.IO.Path]::IsPathRooted($OutputZip)) { $OutputZip = Join-Path $projectRoot $OutputZip }

try {
    if (-not (Test-Path -LiteralPath $WebDir)) { throw "Web dir not found: $WebDir" }

    # Required files (both data bundles included)
    $requiredFiles = @('index.html', 'style.css', 'app.js', 'spells.js', 'items.js')
    $missing = @()
    foreach ($name in $requiredFiles) {
        if (-not (Test-Path -LiteralPath (Join-Path $WebDir $name))) { $missing += $name }
    }
    if ($missing.Count -gt 0) {
        throw "Missing required files in web/: $($missing -join ', ')"
    }

    # Stale check: spells.js vs data/spells/*.json
    $spellsJs      = Get-Item -LiteralPath (Join-Path $WebDir 'spells.js')
    $spellsDataDir = Join-Path $projectRoot 'data/spells'
    if (Test-Path -LiteralPath $spellsDataDir) {
        $newer = Get-ChildItem -LiteralPath $spellsDataDir -Filter '*.json' -File |
            Where-Object { $_.LastWriteTime -gt $spellsJs.LastWriteTime } | Select-Object -First 1
        if ($newer) {
            Write-Warning "[stale] spells.js older than $($newer.Name). Run Build-SpellWebData first."
        }
    }

    # Stale check: items.js vs data/items/*.json
    $itemsJs      = Get-Item -LiteralPath (Join-Path $WebDir 'items.js')
    $itemsDataDir = Join-Path $projectRoot 'data/items'
    if (Test-Path -LiteralPath $itemsDataDir) {
        $newer = Get-ChildItem -LiteralPath $itemsDataDir -Filter '*.json' -File |
            Where-Object { $_.LastWriteTime -gt $itemsJs.LastWriteTime } | Select-Object -First 1
        if ($newer) {
            Write-Warning "[stale] items.js older than $($newer.Name). Run Build-ItemWebData first."
        }
    }

    # Stage into a temp dir, then compress. Pack the entire web/ folder recursively.
    $stagingRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("dataweb-stage-" + [guid]::NewGuid().ToString('N'))
    $stagingPkg  = Join-Path $stagingRoot $FolderName
    try {
        Copy-Item -LiteralPath $WebDir -Destination $stagingPkg -Recurse -Force

        $outDir = Split-Path -Parent $OutputZip
        if ($outDir -and -not (Test-Path -LiteralPath $outDir)) {
            New-Item -ItemType Directory -Path $outDir -Force | Out-Null
        }
        if (Test-Path -LiteralPath $OutputZip) { Remove-Item -LiteralPath $OutputZip -Force }
        Compress-Archive -Path $stagingPkg -DestinationPath $OutputZip -CompressionLevel Optimal
    } finally {
        if (Test-Path -LiteralPath $stagingRoot) {
            Remove-Item -LiteralPath $stagingRoot -Recurse -Force
        }
    }

    $zipSizeKb = [math]::Round((Get-Item -LiteralPath $OutputZip).Length / 1KB, 1)
    Write-Host "[ok] $OutputZip ($zipSizeKb KB)" -ForegroundColor Green

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($OutputZip)
    try {
        Write-Host ""
        Write-Host "Contents:" -ForegroundColor Cyan
        foreach ($e in $zip.Entries) {
            Write-Host ("  {0,-60} {1,8} KB" -f $e.FullName, [math]::Round($e.Length / 1KB, 1))
        }
    } finally { $zip.Dispose() }
} finally {
    if (-not $NoPause) { Read-Host 'Press Enter to exit' | Out-Null }
}