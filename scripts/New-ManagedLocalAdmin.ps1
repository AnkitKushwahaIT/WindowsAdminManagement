# ============================================================
# Windows - Create Local Administrator
# Account : LocalAdmin
# ============================================================

$ErrorActionPreference = "Stop"

$LogFolder = "C:\ProgramData\WindowsAdminManagement"
$LogFile   = Join-Path $LogFolder "Create-LocalAdmin.log"

$AdminUser     = "LocalAdmin"
$AdminPassword = 'ChangeMe!2026'

# ------------------------------------------------------------
# Logging
# ------------------------------------------------------------

if (-not (Test-Path $LogFolder)) {
    New-Item -Path $LogFolder -ItemType Directory -Force | Out-Null
}

function Write-Log {
    param (
        [string]$Message,
        [string]$Level = "INFO"
    )

    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $Entry = "[$Timestamp] [$Level] $Message"

    Add-Content -Path $LogFile -Value $Entry
}

Write-Log "============================================================"
Write-Log "Starting Windows local administrator creation"
Write-Log "Target account: $AdminUser"

try {

    # --------------------------------------------------------
    # Convert password to SecureString
    # --------------------------------------------------------

    $SecurePassword = ConvertTo-SecureString `
        $AdminPassword `
        -AsPlainText `
        -Force

    # --------------------------------------------------------
    # Check whether account already exists
    # --------------------------------------------------------

    $ExistingUser = Get-LocalUser `
        -Name $AdminUser `
        -ErrorAction SilentlyContinue

    if ($ExistingUser) {

        Write-Log "Account $AdminUser already exists."

        if (-not $ExistingUser.Enabled) {
            Enable-LocalUser -Name $AdminUser
            Write-Log "Account $AdminUser was disabled and has been enabled."
        }

        Set-LocalUser `
            -Name $AdminUser `
            -Password $SecurePassword

        Write-Log "Password updated for $AdminUser."

    }
    else {

        Write-Log "Account $AdminUser does not exist. Creating account."

        New-LocalUser `
            -Name $AdminUser `
            -Password $SecurePassword `
            -FullName "Windows Local Administrator" `
            -Description "Managed Windows local administrator account" `
            -PasswordNeverExpires:$true `
            -UserMayNotChangePassword:$true | Out-Null

        Write-Log "Account $AdminUser created successfully."
    }

    # --------------------------------------------------------
    # Add to local Administrators group
    # --------------------------------------------------------

    $AdminGroup = "Administrators"

    $IsMember = Get-LocalGroupMember `
        -Group $AdminGroup `
        -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -eq "$env:COMPUTERNAME\$AdminUser"
        }

    if (-not $IsMember) {

        Add-LocalGroupMember `
            -Group $AdminGroup `
            -Member $AdminUser

        Write-Log "$AdminUser added to local Administrators group."

    }
    else {

        Write-Log "$AdminUser is already a member of local Administrators."

    }

    # --------------------------------------------------------
    # Final verification
    # --------------------------------------------------------

    $VerifyUser = Get-LocalUser `
        -Name $AdminUser `
        -ErrorAction SilentlyContinue

    $VerifyMembership = Get-LocalGroupMember `
        -Group $AdminGroup `
        -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -eq "$env:COMPUTERNAME\$AdminUser"
        }

    if (-not $VerifyUser) {
        throw "Verification failed: $AdminUser account does not exist."
    }

    if (-not $VerifyUser.Enabled) {
        throw "Verification failed: $AdminUser account is disabled."
    }

    if (-not $VerifyMembership) {
        throw "Verification failed: $AdminUser is not a member of Administrators."
    }

    Write-Log "Verification successful."
    Write-Log "Account exists     : YES"
    Write-Log "Account enabled    : YES"
    Write-Log "Local administrator: YES"

    # --------------------------------------------------------
    # Completion marker
    # --------------------------------------------------------

    $CompletionFile = Join-Path `
        $LogFolder `
        "Create-LocalAdmin.completed"

    Set-Content `
        -Path $CompletionFile `
        -Value "LocalAdmin creation verified on $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

    Write-Log "Completion marker created."
    Write-Log "Windows local administrator creation completed successfully."
    Write-Log "============================================================"

    exit 0
}
catch {

    Write-Log "ERROR: $($_.Exception.Message)" "ERROR"
    Write-Log "Windows local administrator creation FAILED." "ERROR"
    Write-Log "============================================================"

    exit 1
}
