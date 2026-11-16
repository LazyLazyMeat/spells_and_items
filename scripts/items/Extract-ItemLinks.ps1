#requires -Version 5.1
<#
.SYNOPSIS
    Extract item links from dnd.su items list page(s) into items-index.json.

.DESCRIPTION
    Parses one or more HTML files of the /items/ list page (pagination supported
    via folder input) and writes data/items-index.json in the same format as
    data/spells-index.json.

.PARAMETER InputPath
    Path to a single HTML file or a folder of HTML files.
    Default: <projectRoot>/source/items.html

.PARAMETER OutputFile
    Path to output JSON. Default: <projectRoot>/data/items-index.json

.PARAMETER LibPath
    Path to HtmlAgilityPack.dll. Default: <projectRoot>/lib/HtmlAgilityPack.dll

.EXAMPLE
    .\Extract-ItemLinks.ps1 -NoPause

.EXAMPLE
    .\Extract-ItemLinks.ps1 -InputPath .\source\items -NoPause
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$false, Position=0)]
    [string]$InputPath,
    [string]$OutputFile,
    [string]$LibPath,
    [switch]$NoPause
)

$ErrorActionPreference = 'Stop'

# ---- Resolve paths ----
$scriptDir   = $PSScriptRoot
$projectRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)

if (-not $OutputFile) { $OutputFile = Join-Path $projectRoot 'data/items-index.json' }
if (-not $LibPath)    { $LibPath    = Join-Path $projectRoot 'lib/HtmlAgilityPack.dll' }
if (-not $InputPath)  { $InputPath  = Join-Path $projectRoot 'source/items.html' }

function Stop-WithMessage {
    param([string]$Message)
    Write-Error $Message
    if (-not $NoPause) { Read-Host 'Press Enter to exit' | Out-Null }
    exit 1
}

if (-not (Test-Path $LibPath))   { Stop-WithMessage "HtmlAgilityPack not found: $LibPath" }
if (-not (Test-Path $InputPath)) { Stop-WithMessage "Input not found: $InputPath" }

Add-Type -Path $LibPath

# ---- Collect input files ----
$item  = Get-Item $InputPath
$files = if ($item.PSIsContainer) {
    @(Get-ChildItem -Path $InputPath -Filter '*.html' -File | Sort-Object Name)
} else {
    @($item)
}

if ($files.Count -eq 0) {
    Stop-WithMessage "No .html files found in: $InputPath"
}

# ---- Extract ----
$urlPattern = '^https?://dnd\.su/items/([^/?#]+)/?$'
$seen    = @{}
$entries = New-Object System.Collections.Generic.List[object]

foreach ($f in $files) {
    Write-Host "==> $($f.Name)"
    $html = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8)
    $doc = New-Object HtmlAgilityPack.HtmlDocument
    $doc.LoadHtml($html)

    $links = $doc.DocumentNode.SelectNodes('//a[contains(@class,"list-item-wrapper")]')
    if (-not $links) {
        Write-Warning "    no list-item-wrapper links found"
        continue
    }

    $added = 0
    foreach ($a in $links) {
        $href = $a.GetAttributeValue('href', '').Trim()
        if (-not $href) { continue }

        $m = [regex]::Match($href, $urlPattern, 'IgnoreCase')
        if (-not $m.Success) { continue }

        $slug = $m.Groups[1].Value
        if ($seen.ContainsKey($slug)) { continue }
        $seen[$slug] = $true

        $entries.Add([PSCustomObject]@{
            slug = $slug
            url  = 'https://dnd.su/items/' + $slug + '/'
        }) | Out-Null
        $added++
    }
    Write-Host ("    +{0} new (total {1})" -f $added, $entries.Count)
}

if ($entries.Count -eq 0) {
    Stop-WithMessage 'No item links extracted'
}

# Sort by numeric id prefix, e.g. "2337-abracadabrus" -> 2337
$sorted = $entries | Sort-Object {
    $prefix = ($_.slug -split '-')[0]
    $n = 0
    if ([int]::TryParse($prefix, [ref]$n)) { $n } else { [int]::MaxValue }
}

# ---- Write ----
$outDir = Split-Path -Parent $OutputFile
if ($outDir -and -not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}

$json = ConvertTo-Json -InputObject @($sorted) -Depth 5
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($OutputFile, $json, $utf8NoBom)

Write-Host ''
Write-Host "Wrote $($sorted.Count) entries -> $OutputFile"

if (-not $NoPause) { Read-Host 'Press Enter to exit' | Out-Null }