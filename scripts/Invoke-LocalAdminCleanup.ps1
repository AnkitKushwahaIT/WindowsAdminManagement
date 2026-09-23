<#
============================================================
WindowsAdminManagement - Local Administrator Cleanup / Enforcement
Purpose:
  1. Retain only approved local administrator accounts
  2. Remove unauthorized accounts and orphaned SIDs from Administrators
  3. Optionally deny local interactive logon to unauthorized accounts
Designed for Microsoft Intune deployment (System Context)
============================================================
#>

[CmdletBinding()]
param (
    [string]$LogFolder = "C:\ProgramData\WindowsAdminManagement",
    [string[]]$ApprovedAdmins = @(
        "LocalAdmin",      # Standard managed local admin
        "LAPSAdmin"        # Windows LAPS managed admin
    ),
    [switch]$PreserveEntraAdmins = $true,  # Keep Azure AD / Entra ID Cloud Device Admins
    [switch]$EnforceDenyLocalLogon = $false # Configure SeDenyInteractiveLogonRight
)

$ErrorActionPreference = "Stop"
$LogFile = Join-Path $LogFolder "LocalAdminCleanup.log"
$AdministratorsGroup = "Administrators"

# ------------------------------------------------------------
# Logging Helper
# ------------------------------------------------------------
if (-not (Test-Path -LiteralPath $LogFolder)) {
    New-Item -Path $LogFolder -ItemType Directory -Force | Out-Null
}

function Write-Log {
    param (
        [Parameter(Mandatory)]
        [string]$Message,
        [ValidateSet("INFO","WARN","ERROR")]
        [string]$Level = "INFO"
    )
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $Entry = "[$Timestamp] [$Level] $Message"
    Add-Content -LiteralPath $LogFile -Value $Entry
}

Write-Log "============================================================"
Write-Log "Starting local administrator cleanup and enforcement"
Write-Log "Approved administrators: $($ApprovedAdmins -join ', ')"

try {
    # --------------------------------------------------------
    # Verify Administrator Privileges
    # --------------------------------------------------------
    $CurrentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $Principal = [Security.Principal.WindowsPrincipal]::new($CurrentIdentity)
    if (-not $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Script is not running with elevated administrative privileges."
    }

    # --------------------------------------------------------
    # Enumerate Administrators via ADSI (Bypasses Get-LocalGroupMember bugs)
    # --------------------------------------------------------
    $AdminGroupADSI = [ADSI]"WinNT://./$AdministratorsGroup,group"
    $Members = @($AdminGroupADSI.Invoke("Members"))

    if (-not $Members -or $Members.Count -eq 0) {
        Write-Log "No members discovered in $AdministratorsGroup." "WARN"
    }

    # Identify built-in Administrator SID (Well-Known SID ending in -500)
    $BuiltInAdminSid = (Get-LocalUser | Where-Object { $_.SID.Value -like "S-1-5-21-*-500" }).SID.Value

    foreach ($Member in $Members) {
        $MemberPath = $Member.GetType().InvokeMember("AdsPath", "GetProperty", $null, $Member, $null)
        $MemberName = $Member.GetType().InvokeMember("Name", "GetProperty", $null, $Member, $null)

        # Retrieve SID if available
        $MemberSID = $null
        try {
            $ObjectBytes = $Member.GetType().InvokeMember("objectSid", "GetProperty", $null, $Member, $null)
            if ($ObjectBytes) {
                $MemberSID = (New-Object System.Security.Principal.SecurityIdentifier($ObjectBytes, 0)).Value
            }
        }
        catch {
            $MemberSID = $null
        }

        Write-Log "Evaluating member: Name='$MemberName', SID='$MemberSID', Path='$MemberPath'"

        # 1. Protect Built-in Administrator (-500)
        if ($MemberSID -and $MemberSID -eq $BuiltInAdminSid) {
            Write-Log "Account is built-in Administrator ($MemberName / $MemberSID). Protected." "INFO"
            continue
        }

        # 2. Protect Entra ID / Azure AD Role SIDs (S-1-12-1-*)
        if ($PreserveEntraAdmins -and $MemberSID -and $MemberSID -like "S-1-12-1-*") {
            Write-Log "Account is an Entra ID / Cloud Administrator SID ($MemberSID). Keeping." "INFO"
            continue
        }

        # 3. Check Approved List
        if ($ApprovedAdmins -contains $MemberName) {
            Write-Log "$MemberName is explicitly approved. Keeping." "INFO"
            continue
        }

        # 4. Remove Unauthorized Member / Orphaned SID
        try {
            Write-Log "Removing unauthorized member: $MemberName ($MemberPath)" "WARN"
            $AdminGroupADSI.Remove($MemberPath)
            Write-Log "Successfully removed: $MemberName ($MemberPath)" "INFO"
        }
        catch {
            Write-Log "Failed to remove $MemberName : $($_.Exception.Message)" "ERROR"
        }
    }

    # --------------------------------------------------------
    # Purpose 3: Deny Local Interactive Logon (Optional)
    # --------------------------------------------------------
    if ($EnforceDenyLocalLogon) {
        Write-Log "Configuring SeDenyInteractiveLogonRight..." "INFO"
        # Best configured via Intune Settings Catalog -> User Rights Assignment -> Deny log on locally
        # Fallback via secedit if needed:
        $SecTemplate = Join-Path $env:TEMP "deny_logon.inf"
        $SecDb       = Join-Path $env:TEMP "deny_logon.sdb"
        
        $InfContent = @"
[Unicode]
Unicode=yes
[Version]
signature="`$CHICAGO`$"
Revision=1
[Privilege Rights]
SeDenyInteractiveLogonRight = *S-1-5-32-545
"@
        Set-Content -Path $SecTemplate -Value $InfContent -Encoding Unicode
        $SecProc = Start-Process -FilePath "secedit.exe" -ArgumentList "/configure /db `"$SecDb`" /cfg `"$SecTemplate`" /areas USER_RIGHTS /quiet" -Wait -PassThru
        if ($SecProc.ExitCode -eq 0) {
            Write-Log "Deny local interactive logon policy applied successfully." "INFO"
        } else {
            Write-Log "secedit returned non-zero code: $($SecProc.ExitCode)" "WARN"
        }
        Remove-Item -Path $SecTemplate, $SecDb -Force -ErrorAction SilentlyContinue
    }

    # --------------------------------------------------------
    # Completion Marker
    # --------------------------------------------------------
    $CompletionFile = Join-Path $LogFolder "LocalAdminCleanup.completed"
    Set-Content -LiteralPath $CompletionFile -Value "Cleanup completed on $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-Log "Completion marker created."
    Write-Log "Local administrator cleanup completed successfully."
    Write-Log "============================================================"
    exit 0
}
catch {
    Write-Log "FATAL ERROR: $($_.Exception.Message)" "ERROR"
    Write-Log "Local administrator cleanup FAILED." "ERROR"
    Write-Log "============================================================"
    exit 1
}
