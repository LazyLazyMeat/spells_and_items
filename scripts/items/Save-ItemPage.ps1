#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$Item,
    [string]$OutputDir,
    [string]$ConfigPath,
    [bool]$WithRarity = $true,
    [switch]$Force,
    [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
try {
    [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
    $OutputEncoding           = New-Object System.Text.UTF8Encoding($false)
} catch { }

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not $OutputDir)  { $OutputDir  = Join-Path $projectRoot 'source/items' }
if (-not $ConfigPath) { $ConfigPath = Join-Path $PSScriptRoot 'items-config.json' }
if (-not [System.IO.Path]::IsPathRooted($OutputDir)) { $OutputDir = Join-Path $projectRoot $OutputDir }

# ---- Load rarity config (only needed if WithRarity) ----
$rarityMap      = @{}
$noRarityMarker = $null
if ($WithRarity) {
    if (-not (Test-Path $ConfigPath)) { throw "Config not found: $ConfigPath" }
    $config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $noRarityMarker = $config.no_rarity_marker
    foreach ($prop in $config.rarities.PSObject.Properties) {
        foreach ($form in $prop.Value) {
            $rarityMap[$form] = $prop.Name
        }
    }
}

function Get-RarityKeyFromHtml {
    param([string]$Content)

    # 1) og:description Ч genitive form, gender-stable, primary source
    $meta = [regex]::Match($Content, '<meta[^>]+property="og:description"[^>]*>')
    if ($meta.Success) {
        $c = [regex]::Match($meta.Value, 'content="([^"]*)"')
        if ($c.Success) {
            $desc = [System.Net.WebUtility]::HtmlDecode($c.Groups[1].Value)
            $desc = $desc -replace '\u00A0', ' '
            $desc = $desc -replace '\s+', ' '

            if ($noRarityMarker -and $desc.IndexOf($noRarityMarker, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                return 'none'
            }

            $forms = $rarityMap.Keys | Sort-Object Length -Descending
            foreach ($form in $forms) {
                if ($desc -match ('\b' + [regex]::Escape($form) + '\s+качества\b')) {
                    return $rarityMap[$form]
                }
            }
        }
    }

    # 2) Fallback: size-type-alignment
    $m = [regex]::Match($Content, 'class="size-type-alignment"[^>]*>(?<val>[^<]+)<')
    if ($m.Success) {
        $val = [System.Net.WebUtility]::HtmlDecode($m.Groups['val'].Value).Trim()
        $val = $val -replace '\s*\([^)]*\)\s*$', ''
        $comma = $val.IndexOf(',')
        if ($comma -ge 0) {
            $r = $val.Substring($comma + 1).Trim()
            if ($rarityMap.ContainsKey($r)) { return $rarityMap[$r] }
            if ($r -match 'варьиру') { return 'varies' }
        }
    }

    return 'none'
}

try {
    if ([string]::IsNullOrWhiteSpace($Item)) {
        Write-Host 'Usage: Save-ItemPage.ps1 <slug or URL> [-Force] [-NoPause]' -ForegroundColor Yellow
        Write-Host 'Example: Save-ItemPage.ps1 397-cast-off-armor'
        return
    }

    $url = $Item.Trim()
    if ($url -notmatch '^https?://') { $url = 'https://dnd.su/items/' + $url.Trim('/') + '/' }
    Write-Host "[fetch] $url"

    if ($url -notmatch '/items/(?<slug>[^/]+)/?$') { throw "Cannot extract slug from URL: $url" }
    $slug = $Matches['slug']
    if ($slug -notmatch '^\d+-[a-z0-9][a-z0-9-]*$') {
        throw "Slug has no numeric prefix (expected like 24-wand-of-secrets): $slug"
    }

    if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }

    # Already-saved check (prefix may or may not be present, so wildcard)
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
            if (Test-Path -LiteralPath $tmpPath) { Remove-Item -LiteralPath $tmpPath -Force }
            Invoke-WebRequest -Uri $url -UserAgent $userAgent -UseBasicParsing -TimeoutSec 30 -OutFile $tmpPath
            $content = [System.IO.File]::ReadAllText($tmpPath, [System.Text.Encoding]::UTF8)
            if ($content -match 'card__category-items') { break }
            Write-Warning "Attempt $attempt/$maxAttempts : missing card__category-items, retrying in 5s"
            Start-Sleep -Seconds 5
        } catch {
            Write-Warning "Attempt $attempt/$maxAttempts : $_"
            Start-Sleep -Seconds 5
        }
    }

    if ($null -eq $content -or $content -notmatch 'card__category-items') {
        if (Test-Path -LiteralPath $tmpPath) {
            $debugPath = Join-Path $OutputDir "$slug.debug.html"
            Move-Item -LiteralPath $tmpPath -Destination $debugPath -Force
            Write-Host "Debug copy saved: $debugPath"
        }
        throw "Giving up after $maxAttempts attempts: $url"
    }

    # ---- Build filename ----
    $prefix = ''
    if ($WithRarity) {
        $rk = Get-RarityKeyFromHtml -Content $content
        if (-not $rk) { $rk = 'none' }
        $prefix = "[$rk]"
    }
    $fileName = "$prefix$slug.html"
    $outPath  = Join-Path $OutputDir $fileName

    if ((Test-Path -LiteralPath $outPath) -and $Force) { Remove-Item -LiteralPath $outPath -Force }
    Move-Item -LiteralPath $tmpPath -Destination $outPath -Force

    $size = (Get-Item -LiteralPath $outPath).Length
    Write-Host "[ok] $outPath ($size bytes)" -ForegroundColor Green
} finally {
    if (-not $NoPause) { Read-Host 'Press Enter to exit' | Out-Null }
}