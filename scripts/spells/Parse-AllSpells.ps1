[CmdletBinding()]
param(
    [string]$SourceDir,
    [string]$OutputDir,
    [int]$Count     = 0,
    [string]$Filter = '*.html',
    [switch]$Force,
    [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
try {
    [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
    $OutputEncoding           = New-Object System.Text.UTF8Encoding($false)
} catch { }

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not $SourceDir) { $SourceDir = Join-Path $projectRoot 'source/spells' }
if (-not $OutputDir) { $OutputDir = Join-Path $projectRoot 'data/spells' }
if (-not [System.IO.Path]::IsPathRooted($SourceDir)) { $SourceDir = Join-Path $projectRoot $SourceDir }
if (-not [System.IO.Path]::IsPathRooted($OutputDir)) { $OutputDir = Join-Path $projectRoot $OutputDir }

$childScript = Join-Path $PSScriptRoot 'Parse-Spell.ps1'

function Get-SlugFromFileName([string]$name) {
    $s = $name -replace '\.html?$', ''
    $s = $s -replace '^\[\d+\]', ''
    return $s
}

try {
    if (-not (Test-Path $SourceDir)) { throw "Source dir not found: $SourceDir" }
    if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }
    if (-not (Test-Path $childScript)) { throw "Child script not found: $childScript" }

    $files = @(Get-ChildItem -LiteralPath $SourceDir -File -Filter $Filter | Sort-Object Name)
    if ($files.Count -eq 0) { throw "No files matching '$Filter' in $SourceDir" }
    Write-Host "[source] $SourceDir"
    Write-Host "[target] $OutputDir"
    Write-Host "[files ] $($files.Count)"

    $total = $files.Count
    if ($Count -gt 0 -and $Count -lt $total) {
        $files = @($files | Select-Object -First $Count)
        $total = $files.Count
        Write-Host "[files ] limited to first $total"
    }

    $stats = [pscustomobject]@{ ok=0; skip=0; fail=0; errors=New-Object System.Collections.Generic.List[object] }
    $startedAt = Get-Date
    $i = 0

    foreach ($file in $files) {
        $i++
        $slug = Get-SlugFromFileName $file.Name
        Write-Host "[$i/$total] $($file.Name)"
        if ([string]::IsNullOrWhiteSpace($slug)) {
            $stats.fail++; $stats.errors.Add([pscustomobject]@{ file=$file.Name; error='empty slug' })
            Write-Warning "  [fail] empty slug"; continue
        }
        if (-not $Force) {
            $existing = Get-ChildItem -LiteralPath $OutputDir -File -Filter "*$slug.json" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($existing) { Write-Host "  [skip] $($existing.Name)" -ForegroundColor Yellow; $stats.skip++; continue }
        }
        try {
            $null = & $childScript -Path $file.FullName -NoPause -ErrorAction Stop
            $stats.ok++
        } catch {
            $stats.fail++
            $stats.errors.Add([pscustomobject]@{ file=$file.Name; slug=$slug; error=$_.Exception.Message })
            Write-Warning "  [fail] $($_.Exception.Message)"
        }
    }

    $elapsed = (Get-Date) - $startedAt
    Write-Host ""
    Write-Host "=========== SUMMARY ===========" -ForegroundColor Cyan
    Write-Host ("  ok    : {0}" -f $stats.ok)    -ForegroundColor Green
    Write-Host ("  skip  : {0}" -f $stats.skip)  -ForegroundColor Yellow
    Write-Host ("  fail  : {0}" -f $stats.fail)  -ForegroundColor Red
    Write-Host ("  total : {0}" -f $i)
    Write-Host ("  time  : {0:hh\:mm\:ss}" -f $elapsed)
    if ($stats.errors.Count -gt 0) {
        Write-Host ""
        Write-Host "  errors:" -ForegroundColor Red
        foreach ($e in $stats.errors) { Write-Host ("   - {0} :: {1}" -f $e.file, $e.error) }
    }
    Write-Host "===============================" -ForegroundColor Cyan
} finally {
    if (-not $NoPause) { Read-Host 'Press Enter to exit' | Out-Null }
}