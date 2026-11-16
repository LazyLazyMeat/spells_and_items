[CmdletBinding()]
param(
    [string]$Path,
    [string]$OutputPath,
    [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
try {
    [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
    $OutputEncoding           = New-Object System.Text.UTF8Encoding($false)
} catch { }

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not $Path)       { $Path       = Join-Path $projectRoot 'source/spells.html' }
if (-not $OutputPath) { $OutputPath = Join-Path $projectRoot 'data/spells-index.json' }
if (-not [System.IO.Path]::IsPathRooted($Path))       { $Path       = Join-Path $projectRoot $Path }
if (-not [System.IO.Path]::IsPathRooted($OutputPath)) { $OutputPath = Join-Path $projectRoot $OutputPath }

try {
    function Initialize-HtmlAgilityPack {
        if ('HtmlAgilityPack.HtmlDocument' -as [type]) { return }
        $libDir = Join-Path $projectRoot 'lib'
        $hapDll = Join-Path $libDir 'HtmlAgilityPack.dll'
        if (-not (Test-Path $hapDll)) {
            Write-Host '[setup] First run: downloading HtmlAgilityPack...' -ForegroundColor Cyan
            if (-not (Test-Path $libDir)) { New-Item -ItemType Directory -Path $libDir | Out-Null }
            $nupkg   = Join-Path $libDir 'hap.zip'
            $extract = Join-Path $libDir 'hap'
            Invoke-WebRequest -Uri 'https://www.nuget.org/api/v2/package/HtmlAgilityPack/1.11.54' -OutFile $nupkg -UseBasicParsing
            if (Test-Path $extract) { Remove-Item $extract -Recurse -Force }
            Expand-Archive -Path $nupkg -DestinationPath $extract -Force
            Remove-Item $nupkg -Force
            $fw  = if ($PSVersionTable.PSEdition -eq 'Core') { 'netstandard2.0' } else { 'net45' }
            Copy-Item (Join-Path $extract "lib/$fw/HtmlAgilityPack.dll") $hapDll -Force
        }
        Add-Type -Path $hapDll
    }
    Initialize-HtmlAgilityPack

    function Get-SpellLinksFromHtml {
        param([string]$Html)
        $doc = New-Object HtmlAgilityPack.HtmlDocument
        $doc.LoadHtml($Html)
        $listUl = $doc.DocumentNode.SelectSingleNode("//ul[contains(concat(' ',normalize-space(@class),' '),' cards-list ')]")
        if ($null -eq $listUl) { throw 'ul.cards-list not found in HTML.' }
        $links = $listUl.SelectNodes(".//a[contains(concat(' ',normalize-space(@class),' '),' cards_list__item-wrapper ')]")
        if ($null -eq $links -or $links.Count -eq 0) { throw 'No spell links found inside ul.cards-list.' }
        foreach ($a in $links) {
            $href = $a.GetAttributeValue('href', '')
            if ([string]::IsNullOrWhiteSpace($href)) { continue }
            $slug = $null
            if ($href -match '/spells/(?<slug>[^/]+)/?$') { $slug = $Matches['slug'] }
            [pscustomobject]@{ slug = $slug; url = $href }
        }
    }

    if (-not (Test-Path -LiteralPath $Path)) {
    Write-Host ""
    Write-Host "[error] File not found:" -ForegroundColor Red
    Write-Host "  $Path"
    Write-Host ""
    Write-Host "Place the saved spell-list page at 'source/spells.html' in the project root,"
    Write-Host "or pass its path explicitly with -Path."
    return
}
$fullPath = (Resolve-Path -LiteralPath $Path).Path
    Write-Host "[parse] $fullPath"
    $html   = [System.IO.File]::ReadAllText($fullPath, [System.Text.Encoding]::UTF8)
    $spells = @(Get-SpellLinksFromHtml -Html $html)
    Write-Host "[ok] Found spells: $($spells.Count)" -ForegroundColor Green

    $outDir = Split-Path -Parent $OutputPath
    if ($outDir -and -not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
    $json = '[' + (($spells | ForEach-Object { $_ | ConvertTo-Json -Depth 5 }) -join ',') + ']'
    [System.IO.File]::WriteAllText($OutputPath, $json, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "[ok] $OutputPath" -ForegroundColor Green
} finally {
    if (-not $NoPause) { Read-Host 'Press Enter to exit' | Out-Null }
}