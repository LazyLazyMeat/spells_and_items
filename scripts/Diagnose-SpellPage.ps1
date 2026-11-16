[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$Url,
    [int]$PreviewChars = 3000
)

$ErrorActionPreference = 'Stop'
try {
    [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
    $OutputEncoding           = New-Object System.Text.UTF8Encoding($false)
} catch { }

Write-Host "=== URL: $Url ==="

# 1) Без автоперехода по редиректам — смотрим, что отдаёт сам dnd.su
$userAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) ' +
             'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36'

Write-Host "`n--- HEAD/GET without auto-redirect ---"
try {
    $req = [System.Net.HttpWebRequest]::Create($Url)
    $req.UserAgent = $userAgent
    $req.AllowAutoRedirect = $false
    $req.Timeout = 30000
    $resp = $req.GetResponse()
    Write-Host ("Status : {0} {1}" -f [int]$resp.StatusCode, $resp.StatusCode)
    Write-Host ("Location: {0}" -f $resp.Headers['Location'])
    Write-Host ("Content-Type: {0}" -f $resp.ContentType)
    Write-Host ("Content-Encoding: {0}" -f $resp.Headers['Content-Encoding'])
    $resp.Close()
} catch {
    Write-Warning "Request without redirect failed: $_"
}

# 2) С автопереходом — то, что реально получает Save-SpellPage.ps1
Write-Host "`n--- GET with auto-redirect (like Save-SpellPage) ---"
try {
    $resp2 = Invoke-WebRequest -Uri $Url -UserAgent $userAgent `
        -UseBasicParsing -TimeoutSec 30
    Write-Host ("Status  : {0}" -f $resp2.StatusCode)
    Write-Host ("Final URI: {0}" -f $resp2.BaseResponse.ResponseUri)
    Write-Host ("Content-Type: {0}" -f $resp2.Headers['Content-Type'])
    Write-Host ("Content-Encoding: {0}" -f $resp2.Headers['Content-Encoding'])
    Write-Host ("Length  : {0} chars" -f $resp2.Content.Length)

    $hasCard = $resp2.Content -match 'card__category-spells'
    $hasNext = $resp2.Content -match 'next\.dnd\.su'
    $hasMail = $resp2.Content -match 'mail\.dnd\.su'
    $has5e14 = $resp2.Content -match '5e14\.dnd\.su'
    $hasCaptcha = $resp2.Content -match 'captcha|showcaptcha|smartcaptcha|ddos-guard'

    Write-Host ""
    Write-Host ("Contains 'card__category-spells': {0}" -f $hasCard)
    Write-Host ("Contains 'next.dnd.su'          : {0}" -f $hasNext)
    Write-Host ("Contains 'mail.dnd.su'          : {0}" -f $hasMail)
    Write-Host ("Contains '5e14.dnd.su'          : {0}" -f $has5e14)
    Write-Host ("Contains captcha/ddos markers   : {0}" -f $hasCaptcha)

    Write-Host "`n--- First $PreviewChars chars of body ---"
    $preview = $resp2.Content.Substring(0, [Math]::Min($PreviewChars, $resp2.Content.Length))
    Write-Host $preview
} catch {
    Write-Warning "Invoke-WebRequest failed: $_"
}