# =========================================================
# Local Administrator
# Version : 1.0.0
# Author  : IT Team
# =========================================================

$ErrorActionPreference = "Stop"

#-----------------------------------------------------------
# Configuration
#-----------------------------------------------------------

$AppName    = "Local Admin"
$AppVersion = "1.0.0"

$UserName   = "LocalAdmin"
$Password   = ConvertTo-SecureString '' -AsPlainText -Force
$Description = "Company Break Glass Local Administrator"

$RegistryPath = "HKLM:\SOFTWARE\CompanyIT\LocalAdmin"

#-----------------------------------------------------------
# Logging
#-----------------------------------------------------------

$LogFolder = "C:\CompanyIT"
$LogFile = Join-Path $LogFolder "approvedapps.log"

if (!(Test-Path $LogFolder)) {
    New-Item -Path $LogFolder -ItemType Directory -Force | Out-Null
}

function Write-Log {

    param([string]$Message)

    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $AppName $AppVersion - $Message" |
        Out-File $LogFile -Append -Encoding UTF8

}

Write-Log "========== Installation Started =========="

try {

    $User = Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue

    if ($null -eq $User) {

        Write-Log "Creating local user."

        New-LocalUser `
            -Name $UserName `
            -Password $Password `
            -PasswordNeverExpires `
            -UserMayNotChangePassword `
            -Description $Description | Out-Null

        Write-Log "User created."

    }
    else {

        Write-Log "User already exists."

        Set-LocalUser `
            -Name $UserName `
            -Password $Password

        Write-Log "Password updated."

    }

    #-------------------------------------------------------
    # Add to Local Administrators (Language Independent)
    #-------------------------------------------------------

    $AdminGroup = Get-LocalGroup -SID "S-1-5-32-544"

    try {

        Add-LocalGroupMember `
            -Group $AdminGroup `
            -Member $UserName `
            -ErrorAction Stop

        Write-Log "Added to Administrators group."

    }
    catch {

        Write-Log "User already member of Administrators."

    }

    Enable-LocalUser -Name $UserName

    #-------------------------------------------------------
    # Registry
    #-------------------------------------------------------

    if (!(Test-Path $RegistryPath)) {

        New-Item $RegistryPath -Force | Out-Null

    }

    New-ItemProperty `
        -Path $RegistryPath `
        -Name Version `
        -Value $AppVersion `
        -PropertyType String `
        -Force | Out-Null

    Write-Log "Registry updated."

    Write-Log "Installation completed successfully."

    exit 0

}
catch {

    Write-Log "ERROR : $($_.Exception.Message)"

    exit 1

}