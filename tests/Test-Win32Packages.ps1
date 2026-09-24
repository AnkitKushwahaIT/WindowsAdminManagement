#requires -Version 5.1
param([switch]$Child, [string]$Package, [string]$Case)
$ErrorActionPreference = 'Stop'
$Repo = Split-Path -Parent $PSScriptRoot
if (-not $Child) {
    foreach ($File in Get-ChildItem (Join-Path $Repo 'scripts/Win32') -Recurse -Filter *.ps1) {
        $Tokens=$null; $Errors=$null
        $null=[Management.Automation.Language.Parser]::ParseFile($File.FullName,[ref]$Tokens,[ref]$Errors)
        if ($Errors.Count) { throw ($Errors | Out-String) }
    }
    $Matrix = [ordered]@{
        AdministratorAudit=@('healthy','stale','missingReport','changedReport','readFailure','logFailure')
        ApprovedAdministratorCheck=@('healthy','expiredTask','missingTask','disabledTask','wrongAction','unauthorizedLocal','readFailure','emptyConfig')
        TemporaryAccessCheck=@('healthy','expiredTask','missingTask','disabledTask','wrongAction','noEntraUser','readFailure')
        RevokeTemporaryAccess=@('healthy','replay','missingTask','removeFailure','silentRemoveFailure','unregisterFailure','invalidSid','unrelatedGroup')
        ExtendTemporaryAccess=@('healthy','replay','expiredTask','missingTask','pastExpiry','shorterExpiry','setFailure','silentSetFailure','requestChanged','runningTask')
        BreakGlassHealth=@('healthy','missingUser','disabledUser','notAdmin','readFailure')
        AdministratorChanges=@('healthy','changes','emptyBaseline','corruptBaseline','stale','readFailure')
        RemoteDesktopMembership=@('healthy','drift','overlap','emptyConfig','addFailure','removeFailure','silentRemoveFailure','readFailure')
    }
    $Count=0
    foreach ($Name in $Matrix.Keys) {
        foreach ($Scenario in $Matrix[$Name]) {
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -Child -Package $Name -Case $Scenario
            if ($LASTEXITCODE -ne 0) { throw "FAILED: $Name / $Scenario" }
            $Count++
        }
    }
    Write-Output "PASS: syntax and $Count Win32 package scenarios. Account and task operations were simulated."
    exit 0
}

# Real report/receipt IO is confined to an isolated temporary directory.
# Windows membership, scheduling and ACL mutations are mocked below.
$TestRoot = Join-Path ([IO.Path]::GetTempPath()) ('wam-tests-' + [guid]::NewGuid().ToString('N'))
New-Item -Path $TestRoot -ItemType Directory | Out-Null
$env:ProgramData = Join-Path $TestRoot 'ProgramData'
$global:Scenario=$Case
$global:CloudSid='S-1-12-1-111-222-333-444'
$global:LocalSid='S-1-5-21-1-2-3-1001'
$global:OtherSid='S-1-5-21-1-2-3-1002'
function New-TestMember($Name,$Sid,$Class='User',$Source='Local') {
    [pscustomobject]@{ Name=$Name; SID=[pscustomobject]@{Value=$Sid}; ObjectClass=$Class; PrincipalSource=$Source }
}
$global:Cloud=New-TestMember 'AzureAD\ExampleUser' $global:CloudSid 'User' 'AzureAD'
$global:Local=New-TestMember 'DEVICE\LocalAdmin' $global:LocalSid
$global:Other=New-TestMember 'DEVICE\OtherUser' $global:OtherSid
$global:Admins=@($global:Cloud,$global:Local)
$global:Rdp=@($global:Other)
$global:User=[pscustomobject]@{Name='LocalAdmin';SID=[pscustomobject]@{Value=$global:LocalSid};Enabled=$true}
$Payload = '$UserSid = ''' + $global:CloudSid + "'`n" + '$TaskName = ''TempAdminRemoval_' + $global:CloudSid + "'`n" + 'Remove-LocalGroupMember -SID ''S-1-5-32-544'' -Member $UserSid' + "`n" + 'Unregister-ScheduledTask'
$global:RemovalTask=[pscustomobject]@{
    TaskName="TempAdminRemoval_$global:CloudSid"; State='Ready'
    Principal=[pscustomobject]@{UserId='SYSTEM';RunLevel='Highest'}
    Settings=[pscustomobject]@{Enabled=$true;StartWhenAvailable=$true}
    Triggers=@([pscustomobject]@{Enabled=$true;DaysInterval=1;StartBoundary=[datetime]::UtcNow.AddDays(2).ToString('o')})
    Actions=@([pscustomobject]@{Execute=(Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe');Arguments=('-EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Payload)))})
}
$global:Changes=0
switch ($Case) {
    'expiredTask' {$global:RemovalTask.Triggers[0].StartBoundary=[datetime]::UtcNow.AddDays(-1).ToString('o')}
    'missingTask' {$global:RemovalTask=$null}
    'disabledTask' {$global:RemovalTask.Settings.Enabled=$false}
    'wrongAction' {$global:RemovalTask.Actions[0].Execute='unexpected.exe'}
    'runningTask' {$global:RemovalTask.State='Running'}
    'unauthorizedLocal' {$global:Admins += $global:Other}
    'noEntraUser' {$global:Admins=@($global:Local)}
    'missingUser' {$global:User=$null}
    'disabledUser' {$global:User.Enabled=$false}
    'notAdmin' {$global:Admins=@($global:Cloud)}
    'emptyBaseline' {$global:Admins=@()}
    'unrelatedGroup' {$global:Cloud.ObjectClass='Group'}
}
function Import-Module {param($Name,$ErrorAction)}
function New-Object {
    $Principal=[pscustomobject]@{}
    $Principal | Add-Member ScriptMethod IsInRole {param($Role) $true}
    $Principal
}
function Set-Acl {param($LiteralPath,$AclObject,$ErrorAction)}
function Add-Content {
    param($LiteralPath,$Value,$Encoding,$ErrorAction)
    if ($global:Scenario -eq 'logFailure') {throw 'Simulated log write failure'}
    Microsoft.PowerShell.Management\Add-Content -LiteralPath $LiteralPath -Value $Value -Encoding UTF8 -ErrorAction Stop
}
function Get-LocalGroupMember {
    param($SID,$ErrorAction)
    if ($global:Scenario -eq 'readFailure') {throw 'Simulated enumeration failure'}
    if ($SID -eq 'S-1-5-32-544') {return $global:Admins}
    if ($SID -eq 'S-1-5-32-555') {return $global:Rdp}
    throw 'Unexpected group SID'
}
function Get-LocalUser {param($ErrorAction); if ($global:User) {$global:User}}
function Add-LocalGroupMember {
    param($SID,$Member,$ErrorAction)
    if ($global:Scenario -eq 'addFailure') {throw 'Simulated add failure'}
    if ($SID -ne 'S-1-5-32-555' -or $Member -ne $global:CloudSid) {throw 'Unexpected addition'}
    $global:Changes++; $global:Rdp += $global:Cloud
}
function Remove-LocalGroupMember {
    param($SID,$Member,$Confirm,$ErrorAction)
    if ($global:Scenario -eq 'removeFailure') {throw 'Simulated removal failure'}
    $global:Changes++
    if ($global:Scenario -eq 'silentRemoveFailure') {return}
    if ($SID -eq 'S-1-5-32-544' -and $Member -eq $global:CloudSid) {$global:Admins=@($global:Admins | Where-Object {$_.SID.Value -ne $Member}); return}
    if ($SID -eq 'S-1-5-32-555' -and $Member -eq $global:OtherSid) {$global:Rdp=@($global:Rdp | Where-Object {$_.SID.Value -ne $Member}); return}
    throw 'Unexpected removal'
}
function Get-ScheduledTask {param($TaskPath,$ErrorAction); if ($global:RemovalTask) {$global:RemovalTask}}
function Unregister-ScheduledTask {
    param($TaskName,$TaskPath,$Confirm,$ErrorAction)
    if ($global:Scenario -eq 'unregisterFailure') {throw 'Simulated task removal failure'}
    if (@($global:Admins | Where-Object {$_.SID.Value -eq $global:CloudSid}).Count) {throw 'Task removal occurred before membership removal'}
    $global:Changes++; $global:RemovalTask=$null
}
function New-ScheduledTaskTrigger {param([switch]$Daily,$DaysInterval,$At); [pscustomobject]@{Enabled=$true;DaysInterval=$DaysInterval;StartBoundary=$At.ToString('o')}}
function Set-ScheduledTask {
    param($TaskName,$TaskPath,$Trigger,$Description,$ErrorAction)
    if ($global:Scenario -eq 'setFailure') {throw 'Simulated task update failure'}
    $global:Changes++
    if ($global:Scenario -ne 'silentSetFailure') {$global:RemovalTask.Triggers=@($Trigger)}
}

try {
    $Future=[datetime]::UtcNow.AddDays(4).ToString('yyyy-MM-ddTHH:mm:ssZ')
    if ($Case -eq 'pastExpiry') {$Future=[datetime]::UtcNow.AddDays(-1).ToString('yyyy-MM-ddTHH:mm:ssZ')}
    if ($Case -eq 'shorterExpiry') {$Future=[datetime]::UtcNow.AddDays(1).ToString('yyyy-MM-ddTHH:mm:ssZ')}
    foreach ($Action in @('Install','Detection')) {
        $Text=[IO.File]::ReadAllText((Join-Path $Repo "scripts/Win32/$Package/$Action.ps1"))
        $Text=$Text.Replace("'C:\CompanyIT'", "'"+(Join-Path $TestRoot 'Logs').Replace("'","''")+"'")
        if ($Case -ne 'emptyConfig') {
            $Text=$Text.Replace('$ApprovedAdminSids = @()', '$ApprovedAdminSids = @('''+$global:LocalSid+''')')
            $Text=$Text.Replace('$MemberSidsToAdd = @()', '$MemberSidsToAdd = @('''+$global:CloudSid+''')')
            $RemoveSid=$global:OtherSid
            if ($Case -eq 'overlap') {$RemoveSid=$global:CloudSid}
            $Text=$Text.Replace('$MemberSidsToRemove = @()', '$MemberSidsToRemove = @('''+$RemoveSid+''')')
        }
        $Sid=$global:CloudSid
        if ($Case -eq 'invalidSid') {$Sid='not-a-sid'}
        $Text=$Text.Replace('$TargetUserSid = ''''', '$TargetUserSid = '''+$Sid+'''')
        $Text=$Text.Replace('$RequestId = ''''', '$RequestId = ''test-request''')
        $Text=$Text.Replace('$NewExpiryUtc = ''''', '$NewExpiryUtc = '''+$Future+'''')
        [IO.File]::WriteAllText((Join-Path $TestRoot "$Action.ps1"),$Text)
    }
    $Install=Join-Path $TestRoot 'Install.ps1'; $Detect=Join-Path $TestRoot 'Detection.ps1'
    $Output=& $Install
    $Actual=$LASTEXITCODE
    $FailureCases=@('expiredTask','missingTask','disabledTask','wrongAction','unauthorizedLocal','readFailure','emptyConfig','logFailure','removeFailure','silentRemoveFailure','unregisterFailure','invalidSid','unrelatedGroup','pastExpiry','shorterExpiry','setFailure','silentSetFailure','runningTask','missingUser','disabledUser','notAdmin','overlap','addFailure')
    $Expected=0
    if ($Case -in $FailureCases) {$Expected=1}
    if ($Actual -ne $Expected) {throw "Install expected $Expected got $Actual. $Output"}
    $Receipt=Join-Path $env:ProgramData "WindowsAdminManagement/Win32/$Package/Receipt.json"
    if ($Package -in @('ExtendTemporaryAccess','RevokeTemporaryAccess')) {$Receipt=Join-Path $env:ProgramData "WindowsAdminManagement/Win32/$Package/Receipt-test-request.json"}
    if ($Expected -eq 1 -and (Test-Path -LiteralPath $Receipt)) {throw 'Failed operation wrote a successful receipt'}
    if ($Expected -eq 0) {
        $Output=& $Detect
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($Output -join ''))) {throw "Successful install not detected: $Output"}
    }
    if ($Case -eq 'replay') {
        $Before=$global:Changes
        if ($Package -eq 'RevokeTemporaryAccess') {$global:Admins += $global:Cloud}
        else {$global:Admins=@($global:Local); $global:RemovalTask=$null}
        $Output=& $Install
        if ($LASTEXITCODE -ne 0 -or $global:Changes -ne $Before) {throw 'A completed request replayed changes'}
        $Output=& $Detect
        if ($LASTEXITCODE -ne 0) {throw 'Historical completed request incorrectly failed detection'}
    }
    if ($Case -in @('stale','missingReport','changedReport','drift','requestChanged')) {
        $State=Split-Path -Parent $Receipt
        if ($Case -eq 'stale') {
            $Data=Get-Content -LiteralPath $Receipt -Raw | ConvertFrom-Json
            $Data.CompletedUtc=[datetime]::UtcNow.AddDays(-2).ToString('o')
            $Data | ConvertTo-Json | Set-Content -LiteralPath $Receipt
        }
        if ($Case -eq 'missingReport') {Remove-Item -LiteralPath (Join-Path $State 'Report.json')}
        if ($Case -eq 'changedReport') {Set-Content -LiteralPath (Join-Path $State 'Report.json') -Value '{}'}
        if ($Case -eq 'drift') {$global:Rdp=@($global:Other)}
        if ($Case -eq 'requestChanged') {
            $Text=[IO.File]::ReadAllText($Detect).Replace($Future,[datetime]::UtcNow.AddDays(6).ToString('yyyy-MM-ddTHH:mm:ssZ'))
            [IO.File]::WriteAllText($Detect,$Text)
        }
        $Output=& $Detect
        if ($LASTEXITCODE -ne 1) {throw 'Drift or changed request incorrectly detected'}
    }
    if ($Case -in @('changes','emptyBaseline','corruptBaseline')) {
        $State=Split-Path -Parent $Receipt
        if ($Case -eq 'corruptBaseline') {Set-Content -LiteralPath (Join-Path $State 'Baseline.json') -Value '{}'}
        else {$global:Admins=@($global:Other)}
        $Output=& $Install
        if ($Case -eq 'corruptBaseline') {if ($LASTEXITCODE -ne 1) {throw 'Corrupt baseline was ignored'}}
        else {
            if ($LASTEXITCODE -ne 0) {throw "Comparison failed: $Output"}
            $Data=(Get-Content -LiteralPath (Join-Path $State 'Report.json') -Raw | ConvertFrom-Json).Data
            if (@($Data.Added).Count -ne 1) {throw 'New member not reported'}
            $Removed=2; if ($Case -eq 'emptyBaseline') {$Removed=0}
            if (@($Data.Removed).Count -ne $Removed -or $Data.BaselineCreated) {throw 'Baseline comparison incorrect'}
        }
    }
    if ($Package -in @('AdministratorAudit','ApprovedAdministratorCheck','TemporaryAccessCheck','BreakGlassHealth','AdministratorChanges') -and $global:Changes) {throw 'A monitoring package modified membership or tasks'}
    Write-Output "PASS: $Package / $Case"
}
finally {
    # Verify this exact generated path stays inside the designated temp directory.
    $Full=[IO.Path]::GetFullPath($TestRoot)
    $Temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if (-not $Full.StartsWith($Temp,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path -Leaf $Full) -notlike 'wam-tests-*') {throw 'Unexpected test cleanup path'}
    Remove-Item -LiteralPath $Full -Recurse -Force
}
exit 0
