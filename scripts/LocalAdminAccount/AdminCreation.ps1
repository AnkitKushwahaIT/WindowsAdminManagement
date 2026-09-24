#requires -Version 5.1
<#
.SYNOPSIS
Creates a package-owned break-glass local administrator.
.DESCRIPTION
Set InitialPassword in a private deployment copy before packaging. Existing owned
accounts are repaired without resetting passwords. Unowned accounts are refused.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidatePattern('^[A-Za-z][A-Za-z0-9_-]{0,19}$')]
    [string]$UserName = 'ManagedLocalAdmin',
    [string]$Description = 'Organization-managed local administrator',
    [string]$LogFolder = (Join-Path $env:ProgramData 'WindowsAdminManagement')
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
# ADMIN CONFIGURATION: fill this in only in your private deployment copy.
# Use a single-quoted string; double any apostrophe inside the password.
# Never commit the configured password to GitHub. It is used only for first creation.
$InitialPassword = ''
$version = '1.0.0'
$AppName = 'Managed Local Admin'
$LogFile = Join-Path $LogFolder 'approvedapps.log'
$logReady = $false

function Write-Log {
    param([string]$Message)
    if ($WhatIfPreference) { return }
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $AppName $version - $Message" |
        Out-File -LiteralPath $LogFile -Append -Encoding UTF8 -ErrorAction Stop
}

$registryPath = "HKLM:\SOFTWARE\WindowsAdminManagement\LocalAdminAccounts\$UserName"
try {
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { throw 'Use 64-bit Windows PowerShell.' }
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run elevated or as SYSTEM.' }
    if (-not $WhatIfPreference) {
        New-Item -Path $LogFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
        $logReady = $true
    }
    Write-Log '========== Installation Started =========='
    Write-Log "Target account: $UserName"
    Import-Module Microsoft.PowerShell.LocalAccounts -ErrorAction Stop
    # Enumerate rather than suppressing errors that could look like an absent account.
    $user = @(Get-LocalUser -ErrorAction Stop | Where-Object { $_.Name -eq $UserName })
    $members = @(Get-LocalGroupMember -SID 'S-1-5-32-544' -ErrorAction Stop)
    $record = $null
    if (Test-Path -LiteralPath $registryPath) { $record = Get-ItemProperty -LiteralPath $registryPath -ErrorAction Stop }
    if ($user.Count -gt 1) { throw 'Ambiguous local account lookup.' }
    if ($user.Count -eq 1) {
        if (-not $record -or $record.AccountSid -ne $user[0].SID.Value) { throw 'Existing account is not owned by this package; no changes made.' }
        if ($user[0].SID.Value -match '-500$') { throw 'The built-in Administrator is outside this package scope.' }
        Write-Log 'Owned account already exists. Password will not be changed.'
    }
    else {
        if ($record) { throw 'Ownership record exists but the account is missing. Review and uninstall stale state before recreating.' }
        if ([string]::IsNullOrWhiteSpace($InitialPassword)) { throw 'Set InitialPassword in your private script copy before first creation.' }
    }
    if (-not $PSCmdlet.ShouldProcess($UserName, 'Create or repair package-owned local administrator')) { exit 0 }
    if ($user.Count -eq 0) {
        Write-Log 'Creating local user with a non-expiring password.'
        $securePassword = ConvertTo-SecureString -String $InitialPassword -AsPlainText -Force
        try {
            $created = New-LocalUser -Name $UserName -Password $securePassword -Description $Description -PasswordNeverExpires -Disabled -ErrorAction Stop
        }
        finally { $securePassword.Dispose() }
        Write-Log 'User created in disabled state.'
        # Record the immutable SID before granting privileges. Version is written only after verification.
        New-Item -Path $registryPath -Force -ErrorAction Stop | Out-Null
        New-ItemProperty -LiteralPath $registryPath -Name AccountSid -Value $created.SID.Value -PropertyType String -Force -ErrorAction Stop | Out-Null
        $accountSid = $created.SID.Value
        Write-Log 'Account ownership recorded.'
    }
    else { $accountSid = $user[0].SID.Value }
    if (-not ($members | Where-Object { $_.SID.Value -eq $accountSid })) {
        Add-LocalGroupMember -SID 'S-1-5-32-544' -Member $accountSid -ErrorAction Stop
        Write-Log 'Added to Administrators group.'
    }
    else { Write-Log 'User already belongs to Administrators group.' }
    Enable-LocalUser -SID $accountSid -ErrorAction Stop
    Write-Log 'User enabled.'
    $verifiedUser = Get-LocalUser -SID $accountSid -ErrorAction Stop
    $verifiedMembers = @(Get-LocalGroupMember -SID 'S-1-5-32-544' -ErrorAction Stop)
    if (-not $verifiedUser.Enabled -or $verifiedUser.Name -ne $UserName -or -not ($verifiedMembers | Where-Object { $_.SID.Value -eq $accountSid })) {
        throw 'Account or administrator membership verification failed.'
    }
    New-ItemProperty -LiteralPath $registryPath -Name Version -Value $version -PropertyType String -Force -ErrorAction Stop | Out-Null
    Write-Log 'Verification successful. Registry version updated.'
    Write-Log '========== Installation Completed Successfully =========='
    Write-Output "Installed: $UserName is enabled and a direct local administrator. Version $version."
    exit 0
}
catch {
    $failure = $_.Exception.Message
    if ($logReady) {
        try { Write-Log "ERROR: $failure" }
        catch { Write-Output 'Unable to write the error to the log file.' }
    }
    Write-Output "Installation failed: $failure"
    exit 1
}
