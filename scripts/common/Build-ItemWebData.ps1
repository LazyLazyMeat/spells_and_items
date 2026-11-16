#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$DataDir,
    [string]$OutputFile,
    [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
try {
    [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
    $OutputEncoding           = New-Object System.Text.UTF8Encoding($false)
} catch { }

# scripts/common/ -> scripts/ -> <root>
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not $DataDir)    { $DataDir    = Join-Path $projectRoot 'data/items' }
if (-not $OutputFile) { $OutputFile = Join-Path $projectRoot 'web/items.js' }
if (-not [System.IO.Path]::IsPathRooted($DataDir))    { $DataDir    = Join-Path $projectRoot $DataDir }
if (-not [System.IO.Path]::IsPathRooted($OutputFile)) { $OutputFile = Join-Path $projectRoot $OutputFile }

try {
    if (-not (Test-Path -LiteralPath $DataDir)) { throw "Data dir not found: $DataDir" }

    $files = @(Get-ChildItem -LiteralPath $DataDir -Filter '*.json' -File | Sort-Object Name)
    if ($files.Count -eq 0) { throw "No JSON files in $DataDir" }
    Write-Host "[index] $($files.Count) items"

    $items = foreach ($f in $files) {
        try {
            $raw = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8
            ConvertFrom-Json -InputObject $raw
        } catch {
            Write-Warning "  [skip] $($f.Name): $($_.Exception.Message)"
        }
    }

    $itemsArray = @($items)
    if ($itemsArray.Count -eq 0) { throw "All JSON files failed to parse" }
    Write-Host "[parsed] $($itemsArray.Count) items"

    $json = ConvertTo-Json -InputObject $itemsArray -Depth 20 -Compress

    $outDir = Split-Path -Parent $OutputFile
    if ($outDir -and -not (Test-Path -LiteralPath $outDir)) {
        New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    }
    $body = "window.ITEMS = $json;"
    [System.IO.File]::WriteAllText($OutputFile, $body, (New-Object System.Text.UTF8Encoding($false)))

    $sizeKb = [math]::Round((Get-Item -LiteralPath $OutputFile).Length / 1KB, 1)
    Write-Host "[ok] $OutputFile ($sizeKb KB)" -ForegroundColor Green
} finally {
    if (-not $NoPause) { Read-Host 'Press Enter to exit' | Out-Null }
}