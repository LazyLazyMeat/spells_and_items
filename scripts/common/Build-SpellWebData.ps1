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

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not $DataDir)    { $DataDir    = Join-Path $projectRoot 'data/spells' }
if (-not $OutputFile) { $OutputFile = Join-Path $projectRoot 'web/spells.js' }
if (-not [System.IO.Path]::IsPathRooted($DataDir))    { $DataDir    = Join-Path $projectRoot $DataDir }
if (-not [System.IO.Path]::IsPathRooted($OutputFile)) { $OutputFile = Join-Path $projectRoot $OutputFile }

try {
    $files = @(Get-ChildItem -LiteralPath $DataDir -Filter '*.json' -File | Sort-Object Name)
    if ($files.Count -eq 0) { throw "No JSON files in $DataDir" }
    Write-Host "[index] $($files.Count) spells"

    $items = foreach ($f in $files) {
        $raw = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8
        ConvertFrom-Json -InputObject $raw
    }

    $json = ConvertTo-Json -InputObject @($items) -Depth 20 -Compress
    $outDir = Split-Path -Parent $OutputFile
    if ($outDir -and -not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
    $body = "window.SPELLS = $json;"
    [System.IO.File]::WriteAllText($OutputFile, $body, (New-Object System.Text.UTF8Encoding($false)))

    $sizeKb = [math]::Round((Get-Item -LiteralPath $OutputFile).Length / 1KB, 1)
    Write-Host "[ok] $OutputFile ($sizeKb KB)" -ForegroundColor Green
} finally {
    if (-not $NoPause) { Read-Host 'Press Enter to exit' | Out-Null }
}