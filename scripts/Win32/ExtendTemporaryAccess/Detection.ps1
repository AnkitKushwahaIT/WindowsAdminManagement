#requires -Version 5.1
# ==========================================
# Extend Temporary Access - Detection
# Intune Win32 app / SYSTEM / 64-bit PowerShell
# ==========================================

# Configuration - keep values identical in Install.ps1 and Detection.ps1.
$AppVersion = '1.0.0'
$PackageName = 'ExtendTemporaryAccess'
# Use an absolute UTC expiry, such as 2030-01-10T17:00:00Z, in your PRIVATE copy.
$TargetUserSid = ''
$RequestId = ''
$NewExpiryUtc = ''
$LogFolder = 'C:\CompanyIT'
$LogFile = Join-Path $LogFolder "ExtendTemporaryAccess.log"
$StateFolder = Join-Path $env:ProgramData 'WindowsAdminManagement\Win32\ExtendTemporaryAccess'
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$Policy = [ordered]@{ Package=$PackageName; Version=$AppVersion; TargetUserSid=$TargetUserSid; RequestId=$RequestId; NewExpiryUtc=$NewExpiryUtc }

# ==========================================
# Logging
# ==========================================
function Write-Log {
    param([string]$Message)
    $TimeStamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -LiteralPath $LogFile -Value "$TimeStamp - $Message" -Encoding UTF8 -ErrorAction Stop
}

# ==========================================
# Common checks and local report state
# ==========================================
function Assert-Context {
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { throw 'Run in 64-bit Windows PowerShell.' }
    $Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $Principal = New-Object Security.Principal.WindowsPrincipal($Identity)
    if (-not $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run elevated or as SYSTEM.' }
    Import-Module Microsoft.PowerShell.LocalAccounts -ErrorAction Stop
}
function Assert-Sids {
    param([string[]]$Values)
    foreach ($Value in $Values) {
        if ([string]::IsNullOrWhiteSpace($Value)) { throw 'Empty SID in configuration.' }
        $Parsed = [Security.Principal.SecurityIdentifier]::new($Value)
        if ($Parsed.Value -ne $Value) { throw 'Use canonical SID strings in configuration.' }
    }
}
function Get-PolicyHash {
    $Json = $Policy | ConvertTo-Json -Depth 8 -Compress
    $Hasher = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($Hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes($Json)))).Replace('-', '') }
    finally { $Hasher.Dispose() }
}
function Assert-PlainPath {
    param([string]$Path)
    $Current = $Path
    while ($Current) {
        if (Test-Path -LiteralPath $Current) {
            if ((Get-Item -LiteralPath $Current -Force -ErrorAction Stop).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'State path contains a reparse point; investigate before continuing.' }
        }
        $Parent = Split-Path -Parent $Current
        if ($Parent -eq $Current) { break }
        $Current = $Parent
    }
}
function Initialize-State {
    Assert-PlainPath $StateFolder
    if (Test-Path -LiteralPath $StateFolder) {
        $Owner = (Get-Acl -LiteralPath $StateFolder -ErrorAction Stop).GetOwner([Security.Principal.SecurityIdentifier]).Value
        $Caller = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        if ($Owner -notin @('S-1-5-18', 'S-1-5-32-544', $Caller)) { throw 'State folder has an unexpected owner.' }
    }
    New-Item -Path $StateFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
    $Acl = [Security.AccessControl.DirectorySecurity]::new()
    $Acl.SetAccessRuleProtection($true, $false)
    $Acl.SetOwner([Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'))
    foreach ($Sid in @('S-1-5-18','S-1-5-32-544')) {
        $Rule = [Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($Sid), 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
        $Acl.AddAccessRule($Rule)
    }
    Set-Acl -LiteralPath $StateFolder -AclObject $Acl -ErrorAction Stop
}
function Write-StateJson {
    param([string]$Path, [object]$Value)
    Assert-PlainPath $Path
    $Temporary = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Temporary -Encoding UTF8 -ErrorAction Stop
        Move-Item -LiteralPath $Temporary -Destination $Path -Force -ErrorAction Stop
    }
    finally {
        if (Test-Path -LiteralPath $Temporary) { Remove-Item -LiteralPath $Temporary -Force -ErrorAction Stop }
    }
}
function Write-Report {
    param([object]$Data)
    Write-StateJson $ReportFile ([ordered]@{ Package=$PackageName; Version=$AppVersion; GeneratedUtc=[datetime]::UtcNow.ToString('o'); Data=$Data })
    Write-Log "Report saved: $ReportFile"
}
function Save-Receipt {
    $Hash = (Get-FileHash -LiteralPath $ReportFile -Algorithm SHA256 -ErrorAction Stop).Hash
    Write-StateJson $ReceiptFile ([ordered]@{ Package=$PackageName; Version=$AppVersion; PolicyHash=(Get-PolicyHash); CompletedUtc=[datetime]::UtcNow.ToString('o'); ReportHash=$Hash })
}
function Read-Receipt {
    Assert-PlainPath $ReceiptFile
    if (-not (Test-Path -LiteralPath $ReceiptFile -PathType Leaf)) { throw 'No successful run recorded for this configuration.' }
    $Receipt = Get-Content -LiteralPath $ReceiptFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if ($Receipt.Package -ne $PackageName -or $Receipt.Version -ne $AppVersion -or $Receipt.PolicyHash -ne (Get-PolicyHash)) { throw 'Saved receipt does not match the configured package or request.' }
    Assert-PlainPath $ReportFile
    if ((Get-FileHash -LiteralPath $ReportFile -Algorithm SHA256 -ErrorAction Stop).Hash -ne $Receipt.ReportHash) { throw 'Saved report is missing or changed.' }
    return $Receipt
}
function Test-FreshReport {
    $Receipt = Read-Receipt
    $Completed = [datetimeoffset]::Parse($Receipt.CompletedUtc).UtcDateTime
    $Age = ([datetime]::UtcNow - $Completed).TotalHours
    if ($Age -lt 0 -or $Age -ge $ReportMaxAgeHours) { throw 'Report is stale or its timestamp is invalid.' }
}
function Get-Members {
    param([string]$GroupSid = 'S-1-5-32-544')
    $Members = @(Get-LocalGroupMember -SID $GroupSid -ErrorAction Stop)
    foreach ($Member in $Members) {
        if (-not $Member.SID) { throw 'Membership inventory contains an entry without a SID.' }
        [pscustomobject]@{ Name=$Member.Name; SID=$Member.SID.Value; ObjectClass=[string]$Member.ObjectClass; Source=[string]$Member.PrincipalSource }
    }
}

# ==========================================
# Existing temporary-grant task checks
# Compatible with Grant-TemporaryLocalAdmin.ps1
# ==========================================
function Get-RemovalTask {
    param([string]$Sid, [switch]$AllowExpired)
    Import-Module ScheduledTasks -ErrorAction Stop
    $Name = "TempAdminRemoval_$Sid"
    $FoundTasks = @(Get-ScheduledTask -TaskPath '\' -ErrorAction Stop | Where-Object { $_.TaskName -eq $Name })
    if ($FoundTasks.Count -ne 1) { throw "Expected one removal task for $Sid." }
    $Task = $FoundTasks[0]
    if ($Task.Principal.UserId -notin @('SYSTEM','S-1-5-18','NT AUTHORITY\SYSTEM') -or [string]$Task.Principal.RunLevel -ne 'Highest') { throw 'Removal task must run as SYSTEM with highest privileges.' }
    if (-not $Task.Settings.Enabled -or [string]$Task.State -eq 'Disabled') { throw 'Removal task is disabled.' }
    $Triggers = @($Task.Triggers)
    if ($Triggers.Count -ne 1 -or -not $Triggers[0].Enabled -or $Triggers[0].DaysInterval -ne 1) { throw 'Removal task must have one enabled daily trigger.' }
    $Expiry = [datetimeoffset]::Parse($Triggers[0].StartBoundary)
    if (-not $AllowExpired -and $Expiry.UtcDateTime -le [datetime]::UtcNow) { throw 'Temporary grant has expired.' }
    if (-not $Task.Settings.StartWhenAvailable) { throw 'Removal task cannot catch up after a missed run.' }
    $Actions = @($Task.Actions)
    $ExpectedExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if ($Actions.Count -ne 1 -or $Actions[0].Execute -ne $ExpectedExe -or $Actions[0].Arguments -notmatch '(?i)-EncodedCommand\s+([A-Za-z0-9+/=]+)\s*$') { throw 'Unexpected removal task action.' }
    $Payload = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($Matches[1]))
    $ExpectedSid = '$UserSid = ''' + $Sid + ''''
    $ExpectedTask = '$TaskName = ''' + $Name + ''''
    if (-not $Payload.Contains($ExpectedSid) -or -not $Payload.Contains($ExpectedTask) -or -not $Payload.Contains("Remove-LocalGroupMember -SID 'S-1-5-32-544' -Member " + '$UserSid') -or -not $Payload.Contains('Unregister-ScheduledTask')) { throw 'Removal task does not match this repository grant format.' }
    [pscustomobject]@{ Task=$Task; Name=$Name; Expiry=$Expiry }
}
function Get-TemporaryStatus {
    param([object[]]$Members, [string[]]$PermanentSids = @())
    foreach ($Member in $Members) {
        if ($Member.Name -match '^AzureAD\\' -and $Member.ObjectClass -eq 'User' -and $PermanentSids -notcontains $Member.SID) {
            try {
                $Removal = Get-RemovalTask $Member.SID
                [pscustomobject]@{ SID=$Member.SID; Name=$Member.Name; Valid=$true; ExpiryUtc=$Removal.Expiry.UtcDateTime.ToString('o'); Reason='Valid temporary removal task' }
            }
            catch {
                [pscustomobject]@{ SID=$Member.SID; Name=$Member.Name; Valid=$false; ExpiryUtc=$null; Reason=$_.Exception.Message }
            }
        }
    }
}

# ==========================================
# Intune custom detection
# ==========================================
try {
    Assert-Context
    New-Item -Path $LogFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
    Write-Log '========== Detection Started =========='
    Assert-Sids @($TargetUserSid)
    if ($TargetUserSid -notmatch '^S-1-12-1-\d+-\d+-\d+-\d+$') { throw 'Configure the exact Entra user SID.' }
    if ($RequestId -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$') { throw 'Configure a unique RequestId.' }
    if ($NewExpiryUtc -notmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$') { throw 'NewExpiryUtc must use YYYY-MM-DDTHH:MM:SSZ.' }
    $RequestedExpiry = [datetimeoffset]::ParseExact($NewExpiryUtc, "yyyy-MM-dd'T'HH:mm:ss'Z'", [cultureinfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal)
    Import-Module ScheduledTasks -ErrorAction Stop
    $ReportFile = Join-Path $StateFolder "Report-$RequestId.json"
    $ReceiptFile = Join-Path $StateFolder "Receipt-$RequestId.json"
    # Historical completion prevents Required assignment from renewing expired access.
    $null = Read-Receipt
    Write-Log '========== Detection Completed Successfully =========='
    Write-Output 'Detected: Extend Temporary Access.'
    exit 0
}
catch {
    $Failure = $_.Exception.Message
    try { Write-Log "ERROR: $Failure" } catch { }
    Write-Output ('Not detected: ' + $Failure.Substring(0, [Math]::Min(1200, $Failure.Length)))
    exit 1
}

