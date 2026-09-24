#requires -Version 5.1
param([switch]$Child,[string]$Kind,[string]$Case)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
if (-not $Child) {
    foreach ($f in Get-ChildItem (Join-Path $repo 'scripts/LocalAdminAccount') -Filter *.ps1) {
        $t=$null; $e=$null
        $null=[Management.Automation.Language.Parser]::ParseFile($f.FullName,[ref]$t,[ref]$e)
        if ($e.Count) { throw ($e | Out-String) }
    }
    $matrix = @{
        AdminCreation = @('new','blank','owned','disabled','notAdmin','unowned','mismatch','addFailure','silentAddFailure','readFailure','preview')
        Detection = @('owned','disabled','notAdmin','unowned','mismatch','wrongVersion','absent','readFailure')
        Uninstall = @('owned','unowned','mismatch','absent','renamed','removeFailure','silentRemoveFailure','noConfirmation','preview')
    }
    $count=0
    foreach ($k in $matrix.Keys) {
        foreach ($c in $matrix[$k]) {
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -Child -Kind $k -Case $c
            if ($LASTEXITCODE) { throw "FAIL $k / $c" }
            $count++
        }
    }
    Write-Output "PASS: syntax and $count lifecycle checks; no real account or registry changes."
    exit 0
}
$global:caseName=$Case
$global:account=[pscustomobject]@{Name='ManagedLocalAdmin';SID=[pscustomobject]@{Value='S-1-5-21-1-2-3-1001'};Enabled=$true}
$global:record=[pscustomobject]@{AccountSid=$global:account.SID.Value;Version='1.0.0'}
$global:admin=$true
$global:created=0; $global:deleted=0; $global:changes=0; $global:noExpiry=$false
switch ($Case) {
    {$_ -in @('new','blank','absent')} { $global:account=$null; $global:record=$null; $global:admin=$false }
    'disabled' { $global:account.Enabled=$false }
    'notAdmin' { $global:admin=$false }
    'unowned' { $global:record=$null }
    'mismatch' { $global:record.AccountSid='S-1-5-21-1-2-3-2002' }
    'wrongVersion' { $global:record.Version='0.0.0' }
    'renamed' { $global:account.Name='RenamedAccount' }
    {$_ -in @('addFailure','silentAddFailure')} { $global:admin=$false }
}
function Import-Module { param($Name,$ErrorAction) }
function New-Object { $p=[pscustomobject]@{}; $p | Add-Member ScriptMethod IsInRole { param($role) $true }; $p }
function Get-LocalUser {
    param($Name,$SID,$ErrorAction)
    if ($global:caseName -eq 'readFailure') { throw 'Simulated read failure' }
    if ($global:account) { return $global:account }
    if ($Name -or $SID) { throw 'Account absent' }
}
function Get-LocalGroupMember { param($SID,$ErrorAction); if ($global:admin -and $global:account) { $global:account } }
function New-LocalUser {
    param($Name,$Password,$Description,[switch]$PasswordNeverExpires,[switch]$Disabled,$ErrorAction)
    if ($Password -isnot [Security.SecureString]) { throw 'Password must be converted before creation' }
    $global:created++; $global:changes++; $global:noExpiry=[bool]$PasswordNeverExpires
    $global:account=[pscustomobject]@{Name=$Name;SID=[pscustomobject]@{Value='S-1-5-21-1-2-3-1001'};Enabled=(-not $Disabled)}
    return $global:account
}
function Set-LocalUser { throw 'Unexpected password/account reset' }
function Enable-LocalUser { param($SID,$ErrorAction); $global:changes++; $global:account.Enabled=$true }
function Add-LocalGroupMember {
    param($SID,$Member,$ErrorAction)
    if ($global:caseName -eq 'addFailure') { throw 'Simulated group failure' }
    $global:changes++
    if ($global:caseName -ne 'silentAddFailure') { $global:admin=$true }
}
function Remove-LocalUser {
    param($SID,$ErrorAction)
    if ($global:caseName -eq 'removeFailure') { throw 'Simulated deletion failure' }
    if ($SID -ne $global:account.SID.Value) { throw 'Wrong deletion SID' }
    $global:changes++; $global:deleted++
    if ($global:caseName -ne 'silentRemoveFailure') { $global:account=$null }
}
function Test-Path { param($LiteralPath); return ($null -ne $global:record) }
function Get-ItemProperty { param($LiteralPath,$ErrorAction); if (-not $global:record) { throw 'Record absent' }; $global:record }
function New-Item { param($Path,[switch]$Force,$ErrorAction); $global:changes++; $global:record=[pscustomobject]@{AccountSid='';Version=''} }
function New-ItemProperty { param($LiteralPath,$Name,$Value,$PropertyType,[switch]$Force,$ErrorAction); $global:changes++; $global:record.$Name=$Value }
function Remove-Item { param($LiteralPath,[switch]$Force,$ErrorAction); $global:changes++; $global:record=$null }
$path=Join-Path $repo "scripts/LocalAdminAccount/$Kind.ps1"
# Only the isolated test copy gets a synthetic value; never use the user's source.
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('account-test-' + [guid]::NewGuid().ToString() + '.ps1')
$text=[IO.File]::ReadAllText($path)
if ($Case -ne 'blank') { $text=$text.Replace("`$InitialPassword = ''", "`$InitialPassword = [guid]::NewGuid().ToString()") }
[IO.File]::WriteAllText($fixture,$text)
$argsForScript=@{}
if ($Case -eq 'preview') { $argsForScript.WhatIf=$true }
if ($Kind -eq 'Uninstall' -and $Case -ne 'noConfirmation') { $argsForScript.ConfirmRemoval=$true }
try { $result=& $fixture @argsForScript; $actual=$LASTEXITCODE } finally { [IO.File]::Delete($fixture) }
$expected=1
if ($Kind -eq 'AdminCreation' -and $Case -in @('new','owned','disabled','notAdmin','preview')) { $expected=0 }
if ($Kind -eq 'Detection' -and $Case -eq 'owned') { $expected=0 }
if ($Kind -eq 'Uninstall' -and $Case -in @('owned','absent','preview')) { $expected=0 }
if ($actual -ne $expected) { throw "Expected $expected got $actual : $result" }
if ($Kind -eq 'Detection' -and $actual -eq 0 -and [string]::IsNullOrWhiteSpace(($result -join ''))) { throw 'Missing detection stdout' }
if (($Kind -eq 'Detection' -or $Case -in @('preview','unowned','mismatch','readFailure','blank','noConfirmation')) -and $global:changes) { throw 'Unexpected changes' }
if ($Kind -eq 'AdminCreation' -and $Case -eq 'new' -and ($global:created -ne 1 -or -not $global:noExpiry -or -not $global:account.Enabled -or -not $global:admin)) { throw 'Creation result invalid' }
if ($Kind -eq 'AdminCreation' -and $Case -in @('owned','disabled','notAdmin') -and $global:created) { throw 'Existing account recreated' }
if ($Kind -eq 'Uninstall' -and $Case -eq 'owned' -and ($global:account -or $global:record -or $global:deleted -ne 1)) { throw 'Uninstall incomplete' }
Write-Output "PASS $Kind / $Case"
exit 0
