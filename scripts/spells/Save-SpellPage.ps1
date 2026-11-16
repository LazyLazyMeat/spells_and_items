[CmdletBinding()]
param(
    [string]$Spell,
    [string]$OutputDir,
    [bool]$WithLevel = $true,
    [switch]$Force,
    [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
try {
    [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
    $OutputEncoding           = New-Object System.Text.UTF8Encoding($false)
} catch { }

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not $OutputDir) { $OutputDir = Join-Path $projectRoot 'source/spells' }
if (-not [System.IO.Path]::IsPathRooted($OutputDir)) { $OutputDir = Join-Path $projectRoot $OutputDir }

try {
    if ([string]::IsNullOrWhiteSpace($Spell)) {
        Write-Host 'Usage: Save-SpellPage.bat <slug or URL> [-Force]' -ForegroundColor Yellow
        Write-Host 'Example: Save-SpellPage.bat 333-create-or-destroy-water'
        return
    }

    $url = $Spell.Trim()
    if ($url -notmatch '^https?://') { $url = 'https://dnd.su/spells/' + $url.Trim('/') + '/' }
    Write-Host "[fetch] $url"

    if ($url -notmatch '/spells/(?<slug>[^/]+)/?$') { throw "Cannot extract slug from URL: $url" }
    $slug = $Matches['slug']

    if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }

    if (-not $Force) {
        $existing = Get-ChildItem -LiteralPath $OutputDir -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "*$slug.html" } | Select-Object -First 1
        if ($existing) {
            Write-Host "[skip] already exists: $($existing.FullName)" -ForegroundColor Yellow
            return
        }
    }

    $tmpPath   = Join-Path $OutputDir ("__tmp__$slug.html")
    $userAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36'

    $maxAttempts = 3
    $attempt     = 0
    $content     = $null
    while ($attempt -lt $maxAttempts) {
        $attempt++
        try {
            Invoke-WebRequest -Uri $url -UserAgent $userAgent -UseBasicParsing -TimeoutSec 30 -OutFile $tmpPath
            $content = [System.IO.File]::ReadAllText($tmpPath, [System.Text.Encoding]::UTF8)
            if ($content -match 'card__category-spells') { break }
            Write-Warning "Attempt $attempt/$maxAttempts : missing card__category-spells, retrying in 5s"
            Start-Sleep -Seconds 5
        } catch {
            Write-Warning "Attempt $attempt/$maxAttempts : $_"
            Start-Sleep -Seconds 5
        }
    }
    if ($null -eq $content -or $content -notmatch 'card__category-spells') {
        if (Test-Path $tmpPath) { Remove-Item -LiteralPath $tmpPath -Force }
        throw "Giving up after $maxAttempts attempts: $url"
    }

    $fileName = "$slug.html"
    if ($WithLevel) {
        $levelTag = '?'
        if ($content -match 'size-type-alignment[^>]*>\s*(?<val>[^<]+)<') {
            $val = $Matches['val'].Trim()
            if ($val -match '^(?<tok>\d+|[^\d,\s]+)') {
                $tok = $Matches['tok']
                $n   = 0
                if ([int]::TryParse($tok, [ref]$n)) { $levelTag = [string]$n } else { $levelTag = '0' }
            }
        }
        $fileName = "[$levelTag]$slug.html"
    }
    $outPath = Join-Path $OutputDir $fileName
    if ((Test-Path -LiteralPath $outPath) -and $Force) { Remove-Item -LiteralPath $outPath -Force }
    Move-Item -LiteralPath $tmpPath -Destination $outPath -Force
    Write-Host "[ok] $outPath" -ForegroundColor Green
} finally {
    if (-not $NoPause) { Read-Host 'Press Enter to exit' | Out-Null }
}