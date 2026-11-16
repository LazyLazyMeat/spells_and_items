[CmdletBinding()]
param(
    [string]$Path,
    [string]$OutputPath,
    [switch]$Print,
    [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
try {
    [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
    $OutputEncoding           = New-Object System.Text.UTF8Encoding($false)
} catch { }

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

try {
    if ([string]::IsNullOrWhiteSpace($Path)) {
        Write-Host 'Usage: Parse-Spell.bat <path-to-html> [-Print]' -ForegroundColor Yellow
        Write-Host 'Example: Parse-Spell.bat ..\..\source\spells\[1]333-create-or-destroy-water.html'
        return
    }
        # Build candidate paths: absolute, relative to project root,
    # relative to source/spells, plus auto-append .html if missing.
    $candidates = New-Object System.Collections.Generic.List[string]
    if ([System.IO.Path]::IsPathRooted($Path)) {
        $candidates.Add($Path)
    } else {
        $candidates.Add((Join-Path $projectRoot $Path))
        $candidates.Add((Join-Path $projectRoot "source/spells/$Path"))
        if ($Path -notmatch '\.html?$') {
            $candidates.Add((Join-Path $projectRoot "source/spells/$Path.html"))
        }
    }

    $fullPath = $null
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) {
            $fullPath = (Resolve-Path -LiteralPath $c).Path
            break
        }
    }

    # Fallback: treat input as slug, search *<slug>.html in source/spells.
    if (-not $fullPath) {
        $searchName = [System.IO.Path]::GetFileNameWithoutExtension($Path)
        $srcDir     = Join-Path $projectRoot 'source/spells'
        if ((Test-Path -LiteralPath $srcDir) -and $searchName) {
            $hit = Get-ChildItem -LiteralPath $srcDir -File -Filter "*$searchName.html" -ErrorAction SilentlyContinue |
                Select-Object -First 1
            if ($hit) { $fullPath = $hit.FullName }
        }
    }

    if (-not $fullPath) {
        Write-Host ""
        Write-Host "[error] File not found:" -ForegroundColor Red
        Write-Host "  $Path"
        Write-Host ""
        Write-Host "Tried:" -ForegroundColor Yellow
        foreach ($c in $candidates) { Write-Host "  $c" }
        Write-Host ""
        Write-Host "Tip: you can pass" -ForegroundColor Cyan
        Write-Host "  - a full path to an .html file,"
        Write-Host "  - a path relative to the project root,"
        Write-Host "  - or a slug from source/spells (e.g. 333-create-or-destroy-water)."
        return
    }

    # ---- HtmlAgilityPack ----
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
            $src = Join-Path $extract "lib/$fw/HtmlAgilityPack.dll"
            if (-not (Test-Path $src)) { throw "Not found: $src" }
            Copy-Item $src $hapDll -Force
        }
        Add-Type -Path $hapDll
    }
    Initialize-HtmlAgilityPack

    # ---- helpers ----
    function Get-NormalizedText([string]$t) {
        if ([string]::IsNullOrWhiteSpace($t)) { return $null }
        $s = $t -replace '[\u00A0\u2007\u202F]', ' '
        $s = $s -replace '\s+', ' '
        return $s.Trim()
    }

    function Get-SafeInnerText($node) {
        if ($null -eq $node) { return $null }
        try { return $node.InnerText } catch { return $null }
    }

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

    function Get-ParamsMap($Card) {
        $map = [ordered]@{}
        $lis = $Card.SelectNodes(".//ul[contains(concat(' ',normalize-space(@class),' '),' params ')]/li")
        if (-not $lis) { return $map }
        foreach ($li in $lis) {
            $strong = $li.SelectSingleNode('./strong[1]')
            if (-not $strong) { continue }
            $label = Get-NormalizedText $strong.InnerText
            if (-not $label) { continue }
            $label = $label.TrimEnd(':', '：').Trim()
            $sb = New-Object System.Text.StringBuilder
            $n = $strong.NextSibling
            while ($n) {
                if ($n.NodeType -eq [HtmlAgilityPack.HtmlNodeType]::Text -or
                    $n.NodeType -eq [HtmlAgilityPack.HtmlNodeType]::Element) {
                    [void]$sb.Append($n.InnerText)
                }
                $n = $n.NextSibling
            }
            $map[$label] = Get-NormalizedText $sb.ToString()
        }
        return $map
    }

    function Get-Description($Card) {
        $div = $Card.SelectSingleNode(".//div[@itemprop='description']")
        if (-not $div) { return @{ text = $null; html = $null } }
        $html  = $div.InnerHtml.Trim()
        $parts = New-Object System.Collections.Generic.List[string]
        foreach ($child in $div.ChildNodes) {
            if ($child.NodeType -ne [HtmlAgilityPack.HtmlNodeType]::Element) { continue }
            switch ($child.Name) {
                'p' {
                    $t = Get-NormalizedText (Get-SafeInnerText $child)
                    if ($t) { $parts.Add($t) }
                }
                'ul' {
                    $lis = $child.SelectNodes('./li')
                    if ($lis) {
                        foreach ($li in $lis) {
                            $t = Get-NormalizedText (Get-SafeInnerText $li)
                            if ($t) { $parts.Add(([string][char]0x2022) + ' ' + $t) }
                        }
                    }
                }
                'ol' {
                    $lis = $child.SelectNodes('./li')
                    if ($lis) {
                        $i = 0
                        foreach ($li in $lis) {
                            $i++
                            $t = Get-NormalizedText (Get-SafeInnerText $li)
                            if ($t) { $parts.Add("$i. $t") }
                        }
                    }
                }
                'table' {
                    $rows = $child.SelectNodes('.//tr')
                    if ($rows) {
                        foreach ($row in $rows) {
                            $cellNodes = $row.SelectNodes('./td|./th')
                            $cells = @()
                            if ($cellNodes) {
                                foreach ($cell in $cellNodes) {
                                    $cells += (Get-NormalizedText (Get-SafeInnerText $cell))
                                }
                            }
                            if ($cells.Count -gt 0) { $parts.Add(($cells -join ' | ')) }
                        }
                    }
                }
                default {
                    $t = Get-NormalizedText (Get-SafeInnerText $child)
                    if ($t) { $parts.Add($t) }
                }
            }
        }
        return @{
            text = [string]::Join("`n`n", $parts).Trim()
            html = $html
        }
    }

    function Split-ListField([string]$v) {
        if ([string]::IsNullOrWhiteSpace($v)) { return $null }
        $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        $out  = New-Object System.Collections.Generic.List[string]
        foreach ($part in ($v -split '\s*,\s*')) {
            $clean = ($part -replace '(?i)\s*\(?\s*TCE\s*\)?\s*$', '').Trim()
            if ($clean -and $seen.Add($clean)) { $out.Add($clean) }
        }
        if ($out.Count -eq 0) { return $null }
        return , $out.ToArray()
    }

    function ConvertFrom-DndSpellHtml([string]$HtmlContent, [string]$SourceFile) {
        $doc = New-Object HtmlAgilityPack.HtmlDocument
        $doc.LoadHtml($HtmlContent)

        $card = $doc.DocumentNode.SelectSingleNode(
            "//div[contains(concat(' ',normalize-space(@class),' '),' card__category-spells ')]")
        if (-not $card) { throw 'card__category-spells not found.' }

        $url = $null
        $ogUrl = $doc.DocumentNode.SelectSingleNode("//meta[@property='og:url']")
        if ($ogUrl -and $ogUrl.Attributes['content']) {
            $url = Get-NormalizedText $ogUrl.Attributes['content'].Value
        }
        if (-not $url -and $card.Attributes['data-cardlink']) {
            $cardLink = $card.Attributes['data-cardlink'].Value
            if ($cardLink) { $url = 'https://dnd.su' + $cardLink }
        }

        $uuidName = if ($url) { $url } else {
            $t = $card.SelectSingleNode(".//h2//span[@data-copy]")
            if ($t) { $t.Attributes['data-copy'].Value } else { [System.IO.Path]::GetFileNameWithoutExtension($SourceFile) }
        }
        $id = New-DeterministicGuid -Name $uuidName

        $titleSpan = $card.SelectSingleNode(".//h2[contains(concat(' ',normalize-space(@class),' '),' card-title ')]/span[@data-copy]")
        $fullTitle = $null
        if ($titleSpan) {
            $fullTitle = if ($titleSpan.Attributes['data-copy']) { $titleSpan.Attributes['data-copy'].Value } else { $titleSpan.InnerText }
            $fullTitle = Get-NormalizedText $fullTitle
        }
        $nameRu = $null; $nameEn = $null
        if ($fullTitle) {
            if ($fullTitle -match '^(?<ru>.*?)\s*\[\s*(?<en>[^\]]+?)\s*\]\s*$') {
                $nameRu = Get-NormalizedText $Matches['ru']
                $nameEn = Get-NormalizedText $Matches['en']
            } else { $nameRu = $fullTitle }
        }

        $params = Get-ParamsMap $card

        # level / school / ritual / concentration / dunamancy
        $level         = $null
        $school        = $null
        $ritual        = $false
        $concentration = $false
        $dunamancy     = $false
        $dunamancySub  = $null

        $ls = $card.SelectSingleNode(".//ul[contains(concat(' ',normalize-space(@class),' '),' params ')]/li[contains(concat(' ',normalize-space(@class),' '),' size-type-alignment ')]")
        if ($ls) {
            $lsText = Get-NormalizedText $ls.InnerText
            if ($lsText -and ($lsText -match '^(?<lvl>Заговор|\d+)(?:\s+уровень)?\s*,\s*(?<rest>.+)$')) {
                if ($Matches['lvl'] -eq 'Заговор') { $level = 0 }
                else {
                    $tmp = 0
                    if ([int]::TryParse($Matches['lvl'], [ref]$tmp)) { $level = $tmp }
                }
                $rest = Get-NormalizedText $Matches['rest']

                $tags = @()
                if ($rest -match '^(?<base>.+?)\s*\((?<tags>[^)]+)\)\s*$') {
                    $rest = Get-NormalizedText $Matches['base']
                    $tags = @($Matches['tags'] -split '\s*,\s*' |
                                ForEach-Object { $_.Trim() } |
                                Where-Object { $_ })
                }

                foreach ($tag in $tags) {
                    $tl = $tag.ToLower()
                    if     ($tl -eq 'ритуал')       { $ritual = $true }
                    elseif ($tl -eq 'концентрация') { $concentration = $true }
                    elseif ($tl -eq 'дюнамантия')   { $dunamancy = $true }
                    elseif ($tl -match '^дюнамантия\s*:\s*(?<sub>.+)$') {
                        $dunamancy    = $true
                        $dunamancySub = Get-NormalizedText $Matches['sub']
                    }
                }

                if ($rest -match '^дюнамантия(?:\s*:\s*(?<sub>.+))?$') {
                    $dunamancy = $true
                    if ($Matches['sub']) { $dunamancySub = Get-NormalizedText $Matches['sub'] }
                    $school = $null
                } else {
                    $school = if ([string]::IsNullOrWhiteSpace($rest)) { $null } else { $rest }
                }
            }
        }

        $durationRaw = if ($params.Contains('Длительность')) { $params['Длительность'] } else { $null }
        if (-not $concentration -and $durationRaw -and ($durationRaw -match 'концентрац')) {
            $concentration = $true
        }

        $desc = Get-Description $card

        $compRaw = if ($params.Contains('Компоненты')) { $params['Компоненты'] } else { $null }
        $compObj = $null
        if ($compRaw) {
            $hasV = $compRaw -match '(?<![А-Яа-яЁё])В(?![А-Яа-яЁё])'
            $hasS = $compRaw -match '(?<![А-Яа-яЁё])С(?![А-Яа-яЁё])'
            $hasM = $compRaw -match '(?<![А-Яа-яЁё])М(?![А-Яа-яЁё])'
            $matDesc = $null
            if ($compRaw -match '(?<![А-Яа-яЁё])М\s*\((?<desc>.+)\)\s*$') {
                $matDesc = Get-NormalizedText $Matches['desc']
            }
            $compObj = [ordered]@{
                raw           = $compRaw
                verbal        = [bool]$hasV
                somatic       = [bool]$hasS
                material      = [bool]$hasM
                material_desc = $matDesc
            }
        }

        $result = [ordered]@{
            id            = $id
            url           = $url
            source        = 'official'
            name          = [ordered]@{ ru = $nameRu; en = $nameEn; full = $fullTitle }
            level         = $level
            school        = $school
            ritual        = $ritual
            concentration = $concentration
            dunamancy     = $dunamancy
            dunamancy_sub = $dunamancySub
            cast_time     = if ($params.Contains('Время накладывания')) { $params['Время накладывания'] } else { $null }
            range         = if ($params.Contains('Дистанция'))          { $params['Дистанция'] }          else { $null }
            duration      = $durationRaw
            components    = $compObj
            classes       = Split-ListField ($(if ($params.Contains('Классы'))    { $params['Классы'] }    else { $null }))
            subclasses    = Split-ListField ($(if ($params.Contains('Подклассы')) { $params['Подклассы'] } else { $null }))
            description   = [ordered]@{ text = $desc.text; html = $desc.html }
            meta          = [ordered]@{ parsed_at = (Get-Date).ToString('o'); source_file = $SourceFile }
        }
        return [pscustomobject]$result
    }

    # main
    Write-Host "[parse] $fullPath"
    $html  = Get-Content -LiteralPath $fullPath -Raw -Encoding UTF8
    $spell = ConvertFrom-DndSpellHtml -HtmlContent $html -SourceFile (Split-Path -Leaf $fullPath)

    $slug = $null
    if ($spell.url -and ($spell.url -match '/spells/(?<slug>[^/]+)/?$')) { $slug = $Matches['slug'] }
    if ([string]::IsNullOrWhiteSpace($slug)) { $slug = 'unknown' }

    $levelTag = if ($null -ne $spell.level) { [string]$spell.level } else { '?' }

    if (-not $OutputPath) {
        $fileName   = "[$levelTag]$slug.json"
        $OutputPath = Join-Path $projectRoot ("data/spells/$fileName")
    }
    if (-not [System.IO.Path]::IsPathRooted($OutputPath)) {
        $OutputPath = Join-Path $projectRoot $OutputPath
    }

    $outDir = Split-Path -Parent $OutputPath
    if ($outDir -and -not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }

    $json = $spell | ConvertTo-Json -Depth 20
    [System.IO.File]::WriteAllText($OutputPath, $json, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "[ok] id=$($spell.id)" -ForegroundColor Green
    Write-Host "[ok] $OutputPath"      -ForegroundColor Green
    if ($Print) { Write-Host "`n--- JSON ---" -ForegroundColor Cyan; Write-Output $json }
} finally {
    if (-not $NoPause) { Read-Host 'Press Enter to exit' | Out-Null }
}