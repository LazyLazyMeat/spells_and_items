#requires -Version 5.1
<#
.SYNOPSIS
    Parse dnd.su magic item HTML into JSON.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$false, Position=0)]
    [string]$InputPath,
    [string]$OutputDir,
    [string]$LibPath,
    [string]$ConfigPath,
    [bool]$WithRarity = $true,
    [switch]$NoPause
)

$ErrorActionPreference = 'Stop'

# ---- Resolve paths ----
$scriptDir   = $PSScriptRoot
$projectRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)

if (-not $OutputDir)  { $OutputDir  = Join-Path $projectRoot 'data/items' }
if (-not $LibPath)    { $LibPath    = Join-Path $projectRoot 'lib/HtmlAgilityPack.dll' }
if (-not $ConfigPath) { $ConfigPath = Join-Path $scriptDir 'items-config.json' }

function Stop-WithMessage {
    param([string]$Message)
    Write-Error $Message
    if (-not $NoPause) { Read-Host 'Press Enter to exit' | Out-Null }
    exit 1
}

if (-not (Test-Path -LiteralPath $LibPath))    { Stop-WithMessage "HtmlAgilityPack not found: $LibPath" }
if (-not (Test-Path -LiteralPath $ConfigPath)) { Stop-WithMessage "Config not found: $ConfigPath" }

Add-Type -Path $LibPath
$config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json

# ---- Build rarity form -> key map (all genders + genitive) ----
$rarityMap = @{}
foreach ($prop in $config.rarities.PSObject.Properties) {
    $key = $prop.Name
    foreach ($form in $prop.Value) {
        $rarityMap[$form] = $key
    }
}

$variantPat  = '^\+(\d+)\s+(.+)$'
$protoMarker = [char]0x00A7

# ---- Helpers ----

function New-DeterministicGuid {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [string]$Namespace = '6ba7b810-9dad-11d1-80b4-00c04fd430c8'
    )
    $nsBytes = [guid]::Parse($Namespace).ToByteArray()
    $nsBig = [byte[]]@(
        $nsBytes[3], $nsBytes[2], $nsBytes[1], $nsBytes[0],
        $nsBytes[5], $nsBytes[4],
        $nsBytes[7], $nsBytes[6],
        $nsBytes[8], $nsBytes[9], $nsBytes[10], $nsBytes[11],
        $nsBytes[12], $nsBytes[13], $nsBytes[14], $nsBytes[15]
    )
    $nameBytes = [System.Text.Encoding]::UTF8.GetBytes($Name)

    $buf = New-Object byte[] ($nsBig.Length + $nameBytes.Length)
    [Array]::Copy($nsBig,     0, $buf, 0,             $nsBig.Length)
    [Array]::Copy($nameBytes, 0, $buf, $nsBig.Length, $nameBytes.Length)

    $sha1 = [System.Security.Cryptography.SHA1]::Create()
    try   { $hash = $sha1.ComputeHash($buf) }
    finally { $sha1.Dispose() }

    $b = New-Object byte[] 16
    [Array]::Copy($hash, 0, $b, 0, 16)
    $b[6] = ($b[6] -band 0x0F) -bor 0x50
    $b[8] = ($b[8] -band 0x3F) -bor 0x80

    $mixed = [byte[]]@(
        $b[3], $b[2], $b[1], $b[0],
        $b[5], $b[4],
        $b[7], $b[6],
        $b[8], $b[9], $b[10], $b[11],
        $b[12], $b[13], $b[14], $b[15]
    )
    return ([guid]::new($mixed)).ToString('D')
}

function ConvertTo-PlainText {
    param([string]$Html)
    if (-not $Html) { return '' }
    $s = $Html -replace '<[^>]+>', ''
    $s = [System.Net.WebUtility]::HtmlDecode($s)
    return $s
}

function ConvertTo-NormalizedText {
    param([string]$Html)
    $s = ConvertTo-PlainText $Html
    $s = $s -replace '\u00A0', ' '
    $s = $s -replace '\s+', ' '
    return $s.Trim()
}

function Get-ItemName {
    param($Document)
    $span = $Document.DocumentNode.SelectSingleNode('//h2[contains(@class,"card-title")]//span[@data-copy]')
    if (-not $span) { return $null }
    $full = $span.GetAttributeValue('data-copy', '').Trim()
    $ru = $full
    $en = $null
    $m = [regex]::Match($full, '^(.*?)\s*\[(.*?)\]\s*$')
    if ($m.Success) {
        $ru = $m.Groups[1].Value.Trim()
        $en = $m.Groups[2].Value.Trim()
    }
    return [PSCustomObject]@{ ru = $ru; en = $en; full = $full }
}

function Get-ItemUrl {
    param($Document)
    $og = $Document.DocumentNode.SelectSingleNode('//meta[@property="og:url"]')
    if ($og) {
        $content = $og.GetAttributeValue('content', '')
        if ($content) { return $content }
    }
    $card = $Document.DocumentNode.SelectSingleNode('//div[@data-cardlink]')
    if ($card) {
        $rel = $card.GetAttributeValue('data-cardlink', '')
        if ($rel) { return ('https://dnd.su' + $rel) }
    }
    return $null
}

function Get-Slug {
    param([string]$Url)
    if (-not $Url) { return $null }
    $u = $Url.TrimEnd('/')
    $parts = $u -split '/'
    return $parts[-1]
}

function Get-RarityKeyFromOgDescription {
    param($Document)
    $og = $Document.DocumentNode.SelectSingleNode('//meta[@property="og:description"]')
    if (-not $og) { return $null }
    $desc = $og.GetAttributeValue('content', '')
    if (-not $desc) { return $null }
    $desc = [System.Net.WebUtility]::HtmlDecode($desc)
    $desc = $desc -replace '\u00A0', ' '
    $desc = $desc -replace '\s+', ' '

    if ($desc.IndexOf($config.no_rarity_marker, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
        return 'none'
    }

    $forms = $rarityMap.Keys | Sort-Object Length -Descending
    foreach ($form in $forms) {
        if ($desc -match ('\b' + [regex]::Escape($form) + '\s+качества\b')) {
            return $rarityMap[$form]
        }
    }
    return $null
}

function Get-TypeInfo {
    param([string]$RawHtml)

    $WORK = $RawHtml
    $prototype = $null

    # 1. Tooltip-prototype → marker
    $protoMatch = [regex]::Match($WORK,
        '<span[^>]*class="[^"]*item-tooltip[^"]*"[^>]*>([^<]*)</span>\s*(?=\))',
        'IgnoreCase')
    if ($protoMatch.Success) {
        $prototype = $protoMatch.Groups[1].Value.Trim()
        $prototype = ($prototype -replace '\s+', ' ').Trim()
        $WORK = $WORK.Substring(0, $protoMatch.Index) +
                [string]$protoMarker +
                $WORK.Substring($protoMatch.Index + $protoMatch.Length)
    }

    # 2. Strip tags & normalize
    $plain = ConvertTo-PlainText $WORK
    $plain = $plain.Replace([string]$protoMarker, '')
    $plain = $plain -replace '\u00A0', ' '
    $plain = $plain -replace '\(\s*\)', ''
    $plain = $plain -replace '\s+,', ','
    $plain = $plain -replace ',\s*,', ','
    $plain = $plain -replace '^\s*,', ''
    $plain = $plain -replace ',\s*$', ''
    $plain = $plain -replace '\s+', ' '
    $plain = $plain.Trim()

    # 3. Split at FIRST top-level comma (not inside parens)
    $depth = 0
    $splitIdx = -1
    for ($i = 0; $i -lt $plain.Length; $i++) {
        $ch = $plain[$i]
        if ($ch -eq '(') { $depth++ }
        elseif ($ch -eq ')') { $depth-- }
        elseif ($ch -eq ',' -and $depth -eq 0) { $splitIdx = $i; break }
    }
    $head = if ($splitIdx -ge 0) { $plain.Substring(0, $splitIdx).Trim() } else { $plain }
    $rest = if ($splitIdx -ge 0) { $plain.Substring($splitIdx + 1).Trim() } else { $null }

    # 4. Parse head: "type" or "type (paren)"
    $type = $head
    $headParen = $null
    $mHead = [regex]::Match($head, '^([^(]+?)\s*\(([^()]*)\)\s*$')
    if ($mHead.Success) {
        $type      = $mHead.Groups[1].Value.Trim()
        $headParen = $mHead.Groups[2].Value.Trim()
    }

    # 5. Parse rest: "rarity" or "rarity (tail)"
    $rarity = $null
    $tail   = $null
    if ($rest) {
        $mRest = [regex]::Match($rest, '^(.+?)\s*\(([^()]*)\)\s*$')
        if ($mRest.Success) {
            $rarity = $mRest.Groups[1].Value.Trim()
            $tail   = $mRest.Groups[2].Value.Trim()
        }
        else {
            $rarity = $rest
        }
    }

    # 6. Classify headParen: attunement or prototype?
    $attunement     = $false
    $attunementNote = $null
    $variants       = @()

    if ($headParen -and -not $prototype) {
        $hpAtt = $headParen.IndexOf($config.attunement_marker, [System.StringComparison]::OrdinalIgnoreCase)
        $hpNo  = $headParen.IndexOf($config.no_attunement_marker, [System.StringComparison]::OrdinalIgnoreCase)
        if ($hpAtt -ge 0) {
            $attunement = $true
            $noteRaw = $headParen.Substring($hpAtt + $config.attunement_marker.Length).Trim()
            if ($noteRaw) { $attunementNote = $noteRaw }
        }
        elseif ($hpNo -ge 0) {
            $attunement = $false
        }
        else {
            $prototype = $headParen
        }
    }

    # 7. Parse tail: attunement/variants/note
    if ($tail) {
        $variantsPart = $tail

        $attIdx = $tail.IndexOf($config.attunement_marker, [System.StringComparison]::OrdinalIgnoreCase)
        if ($attIdx -ge 0) {
            $attunement   = $true
            $variantsPart = $tail.Substring(0, $attIdx)
            $noteRaw      = $tail.Substring($attIdx + $config.attunement_marker.Length).Trim()
            if ($noteRaw) { $attunementNote = $noteRaw }
        }
        else {
            $noAttIdx = $tail.IndexOf($config.no_attunement_marker, [System.StringComparison]::OrdinalIgnoreCase)
            if ($noAttIdx -ge 0) {
                $attunement   = $false
                $variantsPart = $tail.Substring(0, $noAttIdx)
            }
        }

        $variantsPart = ($variantsPart -replace ',\s*$', '').Trim()

        # Classify: variants or note?
        $segments   = @(($variantsPart -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        $hasVariants = $false
        $hasNote     = $false
        foreach ($seg in $segments) {
            if ($seg -match $variantPat) { $hasVariants = $true }
            elseif ($rarityMap.ContainsKey($seg)) { $hasVariants = $true }
            else { $hasNote = $true }
        }

        if ($hasVariants) {
            foreach ($seg in $segments) {
                if ($seg -match $variantPat) {
                    $bonus = '+' + $matches[1]
                    $rar   = $matches[2].Trim()
                    $key   = if ($rarityMap.ContainsKey($rar)) { $rarityMap[$rar] } else { 'unknown' }
                    $variants += [PSCustomObject]@{
                        bonus      = $bonus
                        rarity     = $rar
                        rarity_key = $key
                    }
                }
                elseif ($rarityMap.ContainsKey($seg)) {
                    $variants += [PSCustomObject]@{
                        bonus      = $null
                        rarity     = $seg
                        rarity_key = $rarityMap[$seg]
                    }
                }
            }
        }
        elseif ($hasNote -and -not $attunement) {
            # Freeform note in tail (e.g. "может быть использован только рейгаром, создавшим его")
            $attunement     = $true
            $attunementNote = $variantsPart
        }
    }

    # 8. Rarity key
    $rarityKey = 'none'
    if ($rarity) {
        if ($rarityMap.ContainsKey($rarity)) { $rarityKey = $rarityMap[$rarity] }
        elseif ($rarity -match 'варьиру')    { $rarityKey = 'varies' }
        else                                 { $rarityKey = 'unknown' }
    }

    return [PSCustomObject]@{
        type            = $type
        prototype       = $prototype
        rarity          = $rarity
        rarity_key      = $rarityKey
        rarity_variants = $variants
        attunement      = $attunement
        attunement_note = $attunementNote
    }
}

function Get-PriceInfo {
    param([string]$RawText)

    if (-not $RawText) {
        return [PSCustomObject]@{ text = $null; value = $null }
    }
    $raw   = $RawText.Trim()
    $clean = $raw -replace '\u00A0', ' '
    $clean = $clean -replace '\s+', ' '
    $clean = $clean.Trim()

    $unit  = [regex]::Escape($config.price_unit)
    $fromP = [regex]::Escape($config.price_from_prefix)

    $mFrom = [regex]::Match($clean, '^\s*' + $fromP + '\s+(\d[\d\s]*?)\s*' + $unit + '\s*$')
    if ($mFrom.Success) {
        $minStr = $mFrom.Groups[1].Value -replace '\s', ''
        $min = [int64]$minStr
        return [PSCustomObject]@{
            text  = $clean
            value = [PSCustomObject]@{ min = $min; max = $null; unit = $config.price_unit }
        }
    }

    $m = [regex]::Match($clean, '^\s*(\d[\d\s]*?)(?:\s*-\s*(\d[\d\s]*?))?\s*' + $unit + '\s*$')
    if ($m.Success) {
        $minStr = $m.Groups[1].Value -replace '\s', ''
        $min = [int64]$minStr
        $max = $min
        if ($m.Groups[2].Success -and $m.Groups[2].Value) {
            $maxStr = $m.Groups[2].Value -replace '\s', ''
            $max = [int64]$maxStr
        }
        return [PSCustomObject]@{
            text  = $clean
            value = [PSCustomObject]@{ min = $min; max = $max; unit = $config.price_unit }
        }
    }

    return [PSCustomObject]@{ text = $clean; value = $null }
}

function Get-DescriptionInfo {
    param($Document)

    $div = $Document.DocumentNode.SelectSingleNode('//div[@itemprop="description"]')
    if (-not $div) {
        return [PSCustomObject]@{
            text = $null; html = $null
            additional_text = $null; additional_html = $null
        }
    }

    $addText = $null
    $addHtml = $null
    $addNode = $div.SelectSingleNode('.//div[contains(@class,"additionalInfo")]')
    if ($addNode) {
        $addHtml = $addNode.InnerHtml
        $addText = ConvertTo-NormalizedText $addNode.InnerText
        $addNode.Remove()
    }

    $descHtml = $div.InnerHtml
    $descHtml = $descHtml -replace '(<br\s*/?>\s*)+$', ''
    $descHtml = $descHtml.Trim()
    $descText = ConvertTo-NormalizedText $descHtml

    return [PSCustomObject]@{
        text            = $descText
        html            = $descHtml
        additional_text = $addText
        additional_html = $addHtml
    }
}

function Parse-OneItem {
    param([string]$HtmlPath)

    $html = [System.IO.File]::ReadAllText($HtmlPath, [System.Text.Encoding]::UTF8)
    $doc = New-Object HtmlAgilityPack.HtmlDocument
    $doc.LoadHtml($html)

    $url  = Get-ItemUrl $doc
    $slug = Get-Slug $url
    $id   = if ($url) { New-DeterministicGuid -Name $url } else { $null }

    $name = Get-ItemName $doc

    $sizeLi   = $doc.DocumentNode.SelectSingleNode('//li[contains(@class,"size-type-alignment")]')
    $typeInfo = if ($sizeLi) { Get-TypeInfo $sizeLi.InnerHtml } else { $null }

    $ogRarityKey = Get-RarityKeyFromOgDescription $doc
    $finalRarityKey = if ($ogRarityKey) { $ogRarityKey }
                      elseif ($typeInfo) { $typeInfo.rarity_key }
                      else { 'none' }

    $variantsValue = $null
    if ($typeInfo -and $typeInfo.rarity_variants) {
        $arr = @($typeInfo.rarity_variants)
        if ($arr.Count -gt 0) { $variantsValue = $arr }
    }

    $priceText = $null
    $priceLi = $doc.DocumentNode.SelectSingleNode('//li[contains(@class,"price")]')
    if ($priceLi) {
        $t = ConvertTo-NormalizedText $priceLi.InnerText
        $prefix = [regex]::Escape($config.price_prefix)
        $t = $t -replace ('^\s*' + $prefix + '\s*'), ''
        $t = $t.Trim()
        if ($t) { $priceText = $t }
    }
    $price = Get-PriceInfo $priceText

    $desc = Get-DescriptionInfo $doc

    return [PSCustomObject]@{
        id              = $id
        url             = $url
        slug            = $slug
        source          = 'official'
        name            = $name
        type            = if ($typeInfo) { $typeInfo.type } else { $null }
        prototype       = if ($typeInfo) { $typeInfo.prototype } else { $null }
        rarity          = if ($typeInfo) { $typeInfo.rarity } else { $null }
        rarity_key      = $finalRarityKey
        rarity_variants = $variantsValue
        attunement      = if ($typeInfo) { $typeInfo.attunement } else { $false }
        attunement_note = if ($typeInfo) { $typeInfo.attunement_note } else { $null }
        price_text      = $price.text
        price           = $price.value
        description     = [PSCustomObject]@{
            text = $desc.text
            html = $desc.html
        }
        additional_info = [PSCustomObject]@{
            text = $desc.additional_text
            html = $desc.additional_html
        }
        meta = [PSCustomObject]@{
            parsed_at = (Get-Date).ToUniversalTime().ToString('o')
        }
    }
}

function Write-ItemJson {
    param($Item, [string]$OutDir, [bool]$UseRarity)
    if (-not (Test-Path -LiteralPath $OutDir)) {
        New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
    }
    $baseName = if ($Item.slug) { $Item.slug } else { "item-$(Get-Random)" }
    $prefix   = ''
    if ($UseRarity) {
        $rk = if ($Item.rarity_key) { $Item.rarity_key } else { 'none' }
        $prefix = "[$rk]"
    }
    $fileName = "$prefix$baseName.json"
    $path = Join-Path $OutDir $fileName
    $json = $Item | ConvertTo-Json -Depth 20
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($path, $json, $utf8NoBom)
    return $path
}

# ---- Main ----
if (-not $InputPath) {
    Write-Host 'Usage: Parse-Item.ps1 -InputPath <file-or-folder> [-NoPause]'
    if (-not $NoPause) { Read-Host 'Press Enter to exit' | Out-Null }
    exit 0
}

if (-not (Test-Path -LiteralPath $InputPath)) {
    Stop-WithMessage "Input not found: $InputPath"
}

$item  = Get-Item -LiteralPath $InputPath
$files = if ($item.PSIsContainer) {
    @(Get-ChildItem -LiteralPath $InputPath -Filter '*.html' -File | Sort-Object Name)
} else {
    @($item)
}

if ($files.Count -eq 0) {
    Write-Host "No .html files found in: $InputPath"
    if (-not $NoPause) { Read-Host 'Press Enter to exit' | Out-Null }
    exit 0
}

Write-Host "Parsing $($files.Count) file(s) -> $OutputDir  WithRarity=$WithRarity"
Write-Host ''

$ok = 0; $fail = 0
foreach ($f in $files) {
    Write-Host "==> $($f.Name)"
    try {
        $parsed  = Parse-OneItem -HtmlPath $f.FullName
        $outPath = Write-ItemJson -Item $parsed -OutDir $OutputDir -UseRarity $WithRarity

        $rarity = if ($parsed.rarity) { $parsed.rarity } else { '-' }
        $proto  = if ($parsed.prototype) { $parsed.prototype } else { '-' }
        $att    = if ($parsed.attunement) { 'yes' } else { 'no' }
        $note   = if ($parsed.attunement_note) { " ($($parsed.attunement_note))" } else { '' }
        $nvar   = if ($parsed.rarity_variants) { $parsed.rarity_variants.Count } else { 0 }
        $priceS = if ($parsed.price_text) { $parsed.price_text } else { '-' }
        $rkey   = $parsed.rarity_key

        Write-Host ("    type={0} | proto={1} | rarity={2} [{3}] | att={4}{5} | variants={6} | price={7}" -f `
            $parsed.type, $proto, $rarity, $rkey, $att, $note, $nvar, $priceS)
        Write-Host "    -> $outPath"
        $ok++
    }
    catch {
        Write-Warning "    FAILED: $($_.Exception.Message)"
        $fail++
    }
}

Write-Host ''
Write-Host "Done: $ok ok, $fail failed."

if (-not $NoPause) { Read-Host 'Press Enter to exit' | Out-Null }