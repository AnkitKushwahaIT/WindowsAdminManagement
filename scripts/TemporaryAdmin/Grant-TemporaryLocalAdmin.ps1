#requires -Version 5.1
# ==========================================
# Temporary Local Admin Access
# Logged-in Microsoft Entra User
# ==========================================

# Configuration
$DaysToKeep = 5
$LogFolder = 'C:\CompanyIT'
$LogFile = Join-Path $LogFolder 'TempAdmin.log'
$TaskPrefix = 'TempAdminRemoval_'
$ErrorActionPreference = 'Stop'

# Logging
function Write-Log {
    param([string]$Message)
    $TimeStamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -LiteralPath $LogFile -Value "$TimeStamp - $Message" -ErrorAction Stop
}

try {
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
        throw 'Run in 64-bit Windows PowerShell.'
    }
    $Principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run elevated or as SYSTEM.'
    }
    if ($DaysToKeep -isnot [int] -or $DaysToKeep -lt 1 -or $DaysToKeep -gt 365) {
        throw 'DaysToKeep must be an integer between 1 and 365.'
    }
    New-Item -Path $LogFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
    Write-Log '========== Script Started =========='
    Import-Module Microsoft.PowerShell.LocalAccounts -ErrorAction Stop
    Import-Module ScheduledTasks -ErrorAction Stop

    # Require one distinct Explorer owner; never select an arbitrary user.
    $Sessions = @(Get-Process -Name explorer -IncludeUserName -ErrorAction Stop)
    if ($Sessions.Count -eq 0 -or @($Sessions | Where-Object { [string]::IsNullOrWhiteSpace($_.UserName) }).Count) {
        throw 'Unable to identify all Explorer session owners.'
    }
    $UserNames = @($Sessions | Select-Object -ExpandProperty UserName -Unique)
    if ($UserNames.Count -ne 1) { throw 'Multiple signed-in users found. No account was changed.' }
    $LoggedInUser = $UserNames[0]
    if ($LoggedInUser -notmatch '^AzureAD\\') { throw 'The signed-in account is not an AzureAD user.' }
    Write-Log "Detected logged-in user: $LoggedInUser"

    # Read the process owner SID to avoid ambiguous account-name resolution.
    $Process = Get-CimInstance -ClassName Win32_Process -Filter "ProcessId = $($Sessions[0].Id)" -ErrorAction Stop
    $Owner = Invoke-CimMethod -InputObject $Process -MethodName GetOwnerSid -ErrorAction Stop
    if ($Owner.ReturnValue -ne 0 -or $Owner.Sid -notmatch '^S-1-12-1-\d+-\d+-\d+-\d+$') {
        throw 'Unable to verify the Entra user SID.'
    }
    $UserSid = $Owner.Sid
    $TaskName = "$TaskPrefix$UserSid"
    $Members = @(Get-LocalGroupMember -SID 'S-1-5-32-544' -ErrorAction Stop)
    $ExistingTask = @(Get-ScheduledTask -TaskPath '\' -ErrorAction Stop | Where-Object { $_.TaskName -eq $TaskName })
    if ($ExistingTask.Count) {
        throw 'A removal task already exists for this user. Review it; this run will not extend or replace it.'
    }
    if ($Members | Where-Object { $_.SID.Value -eq $UserSid }) {
        Write-Log 'User was already a direct administrator. Existing access was left unchanged; no removal was scheduled.'
        Write-Output 'No change: user already has direct administrator membership.'
        exit 0
    }

    $ExpiryDate = (Get-Date).AddDays($DaysToKeep)
    # Encode the removal command so paths and spaces survive Task Scheduler quoting.
    $SafeLog = $LogFile.Replace("'", "''")
    $SafeTask = $TaskName.Replace("'", "''")
    $RemovalCommand = @'
$ErrorActionPreference = 'Stop'
$UserSid = '__USER_SID__'
$LogFile = '__LOG_FILE__'
$TaskName = '__TASK_NAME__'
try {
    Import-Module Microsoft.PowerShell.LocalAccounts -ErrorAction Stop
    Import-Module ScheduledTasks -ErrorAction Stop
    $Members = @(Get-LocalGroupMember -SID 'S-1-5-32-544' -ErrorAction Stop)
    if ($Members | Where-Object { $_.SID.Value -eq $UserSid }) {
        Remove-LocalGroupMember -SID 'S-1-5-32-544' -Member $UserSid -Confirm:$false -ErrorAction Stop
    }
    $Remaining = @(Get-LocalGroupMember -SID 'S-1-5-32-544' -ErrorAction Stop | Where-Object { $_.SID.Value -eq $UserSid })
    if ($Remaining.Count) { throw 'Administrator membership remains after removal.' }
    Add-Content -LiteralPath $LogFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Verified temporary admin removal: $UserSid" -ErrorAction Stop
    # Keep the task on error so scheduled retries can try again.
    Unregister-ScheduledTask -TaskName $TaskName -TaskPath '\' -Confirm:$false -ErrorAction Stop
    exit 0
}
catch {
    $Failure = $_.Exception.Message
    try { Add-Content -LiteralPath $LogFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Removal failed for ${UserSid}: $Failure" -ErrorAction Stop } catch { }
    Write-Output "Temporary admin removal failed: $Failure"
    exit 1
}
'@
    $RemovalCommand = $RemovalCommand.Replace('__USER_SID__', $UserSid).Replace('__LOG_FILE__', $SafeLog).Replace('__TASK_NAME__', $SafeTask)
    $EncodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($RemovalCommand))
    $PowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $Action = New-ScheduledTaskAction -Execute $PowerShell -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -EncodedCommand $EncodedCommand"
    # First attempt at expiry; repeat daily until successful removal deletes the task.
    $Trigger = New-ScheduledTaskTrigger -Daily -DaysInterval 1 -At $ExpiryDate
    $TaskPrincipal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $Settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 15) -ExecutionTimeLimit (New-TimeSpan -Minutes 5) -MultipleInstances IgnoreNew

    # Register removal BEFORE granting rights. Never overwrite a previous task.
    Register-ScheduledTask -TaskName $TaskName -TaskPath '\' -Action $Action -Trigger $Trigger -Principal $TaskPrincipal -Settings $Settings -Description "Temporary direct admin removal for $UserSid. Expires $($ExpiryDate.ToString('o'))." -ErrorAction Stop | Out-Null
    Write-Log "Removal task created: $TaskName. Expiry: $($ExpiryDate.ToString('o'))"
    Add-LocalGroupMember -SID 'S-1-5-32-544' -Member $UserSid -ErrorAction Stop
    $FinalMembers = @(Get-LocalGroupMember -SID 'S-1-5-32-544' -ErrorAction Stop)
    if (-not ($FinalMembers | Where-Object { $_.SID.Value -eq $UserSid })) { throw 'Administrator membership verification failed.' }
    Write-Log "$LoggedInUser [$UserSid] added to Administrators for $DaysToKeep day(s)."
    Write-Log '========== Script Completed Successfully =========='
    Write-Output "Temporary admin granted to $LoggedInUser. Scheduled expiry: $($ExpiryDate.ToString('u'))."
    exit 0
}
catch {
    $Failure = $_.Exception.Message
    try { Write-Log "ERROR: $Failure" } catch { }
    Write-Output "Temporary admin grant failed: $Failure"
    exit 1
}
