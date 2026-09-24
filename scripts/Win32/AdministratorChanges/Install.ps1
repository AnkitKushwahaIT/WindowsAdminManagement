#requires -Version 5.1
# ==========================================
# Administrator Membership Change Report - Install
# Intune Win32 app / SYSTEM / 64-bit PowerShell
# ==========================================

# Configuration - keep values identical in Install.ps1 and Detection.ps1.
$AppVersion = '1.0.0'
$PackageName = 'AdministratorChanges'
$ReportMaxAgeHours = 24
$LogFolder = 'C:\CompanyIT'
$LogFile = Join-Path $LogFolder "AdministratorChanges.log"
$StateFolder = Join-Path $env:ProgramData 'WindowsAdminManagement\Win32\AdministratorChanges'
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$Policy = [ordered]@{ Package=$PackageName; Version=$AppVersion; ReportMaxAgeHours=$ReportMaxAgeHours }

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
# Action and verification
# ==========================================
try {
    Assert-Context
    New-Item -Path $LogFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
    Write-Log '========== Install Started =========='
    if ($ReportMaxAgeHours -lt 1) { throw 'ReportMaxAgeHours must be at least 1.' }
    $ReportFile = Join-Path $StateFolder 'Report.json'
    $ReceiptFile = Join-Path $StateFolder 'Receipt.json'
    Initialize-State
    $Current = @(Get-Members)
    $BaselineFile = Join-Path $StateFolder 'Baseline.json'
    Assert-PlainPath $BaselineFile
    $FirstRun = -not (Test-Path -LiteralPath $BaselineFile)
    $Previous = @()
    if (-not $FirstRun) {
        $Baseline = Get-Content -LiteralPath $BaselineFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ($Baseline.Schema -ne 1 -or $null -eq $Baseline.Members) { throw 'Baseline is invalid; refusing to silently replace it.' }
        $Previous = @($Baseline.Members)
        foreach ($Member in $Previous) { Assert-Sids @($Member.SID) }
    }
    $Added = @(); $Removed = @()
    if (-not $FirstRun) {
        $PreviousSids = @($Previous | ForEach-Object { $_.SID })
        $CurrentSids = @($Current | ForEach-Object { $_.SID })
        $Added = @($Current | Where-Object { $PreviousSids -notcontains $_.SID })
        $Removed = @($Previous | Where-Object { $CurrentSids -notcontains $_.SID })
    }
    $Data = [ordered]@{ BaselineCreated=$FirstRun; Added=$Added; Removed=$Removed; Current=$Current }
    # Retain each successful comparison in history before advancing the baseline.
    $HistoryFile = Join-Path $StateFolder ("Changes-{0}-{1}.json" -f [datetime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ'), [guid]::NewGuid().ToString('N'))
    Write-StateJson $HistoryFile $Data
    Write-Report $Data
    foreach ($Member in $Added) { Write-Log "ADDED: $($Member.Name) [$($Member.SID)]" }
    foreach ($Member in $Removed) { Write-Log "REMOVED: $($Member.Name) [$($Member.SID)]" }
    Write-StateJson $BaselineFile ([ordered]@{ Schema=1; Members=$Current })
    Write-Log "BaselineCreated=$FirstRun; Added=$($Added.Count); Removed=$($Removed.Count)"
    Save-Receipt
    Write-Log '========== Install Completed Successfully =========='
    exit 0
}
catch {
    $Failure = $_.Exception.Message
    try { Write-Log "ERROR: $Failure" } catch { }
    exit 1
}
