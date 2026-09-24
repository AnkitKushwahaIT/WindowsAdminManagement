#requires -Version 5.1
# ==========================================
# Remote Desktop Users Membership - Install
# Intune Win32 app / SYSTEM / 64-bit PowerShell
# ==========================================

# Configuration - keep values identical in Install.ps1 and Detection.ps1.
$AppVersion = '1.0.0'
$PackageName = 'RemoteDesktopMembership'
# Explicit additions/removals only; unrelated members are preserved.
$MemberSidsToAdd = @()
$MemberSidsToRemove = @()
$LogFolder = 'C:\CompanyIT'
$LogFile = Join-Path $LogFolder "RemoteDesktopMembership.log"
$StateFolder = Join-Path $env:ProgramData 'WindowsAdminManagement\Win32\RemoteDesktopMembership'
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$Policy = [ordered]@{ Package=$PackageName; Version=$AppVersion; MemberSidsToAdd=$MemberSidsToAdd; MemberSidsToRemove=$MemberSidsToRemove }

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
function Test-RdpMembership {
    $Members = @(Get-Members -GroupSid 'S-1-5-32-555')
    $Sids = @($Members | ForEach-Object { $_.SID })
    foreach ($Sid in $MemberSidsToAdd) { if ($Sids -notcontains $Sid) { throw 'A configured Remote Desktop Users addition is missing.' } }
    foreach ($Sid in $MemberSidsToRemove) { if ($Sids -contains $Sid) { throw 'A configured Remote Desktop Users removal remains.' } }
}

# ==========================================
# Action and verification
# ==========================================
try {
    Assert-Context
    New-Item -Path $LogFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
    Write-Log '========== Install Started =========='
    if ($MemberSidsToAdd.Count -eq 0 -and $MemberSidsToRemove.Count -eq 0) { throw 'Configure at least one addition or removal in both scripts.' }
    Assert-Sids $MemberSidsToAdd
    Assert-Sids $MemberSidsToRemove
    if (@($MemberSidsToAdd | Where-Object { $MemberSidsToRemove -contains $_ }).Count) { throw 'A SID cannot be in both lists.' }
    $ReportFile = Join-Path $StateFolder 'Report.json'
    $ReceiptFile = Join-Path $StateFolder 'Receipt.json'
    Initialize-State
    $Before = @(Get-Members -GroupSid 'S-1-5-32-555')
    $Sids = @($Before | ForEach-Object { $_.SID })
    foreach ($Sid in $MemberSidsToAdd | Select-Object -Unique) {
        if ($Sids -notcontains $Sid) { Write-Log "Adding Remote Desktop Users member: $Sid"; Add-LocalGroupMember -SID 'S-1-5-32-555' -Member $Sid -ErrorAction Stop }
    }
    foreach ($Sid in $MemberSidsToRemove | Select-Object -Unique) {
        if ($Sids -contains $Sid) { Write-Log "Removing Remote Desktop Users member: $Sid"; Remove-LocalGroupMember -SID 'S-1-5-32-555' -Member $Sid -Confirm:$false -ErrorAction Stop }
    }
    Test-RdpMembership
    $After = @(Get-Members -GroupSid 'S-1-5-32-555')
    Write-Report ([ordered]@{ Before=$Before; After=$After })
    Save-Receipt
    Write-Log '========== Install Completed Successfully =========='
    Write-Output 'Completed: Remote Desktop Users Membership.'
    exit 0
}
catch {
    $Failure = $_.Exception.Message
    try { Write-Log "ERROR: $Failure" } catch { }
    Write-Output ('Failed: ' + $Failure.Substring(0, [Math]::Min(1200, $Failure.Length)))
    exit 1
}
