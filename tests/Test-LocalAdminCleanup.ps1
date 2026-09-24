#requires -Version 5.1
[CmdletBinding()]
param([switch]$Child, [string]$Kind, [string]$Scenario, [string]$DeploymentType = 'Win32')
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot

if (-not $Child) {
    foreach ($file in Get-ChildItem -Path (Join-Path $repo 'scripts') -Filter '*.ps1') {
        $tokens = $null; $parseErrors = $null
        $null = [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
    }
    $count = 0
    foreach ($kindName in @('Detect', 'Invoke')) {
        foreach ($case in @('mixed', 'clean', 'excluded', 'caseInsensitive', 'localSameName', 'readFailure', 'verifyFailure', 'removeFailure', 'silentFailure', 'missingSid', 'invalidExclusion', 'empty', 'single', 'preview', 'logFailure', 'notElevated')) {
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -Child -Kind $kindName -Scenario $case
            if ($LASTEXITCODE -ne 0) { throw "FAILED: $kindName / $case" }
            $count++
        }
    }
    foreach ($case in @('mixed', 'clean', 'readFailure', 'missingSid', 'invalidExclusion')) {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -Child -Kind Detect -Scenario $case -DeploymentType Remediation
        if ($LASTEXITCODE -ne 0) { throw "FAILED: Remediation detection / $case" }
        $count++
    }
    Write-Output "PASS: syntax and $count isolated behavioral checks. No real account commands were executed."
    exit 0
}

# These mocks shadow every operating-system mutation/import used by the scripts.
# Each case runs in a fresh process so module/session state cannot leak between cases.
function New-TestMember($name, $sid, $class, $source) {
    [pscustomobject]@{ Name=$name; SID=[pscustomobject]@{ Value=$sid }; ObjectClass=$class; PrincipalSource=$source }
}
$global:testUser = New-TestMember 'AzureAD\ExampleUser' 'S-1-12-1-111-222-333-444' 'User' 'AzureAD'
$global:testLocal = New-TestMember 'DEVICE\RecoveryAdmin' 'S-1-5-21-1-2-3-1001' 'User' 'Local'
$global:testRole = New-TestMember 'S-1-12-1-555-666-777-888' 'S-1-12-1-555-666-777-888' 'Other' 'AzureAD'
$global:testGroup = New-TestMember 'AzureAD\ExampleGroup' 'S-1-12-1-222-333-444-555' 'Group' 'AzureAD'
$global:testMembers = @($global:testUser, $global:testLocal, $global:testRole, $global:testGroup)
$global:testRemovals = @()
$global:testReads = 0
$global:testWrites = 0
$global:testCase = $Scenario
switch ($Scenario) {
    'clean' { $global:testMembers = @($global:testLocal, $global:testRole, $global:testGroup) }
    'caseInsensitive' { $global:testUser.Name = 'azuread\ExampleUser' }
    'localSameName' { $global:testUser.Name = 'DEVICE\ExampleUser'; $global:testUser.PrincipalSource = 'Local' }
    'missingSid' { $global:testUser.SID = $null }
    'empty' { $global:testMembers = @() }
    'single' { $global:testMembers = @($global:testUser) }
}

function Import-Module { param($Name, $ErrorAction) }
function New-Object {
    $principal = [pscustomobject]@{}
    $principal | Add-Member -MemberType ScriptMethod -Name IsInRole -Value { param($role) return ($global:testCase -ne 'notElevated') }
    return $principal
}
function Get-LocalGroupMember {
    param($SID, $ErrorAction)
    if ($SID -ne 'S-1-5-32-544') { throw 'Unexpected group identifier' }
    $global:testReads++
    if ($global:testCase -eq 'readFailure' -or ($global:testCase -eq 'verifyFailure' -and $global:testReads -gt 1)) { throw 'Simulated read failure' }
    return $global:testMembers
}
function Remove-LocalGroupMember {
    param($SID, $Member, $Confirm, $ErrorAction)
    if ($SID -ne 'S-1-5-32-544' -or $Member -ne 'S-1-12-1-111-222-333-444') { throw 'Unexpected removal target' }
    if ($global:testCase -eq 'removeFailure') { throw 'Simulated removal failure' }
    $global:testRemovals += $Member
    if ($global:testCase -ne 'silentFailure') {
        $global:testMembers = @($global:testMembers | Where-Object { $_.SID.Value -ne $Member })
    }
}
function New-Item { param($Path, $ItemType, $ErrorAction, [switch]$Force); $global:testWrites++ }
function Add-Content {
    param($LiteralPath, $Value, $Encoding, $ErrorAction)
    $global:testWrites++
    if ($global:testCase -eq 'logFailure') { throw 'Simulated log failure' }
}

$arguments = @{}
if ($Kind -eq 'Detect') { $arguments.DeploymentType = $DeploymentType }
if ($Scenario -eq 'excluded') { $arguments.ExcludedMemberSids = @('S-1-12-1-111-222-333-444') }
if ($Scenario -eq 'invalidExclusion') { $arguments.ExcludedMemberSids = @('not-a-sid') }
if ($Scenario -eq 'preview' -and $Kind -eq 'Invoke') { $arguments.WhatIf = $true }
$target = Join-Path $repo "scripts\$Kind-LocalAdminCleanup.ps1"
$output = & $target @arguments
$actualExit = $LASTEXITCODE
$expectedRemovals = 0
if ($Kind -eq 'Detect') {
    $expectedExit = 1
    if ($Scenario -in @('clean','excluded','localSameName','empty')) { $expectedExit = 0 }
    if ($DeploymentType -eq 'Remediation' -and $Scenario -in @('readFailure','missingSid','invalidExclusion')) { $expectedExit = 2 }
}
else {
    $expectedExit = 0
    if ($Scenario -in @('readFailure','verifyFailure','removeFailure','silentFailure','missingSid','invalidExclusion','logFailure','notElevated')) { $expectedExit = 1 }
    if ($Scenario -in @('mixed','caseInsensitive','single','verifyFailure','silentFailure')) { $expectedRemovals = 1 }
}
if ($Kind -eq 'Detect' -and $actualExit -eq 0 -and [string]::IsNullOrWhiteSpace(($output -join ''))) { throw 'Win32 detection requires nonempty stdout on success' }
if ($actualExit -ne $expectedExit) { throw "Expected exit $expectedExit, got $actualExit. $output" }
if ($global:testRemovals.Count -ne $expectedRemovals) { throw "Unexpected removals: $($global:testRemovals.Count), expected $expectedRemovals" }
if (($Kind -eq 'Detect' -or $Scenario -eq 'preview') -and $global:testWrites -gt 0) { throw 'Read-only execution attempted file writes' }
if ($Scenario -notin @('single','empty') -and -not ($global:testMembers | Where-Object { $_.Name -eq 'DEVICE\RecoveryAdmin' })) { throw 'Local recovery account was not preserved' }
Write-Output "PASS: $Kind / $Scenario"
exit 0
