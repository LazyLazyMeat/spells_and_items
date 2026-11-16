[CmdletBinding()]
param(
    [string]$IndexPath,
    [string]$OutputDir,
    [int]$Count        = 0,
    [int]$DelayMs      = 1500,
    [int]$JitterMs     = 500,
    [bool]$WithLevel   = $true,
    [switch]$Force,
    [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
try {
    [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
    $OutputEncoding           = New-Object System.Text.UTF8Encoding($false)
} catch { }

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not $IndexPath) { $IndexPath = Join-Path $projectRoot 'data/spells-index.json' }
if (-not $OutputDir) { $OutputDir = Join-Path $projectRoot 'source/spells' }
if (-not [System.IO.Path]::IsPathRooted($IndexPath)) { $IndexPath = Join-Path $projectRoot $IndexPath }
if (-not [System.IO.Path]::IsPathRooted($OutputDir)) { $OutputDir = Join-Path $projectRoot $OutputDir }

$childScript = Join-Path $PSScriptRoot 'Save-SpellPage.ps1'

try {
    if (-not (Test-Path $IndexPath)) { throw "Index not found: $IndexPath" }
    if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }
    if (-not (Test-Path $childScript)) { throw "Child script not found: $childScript" }

    $indexRaw = Get-Content -LiteralPath $IndexPath -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($indexRaw)) { throw "Index is empty: $IndexPath" }
    $parsed = ConvertFrom-Json -InputObject $indexRaw
    $spells = @($parsed)
    if ($spells.Count -eq 1 -and $spells[0] -is [System.Array]) { $spells = $spells[0] }
    if ($null -eq $spells -or $spells.Count -eq 0) { throw "Index parsed to zero entries: $IndexPath" }

    Write-Host "[index] $($spells.Count) spells loaded"
    $total = $spells.Count
    if ($Count -gt 0 -and $Count -lt $total) {
        $spells = @($spells | Select-Object -First $Count)
        $total  = $spells.Count
        Write-Host "[index] limited to first $total"
    }
    Write-Host "[target] $OutputDir"
    Write-Host "[delay ] base=${DelayMs}ms jitter=+/-${JitterMs}ms  WithLevel=$WithLevel"

    $stats = [pscustomobject]@{ ok=0; skip=0; fail=0; errors=New-Object System.Collections.Generic.List[object] }
    $startedAt = Get-Date
    $i = 0

    foreach ($spell in $spells) {
        $i++
        if (-not $spell.slug) {
            $stats.fail++; $stats.errors.Add([pscustomobject]@{ slug=$null; url=$spell.url; error='no slug' })
            Write-Warning "[$i/$total] missing slug"; continue
        }
        Write-Host "[$i/$total] $($spell.slug)" -ForegroundColor Cyan

        if (-not $Force) {
            $existing = Get-ChildItem -LiteralPath $OutputDir -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like "*$($spell.slug).html" } | Select-Object -First 1
            if ($existing) { Write-Host "  [skip] $($existing.Name)" -ForegroundColor Yellow; $stats.skip++; continue }
        }

        try {
            $null = & $childScript -Spell $spell.slug -OutputDir $OutputDir -WithLevel:$WithLevel -Force:$Force -NoPause -ErrorAction Stop
            $stats.ok++
        } catch {
            $stats.fail++
            $stats.errors.Add([pscustomobject]@{ slug=$spell.slug; url=$spell.url; error=$_.Exception.Message })
            Write-Warning "  [fail] $($_.Exception.Message)"
        }

        if ($i -lt $total) {
            $delay = $DelayMs + (Get-Random -Minimum (-$JitterMs) -Maximum ($JitterMs + 1))
            if ($delay -lt 100) { $delay = 100 }
            Start-Sleep -Milliseconds $delay
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
        foreach ($e in $stats.errors) { Write-Host ("   - {0} :: {1}" -f $e.slug, $e.error) }
    }
    Write-Host "===============================" -ForegroundColor Cyan
} finally {
    if (-not $NoPause) { Read-Host 'Press Enter to exit' | Out-Null }
}