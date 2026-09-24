#requires -Version 5.1
param([switch]$Child,[string]$Case)
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$source=Join-Path $repo 'scripts/TemporaryAdmin/Grant-TemporaryLocalAdmin.ps1'
if (-not $Child) {
    $tokens=$null; $errors=$null
    $null=[Management.Automation.Language.Parser]::ParseFile($source,[ref]$tokens,[ref]$errors)
    if ($errors.Count) { throw ($errors | Out-String) }
    $cases=@('grant','noUser','multipleUsers','localUser','ownerFailure','readFailure','existingAdmin','existingTask','taskFailure','addFailure','silentAddFailure','logFailure','remove','removeAbsent','removeFailure','removeReadFailure','removeSilentFailure','removeLogFailure')
    foreach ($c in $cases) {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -Child -Case $c
        if ($LASTEXITCODE) { throw "FAIL: $c" }
    }
    Write-Output "PASS: syntax and $($cases.Count) temporary-admin checks. No real changes."
    exit 0
}
$global:testCase=$Case
$global:removalPhase=$false
$global:testSid='S-1-12-1-111-222-333-444'
$global:memberPresent=($Case -eq 'existingAdmin')
$global:registered=$false; $global:unregistered=$false; $global:added=0
$global:payload=''
function New-Object { $p=[pscustomobject]@{}; $p | Add-Member ScriptMethod IsInRole {param($role) $true}; $p }
function Import-Module { param($Name,$ErrorAction) }
function New-Item { param($Path,$ItemType,[switch]$Force,$ErrorAction) }
function Add-Content { param($LiteralPath,$Value,$ErrorAction); if ($global:testCase -eq 'logFailure' -or ($global:removalPhase -and $global:testCase -eq 'removeLogFailure')) { throw 'Simulated log failure' } }
function Get-Process {
    param($Name,[switch]$IncludeUserName,$ErrorAction)
    if ($global:testCase -eq 'noUser') { return }
    if ($global:testCase -eq 'localUser') { return [pscustomobject]@{Id=123;UserName='DEVICE\LocalUser'} }
    [pscustomobject]@{Id=123;UserName='AzureAD\ExampleUser'}
    if ($global:testCase -eq 'multipleUsers') { [pscustomobject]@{Id=124;UserName='AzureAD\OtherUser'} }
}
function Get-CimInstance { param($ClassName,$Filter,$ErrorAction); [pscustomobject]@{ProcessId=123} }
function Invoke-CimMethod { param($InputObject,$MethodName,$ErrorAction); $result=0; if ($global:testCase -eq 'ownerFailure') {$result=2}; [pscustomobject]@{ReturnValue=$result;Sid=$global:testSid} }
function Get-LocalGroupMember {
    param($SID,$ErrorAction)
    if ($global:testCase -eq 'readFailure' -or ($global:removalPhase -and $global:testCase -eq 'removeReadFailure')) { throw 'Simulated membership read failure' }
    if ($global:memberPresent) { [pscustomobject]@{SID=[pscustomobject]@{Value=$global:testSid};Name='AzureAD\ExampleUser'} }
}
function Get-ScheduledTask { param($TaskPath,$ErrorAction); if ($global:testCase -eq 'existingTask') { [pscustomobject]@{TaskName="TempAdminRemoval_$global:testSid"} } }
function New-ScheduledTaskAction {
    param($Execute,$Argument)
    if ($Execute -notlike '*System32\WindowsPowerShell\v1.0\powershell.exe') { throw 'Unexpected executable' }
    $encoded=($Argument -split ' ')[-1]
    $global:payload=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($encoded))
    $t=$null; $e=$null; $null=[Management.Automation.Language.Parser]::ParseInput($global:payload,[ref]$t,[ref]$e)
    if ($e.Count) { throw 'Invalid scheduled removal payload' }
    [pscustomobject]@{Arguments=$Argument}
}
function New-ScheduledTaskTrigger { param([switch]$Daily,$DaysInterval,$At); if (-not $Daily -or $DaysInterval -ne 1 -or $At -lt (Get-Date).AddDays(4.99)) { throw 'Invalid expiry' }; [pscustomobject]@{StartBoundary=$At} }
function New-ScheduledTaskPrincipal { param($UserId,$LogonType,$RunLevel); if ($UserId -ne 'SYSTEM') {throw 'Not SYSTEM'}; [pscustomobject]@{} }
function New-ScheduledTaskSettingsSet {
    param([switch]$StartWhenAvailable,[switch]$AllowStartIfOnBatteries,[switch]$DontStopIfGoingOnBatteries,$RestartCount,$RestartInterval,$ExecutionTimeLimit,$MultipleInstances)
    if (-not $StartWhenAvailable -or $RestartCount -ne 3) { throw 'Missing retry settings' }; [pscustomobject]@{}
}
function Register-ScheduledTask { param($TaskName,$TaskPath,$Action,$Trigger,$Principal,$Settings,$Description,$ErrorAction); if ($global:testCase -eq 'taskFailure') {throw 'Simulated task failure'}; $global:registered=$true }
function Add-LocalGroupMember {
    param($SID,$Member,$ErrorAction)
    if (-not $global:registered) {throw 'Grant occurred before task registration'}
    if ($global:testCase -eq 'addFailure') {throw 'Simulated addition failure'}
    $global:added++
    if ($global:testCase -ne 'silentAddFailure') {$global:memberPresent=$true}
}
function Remove-LocalGroupMember {
    param($SID,$Member,$Confirm,$ErrorAction)
    if ($Member -ne $global:testSid) {throw 'Incorrect removal SID'}
    if ($global:testCase -eq 'removeFailure') {throw 'Simulated removal failure'}
    if ($global:testCase -ne 'removeSilentFailure') {$global:memberPresent=$false}
}
function Unregister-ScheduledTask { param($TaskName,$TaskPath,$Confirm,$ErrorAction); if ($global:memberPresent) {throw 'Task removed before verified removal'}; $global:unregistered=$true }
$output=& $source
$exitCode=$LASTEXITCODE
if ($Case -like 'remove*') {
    if ($exitCode -ne 0 -or -not $global:registered) {throw "Grant setup failed: $output"}
    $global:removalPhase=$true
    if ($Case -eq 'removeAbsent') {$global:memberPresent=$false}
    $fixture=Join-Path ([IO.Path]::GetTempPath()) ('removal-test-' + [guid]::NewGuid() + '.ps1')
    [IO.File]::WriteAllText($fixture,$global:payload)
    try {$output=& $fixture; $exitCode=$LASTEXITCODE} finally {[IO.File]::Delete($fixture)}
    $expected=1
    if ($Case -in @('remove','removeAbsent')) {$expected=0}
    if ($exitCode -ne $expected -or $global:unregistered -ne ($expected -eq 0)) {throw "Removal assertion failed: $output"}
}
else {
    $expected=1
    if ($Case -in @('grant','existingAdmin')) {$expected=0}
    if ($exitCode -ne $expected) {throw "Expected $expected got $exitCode : $output"}
    if ($Case -notin @('grant','addFailure','silentAddFailure') -and ($global:registered -or $global:added)) {throw 'Unexpected task or grant'}
    if ($Case -eq 'grant' -and ($global:added -ne 1 -or -not $global:memberPresent)) {throw 'Grant not verified'}
}
Write-Output "PASS: $Case"
exit 0
